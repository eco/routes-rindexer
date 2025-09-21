# Materialized Views and Queue-based Balance Updates Plan

## Overview

This plan details the implementation of efficient, queue-based materialized view updates for ERC20 token balance tracking across all 34 supported chains in the Eco Foundation rindexer project. This approach ensures consistent performance and scalability regardless of token volume.

---

## Phase 1: Database Schema Design

### 1.1 Core Balance Tracking Tables

```sql
-- Real-time balance summary table (replaces full materialized view refreshes)
CREATE TABLE current_token_balances (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    holder_address VARCHAR(42) NOT NULL,
    current_balance NUMERIC(78, 0) NOT NULL DEFAULT 0,
    last_updated_block BIGINT NOT NULL,
    last_updated_time TIMESTAMP DEFAULT NOW(),
    token_symbol VARCHAR(20),
    token_decimals INTEGER DEFAULT 18,
    balance_usd NUMERIC(18, 6), -- Optional USD value
    UNIQUE(chain_id, contract_address, holder_address)
);

-- Performance indexes for balance queries
CREATE INDEX idx_token_balances_holder ON current_token_balances (holder_address);
CREATE INDEX idx_token_balances_contract ON current_token_balances (chain_id, contract_address);
CREATE INDEX idx_token_balances_composite ON current_token_balances (chain_id, contract_address, holder_address);
CREATE INDEX idx_token_balances_symbol ON current_token_balances (token_symbol, current_balance DESC);
CREATE INDEX idx_token_balances_usd ON current_token_balances (balance_usd DESC) WHERE balance_usd > 0;

-- Partition by chain_id for better performance across 34 chains
CREATE TABLE current_token_balances_ethereum
    PARTITION OF current_token_balances FOR VALUES (1);
CREATE TABLE current_token_balances_arbitrum
    PARTITION OF current_token_balances FOR VALUES (42161);
CREATE TABLE current_token_balances_base
    PARTITION OF current_token_balances FOR VALUES (8453);
CREATE TABLE current_token_balances_polygon
    PARTITION OF current_token_balances FOR VALUES (137);
CREATE TABLE current_token_balances_optimism
    PARTITION OF current_token_balances FOR VALUES (10);
-- Additional partitions for all 34 chains...
```

### 1.2 Queue-based Update System

```sql
-- Balance update queue for all chains (consistent approach)
CREATE TABLE balance_update_queue (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    holder_address VARCHAR(42) NOT NULL,
    update_type VARCHAR(20) NOT NULL, -- 'transfer_in', 'transfer_out', 'recalculate'
    triggered_by_tx VARCHAR(66),
    triggered_by_block BIGINT,
    priority INTEGER DEFAULT 5, -- 1=highest, 10=lowest
    created_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP NULL,
    status VARCHAR(20) DEFAULT 'pending',
    retry_count INTEGER DEFAULT 0,
    error_message TEXT,
    processing_duration_ms INTEGER
);

-- Indexes for efficient queue processing
CREATE INDEX idx_balance_queue_pending ON balance_update_queue (status, priority, created_at)
WHERE status = 'pending';

CREATE INDEX idx_balance_queue_chain_contract ON balance_update_queue (chain_id, contract_address)
WHERE status = 'pending';

CREATE INDEX idx_balance_queue_retry ON balance_update_queue (retry_count, created_at)
WHERE status = 'error' AND retry_count < 3;

-- Partition queue by chain_id for better performance
CREATE TABLE balance_update_queue_ethereum
    PARTITION OF balance_update_queue FOR VALUES (1);
CREATE TABLE balance_update_queue_arbitrum
    PARTITION OF balance_update_queue FOR VALUES (42161);
-- Additional queue partitions for all 34 chains...
```

### 1.3 Historical Balance Snapshots

```sql
-- Daily balance snapshots for historical analysis
CREATE TABLE daily_balance_snapshots (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    holder_address VARCHAR(42) NOT NULL,
    balance NUMERIC(78, 0) NOT NULL,
    balance_usd NUMERIC(18, 6),
    snapshot_date DATE NOT NULL,
    snapshot_block BIGINT NOT NULL,
    token_symbol VARCHAR(20),
    UNIQUE(chain_id, contract_address, holder_address, snapshot_date)
);

-- Index for efficient historical queries
CREATE INDEX idx_daily_snapshots_date ON daily_balance_snapshots (snapshot_date DESC);
CREATE INDEX idx_daily_snapshots_holder ON daily_balance_snapshots (holder_address, snapshot_date DESC);
```

---

## Phase 2: Queue Processing Functions

### 2.1 Core Balance Calculation Function

```sql
-- Recalculate balance for a specific address and token on a specific chain
CREATE OR REPLACE FUNCTION recalculate_address_balance(
    p_chain_id INTEGER,
    p_contract_address VARCHAR(42),
    p_holder_address VARCHAR(42)
)
RETURNS NUMERIC(78, 0) AS $$
DECLARE
    v_balance NUMERIC(78, 0);
    v_max_block BIGINT;
    v_token_symbol VARCHAR(20);
    v_token_decimals INTEGER;
    v_stable_transfers_table TEXT;
BEGIN
    -- Dynamically determine table name based on chain_id and contract
    -- This would be adapted based on rindexer's actual table naming convention
    v_stable_transfers_table := format('stable_transfers_%s', p_chain_id);

    -- Calculate current balance from all transfer events
    EXECUTE format('
        WITH balance_calculation AS (
            SELECT
                SUM(CASE
                    WHEN to_address = $1 THEN value::NUMERIC
                    WHEN from_address = $1 THEN -value::NUMERIC
                    ELSE 0
                END) as calculated_balance,
                MAX(block_number) as max_block
            FROM %I
            WHERE (from_address = $1 OR to_address = $1)
              AND contract_address = $2
        )
        SELECT COALESCE(calculated_balance, 0), COALESCE(max_block, 0)
        FROM balance_calculation
    ', v_stable_transfers_table)
    INTO v_balance, v_max_block
    USING p_holder_address, p_contract_address;

    -- Get token metadata (this would be populated from contract data)
    SELECT
        symbol,
        decimals
    INTO v_token_symbol, v_token_decimals
    FROM token_metadata
    WHERE chain_id = p_chain_id AND contract_address = p_contract_address;

    -- Default fallback for unknown tokens
    IF v_token_symbol IS NULL THEN
        v_token_symbol := 'UNKNOWN';
        v_token_decimals := 18;
    END IF;

    -- Upsert the balance record
    INSERT INTO current_token_balances (
        chain_id,
        contract_address,
        holder_address,
        current_balance,
        last_updated_block,
        last_updated_time,
        token_symbol,
        token_decimals
    )
    VALUES (
        p_chain_id,
        p_contract_address,
        p_holder_address,
        v_balance,
        v_max_block,
        NOW(),
        v_token_symbol,
        v_token_decimals
    )
    ON CONFLICT (chain_id, contract_address, holder_address)
    DO UPDATE SET
        current_balance = EXCLUDED.current_balance,
        last_updated_block = EXCLUDED.last_updated_block,
        last_updated_time = EXCLUDED.last_updated_time,
        token_symbol = EXCLUDED.token_symbol,
        token_decimals = EXCLUDED.token_decimals;

    RETURN v_balance;
END;
$$ LANGUAGE plpgsql;
```

### 2.2 Queue Management Functions

```sql
-- Queue balance updates for async processing (used for ALL chains)
CREATE OR REPLACE FUNCTION queue_balance_update(
    p_chain_id INTEGER,
    p_contract_address VARCHAR(42),
    p_holder_address VARCHAR(42),
    p_update_type VARCHAR(20),
    p_tx_hash VARCHAR(66) DEFAULT NULL,
    p_block_number BIGINT DEFAULT NULL,
    p_priority INTEGER DEFAULT 5
)
RETURNS BIGINT AS $$
DECLARE
    v_queue_id BIGINT;
BEGIN
    INSERT INTO balance_update_queue (
        chain_id,
        contract_address,
        holder_address,
        update_type,
        triggered_by_tx,
        triggered_by_block,
        priority
    )
    VALUES (
        p_chain_id,
        p_contract_address,
        p_holder_address,
        p_update_type,
        p_tx_hash,
        p_block_number,
        p_priority
    )
    RETURNING id INTO v_queue_id;

    RETURN v_queue_id;
END;
$$ LANGUAGE plpgsql;

-- Batch process queued balance updates with error handling and retries
CREATE OR REPLACE FUNCTION process_balance_update_queue(
    p_batch_size INTEGER DEFAULT 100,
    p_chain_id INTEGER DEFAULT NULL -- Process specific chain or all chains
)
RETURNS TABLE(
    processed_count INTEGER,
    error_count INTEGER,
    avg_processing_time_ms NUMERIC
) AS $$
DECLARE
    v_processed_count INTEGER := 0;
    v_error_count INTEGER := 0;
    v_total_processing_time BIGINT := 0;
    v_record RECORD;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_processing_duration INTEGER;
    v_new_balance NUMERIC(78, 0);
BEGIN
    -- Process pending balance updates in batches
    FOR v_record IN
        SELECT id, chain_id, contract_address, holder_address, update_type
        FROM balance_update_queue
        WHERE status = 'pending'
          AND (p_chain_id IS NULL OR chain_id = p_chain_id)
        ORDER BY priority ASC, created_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    LOOP
        v_start_time := NOW();

        BEGIN
            -- Recalculate the balance
            v_new_balance := recalculate_address_balance(
                v_record.chain_id,
                v_record.contract_address,
                v_record.holder_address
            );

            v_end_time := NOW();
            v_processing_duration := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;

            -- Mark as processed
            UPDATE balance_update_queue
            SET
                status = 'completed',
                processed_at = v_end_time,
                processing_duration_ms = v_processing_duration
            WHERE id = v_record.id;

            v_processed_count := v_processed_count + 1;
            v_total_processing_time := v_total_processing_time + v_processing_duration;

        EXCEPTION WHEN OTHERS THEN
            -- Handle errors with retry logic
            UPDATE balance_update_queue
            SET
                status = CASE
                    WHEN retry_count < 3 THEN 'pending'
                    ELSE 'failed'
                END,
                retry_count = retry_count + 1,
                error_message = SQLERRM,
                processed_at = CASE
                    WHEN retry_count >= 3 THEN NOW()
                    ELSE NULL
                END
            WHERE id = v_record.id;

            v_error_count := v_error_count + 1;
        END;
    END LOOP;

    -- Return processing statistics
    RETURN QUERY SELECT
        v_processed_count,
        v_error_count,
        CASE
            WHEN v_processed_count > 0 THEN v_total_processing_time::NUMERIC / v_processed_count
            ELSE 0::NUMERIC
        END;
END;
$$ LANGUAGE plpgsql;
```

### 2.3 Trigger Functions for Automatic Queue Population

```sql
-- Trigger function to queue balance updates when new transfer events are inserted
-- This replaces immediate balance calculation with queue-based processing
CREATE OR REPLACE FUNCTION trigger_queue_balance_update()
RETURNS TRIGGER AS $$
DECLARE
    v_chain_id INTEGER;
BEGIN
    -- Extract chain_id from table name or use network mapping
    -- This assumes rindexer provides chain context in the trigger
    v_chain_id := TG_ARGV[0]::INTEGER; -- Pass chain_id as trigger argument

    -- Queue balance update for the 'from' address (if not burn address)
    IF NEW.from_address != '0x0000000000000000000000000000000000000000' THEN
        PERFORM queue_balance_update(
            v_chain_id,
            NEW.contract_address,
            NEW.from_address,
            'transfer_out',
            NEW.transaction_hash,
            NEW.block_number,
            3 -- Higher priority for recent transfers
        );
    END IF;

    -- Queue balance update for the 'to' address (if not burn address)
    IF NEW.to_address != '0x0000000000000000000000000000000000000000' THEN
        PERFORM queue_balance_update(
            v_chain_id,
            NEW.contract_address,
            NEW.to_address,
            'transfer_in',
            NEW.transaction_hash,
            NEW.block_number,
            3 -- Higher priority for recent transfers
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for each chain's stable transfer table
-- Example triggers (would be created for all 34 chains):

-- Ethereum (Chain ID 1)
CREATE TRIGGER tr_ethereum_stable_transfers_queue_update
    AFTER INSERT ON stable_transfers_ethereum
    FOR EACH ROW
    EXECUTE FUNCTION trigger_queue_balance_update('1');

-- Arbitrum (Chain ID 42161)
CREATE TRIGGER tr_arbitrum_stable_transfers_queue_update
    AFTER INSERT ON stable_transfers_arbitrum
    FOR EACH ROW
    EXECUTE FUNCTION trigger_queue_balance_update('42161');

-- Base (Chain ID 8453)
CREATE TRIGGER tr_base_stable_transfers_queue_update
    AFTER INSERT ON stable_transfers_base
    FOR EACH ROW
    EXECUTE FUNCTION trigger_queue_balance_update('8453');

-- Polygon (Chain ID 137)
CREATE TRIGGER tr_polygon_stable_transfers_queue_update
    AFTER INSERT ON stable_transfers_polygon
    FOR EACH ROW
    EXECUTE FUNCTION trigger_queue_balance_update('137');

-- Optimism (Chain ID 10)
CREATE TRIGGER tr_optimism_stable_transfers_queue_update
    AFTER INSERT ON stable_transfers_optimism
    FOR EACH ROW
    EXECUTE FUNCTION trigger_queue_balance_update('10');

-- Additional triggers for all 34 chains...
```

---

## Phase 3: Token Metadata Management

### 3.1 Token Metadata Table

```sql
-- Store token metadata for all tracked ERC20 tokens across all chains
CREATE TABLE token_metadata (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    name VARCHAR(100),
    decimals INTEGER NOT NULL DEFAULT 18,
    is_stable_token BOOLEAN DEFAULT FALSE,
    coingecko_id VARCHAR(50), -- For price data integration
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(chain_id, contract_address)
);

-- Index for efficient metadata lookups
CREATE INDEX idx_token_metadata_chain_contract ON token_metadata (chain_id, contract_address);
CREATE INDEX idx_token_metadata_symbol ON token_metadata (symbol);
CREATE INDEX idx_token_metadata_stable ON token_metadata (is_stable_token) WHERE is_stable_token = TRUE;

-- Pre-populate with Eco Foundation defined stable tokens
INSERT INTO token_metadata (chain_id, contract_address, symbol, name, decimals, is_stable_token, coingecko_id) VALUES
-- Ethereum stable tokens
(1, '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48', 'USDC', 'USD Coin', 6, TRUE, 'usd-coin'),
(1, '0xdac17f958d2ee523a2206206994597c13d831ec7', 'USDT', 'Tether USD', 6, TRUE, 'tether'),
(1, '0x6b175474e89094c44da98b954eedeac495271d0f', 'DAI', 'Dai Stablecoin', 18, TRUE, 'dai'),
(1, '0x1217bfe6c773eec6cc4a38b5dc45b92292b6e189', 'oUSDT', 'Origin USDT', 18, TRUE, NULL),

-- Arbitrum stable tokens
(42161, '0xaf88d065e77c8cc2239327c5edb3a432268e5831', 'USDC', 'USD Coin', 6, TRUE, 'usd-coin'),
(42161, '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8', 'USDCe', 'Bridged USDC', 6, TRUE, 'usd-coin'),

-- Base stable tokens
(8453, '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913', 'USDC', 'USD Coin', 6, TRUE, 'usd-coin'),
(8453, '0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA', 'USDbC', 'USD Base Coin', 6, TRUE, NULL),

-- Polygon stable tokens
(137, '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359', 'USDC', 'USD Coin', 6, TRUE, 'usd-coin'),
(137, '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', 'USDCe', 'Bridged USDC', 6, TRUE, 'usd-coin'),
(137, '0xc2132d05d31c914a87c6611c10748aeb04b58e8f', 'USDT', 'Tether USD', 6, TRUE, 'tether'),

-- Optimism stable tokens
(10, '0x0b2c639c533813f4aa9d7837caf62653d097ff85', 'USDC', 'USD Coin', 6, TRUE, 'usd-coin'),
(10, '0x7F5c764cBc14f9669B88837ca1490cCa17c31607', 'USDCe', 'Bridged USDC', 6, TRUE, 'usd-coin'),
(10, '0x94b008aA00579c1307B0EF2c499aD98a8ce58e58', 'USDT', 'Tether USD', 6, TRUE, 'tether');
-- Additional stable tokens for all 34 chains based on @eco-foundation/chains package...
```

---

## Phase 4: Background Queue Processing Service

### 4.1 Queue Worker Configuration

```sql
-- Configuration table for queue processing parameters
CREATE TABLE queue_processing_config (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER,
    batch_size INTEGER DEFAULT 100,
    processing_interval_seconds INTEGER DEFAULT 5,
    max_retry_attempts INTEGER DEFAULT 3,
    priority_boost_threshold_hours INTEGER DEFAULT 1, -- Boost priority for old items
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Default configuration for all chains (can be customized per chain)
INSERT INTO queue_processing_config (chain_id, batch_size, processing_interval_seconds) VALUES
(1, 200, 3),     -- Ethereum: Higher batch size, faster processing
(42161, 150, 3), -- Arbitrum: High volume
(8453, 150, 3),  -- Base: High volume
(137, 200, 3),   -- Polygon: Highest volume
(10, 150, 3),    -- Optimism: High volume
-- Standard configuration for remaining chains
(146, 100, 5),   -- Sonic
(5330, 100, 5),  -- Superseed
(480, 100, 5),   -- World Chain
(57073, 100, 5); -- Ink
-- Additional configurations for all 34 chains...

-- Function to get processing configuration
CREATE OR REPLACE FUNCTION get_queue_config(p_chain_id INTEGER)
RETURNS TABLE(
    batch_size INTEGER,
    processing_interval_seconds INTEGER,
    max_retry_attempts INTEGER,
    enabled BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        qpc.batch_size,
        qpc.processing_interval_seconds,
        qpc.max_retry_attempts,
        qpc.enabled
    FROM queue_processing_config qpc
    WHERE qpc.chain_id = p_chain_id OR qpc.chain_id IS NULL
    ORDER BY qpc.chain_id NULLS LAST
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;
```

### 4.2 Queue Health Monitoring

```sql
-- Queue health metrics table
CREATE TABLE queue_health_metrics (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER,
    pending_count INTEGER,
    processing_count INTEGER,
    completed_count_last_hour INTEGER,
    error_count_last_hour INTEGER,
    avg_processing_time_ms NUMERIC,
    oldest_pending_age_minutes INTEGER,
    recorded_at TIMESTAMP DEFAULT NOW()
);

-- Function to collect queue health metrics
CREATE OR REPLACE FUNCTION collect_queue_health_metrics()
RETURNS void AS $$
DECLARE
    v_chain_record RECORD;
BEGIN
    -- Clear old metrics (keep last 24 hours)
    DELETE FROM queue_health_metrics WHERE recorded_at < NOW() - INTERVAL '24 hours';

    -- Collect metrics for each chain
    FOR v_chain_record IN
        SELECT DISTINCT chain_id FROM balance_update_queue
    LOOP
        INSERT INTO queue_health_metrics (
            chain_id,
            pending_count,
            processing_count,
            completed_count_last_hour,
            error_count_last_hour,
            avg_processing_time_ms,
            oldest_pending_age_minutes
        )
        SELECT
            v_chain_record.chain_id,
            COUNT(*) FILTER (WHERE status = 'pending'),
            COUNT(*) FILTER (WHERE status = 'processing'),
            COUNT(*) FILTER (WHERE status = 'completed' AND processed_at > NOW() - INTERVAL '1 hour'),
            COUNT(*) FILTER (WHERE status IN ('error', 'failed') AND processed_at > NOW() - INTERVAL '1 hour'),
            AVG(processing_duration_ms) FILTER (WHERE status = 'completed' AND processed_at > NOW() - INTERVAL '1 hour'),
            EXTRACT(EPOCH FROM (NOW() - MIN(created_at) FILTER (WHERE status = 'pending'))) / 60
        FROM balance_update_queue
        WHERE chain_id = v_chain_record.chain_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- View for queue health dashboard
CREATE VIEW queue_health_summary AS
SELECT
    qhm.chain_id,
    tm.name as chain_name,
    qhm.pending_count,
    qhm.processing_count,
    qhm.completed_count_last_hour,
    qhm.error_count_last_hour,
    ROUND(qhm.avg_processing_time_ms, 2) as avg_processing_time_ms,
    qhm.oldest_pending_age_minutes,
    CASE
        WHEN qhm.pending_count > 1000 THEN 'HIGH_LOAD'
        WHEN qhm.oldest_pending_age_minutes > 60 THEN 'DELAYED'
        WHEN qhm.error_count_last_hour > 50 THEN 'ERRORS'
        ELSE 'HEALTHY'
    END as health_status,
    qhm.recorded_at
FROM queue_health_metrics qhm
LEFT JOIN (
    SELECT DISTINCT chain_id,
    CASE chain_id
        WHEN 1 THEN 'ethereum'
        WHEN 42161 THEN 'arbitrum'
        WHEN 8453 THEN 'base'
        WHEN 137 THEN 'polygon'
        WHEN 10 THEN 'optimism'
        -- Add mappings for all 34 chains
        ELSE 'unknown'
    END as name
    FROM balance_update_queue
) tm ON qhm.chain_id = tm.chain_id
WHERE qhm.recorded_at = (
    SELECT MAX(recorded_at)
    FROM queue_health_metrics qhm2
    WHERE qhm2.chain_id = qhm.chain_id
);
```

---

## Phase 5: API Integration and Query Optimization

### 5.1 Optimized Balance Query Functions

```sql
-- Get current balance for a specific address and token
CREATE OR REPLACE FUNCTION get_current_balance(
    p_chain_id INTEGER,
    p_contract_address VARCHAR(42),
    p_holder_address VARCHAR(42)
)
RETURNS TABLE(
    balance NUMERIC(78, 0),
    balance_formatted TEXT,
    balance_usd NUMERIC(18, 6),
    token_symbol VARCHAR(20),
    last_updated_block BIGINT,
    last_updated_time TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ctb.current_balance,
        FORMAT_TOKEN_BALANCE(ctb.current_balance, ctb.token_decimals) as balance_formatted,
        ctb.balance_usd,
        ctb.token_symbol,
        ctb.last_updated_block,
        ctb.last_updated_time
    FROM current_token_balances ctb
    WHERE ctb.chain_id = p_chain_id
      AND ctb.contract_address = p_contract_address
      AND ctb.holder_address = p_holder_address
      AND ctb.current_balance > 0;
END;
$$ LANGUAGE plpgsql;

-- Get all token balances for a specific address across all chains
CREATE OR REPLACE FUNCTION get_address_portfolio(
    p_holder_address VARCHAR(42),
    p_min_balance_usd NUMERIC DEFAULT 1.00
)
RETURNS TABLE(
    chain_id INTEGER,
    chain_name TEXT,
    contract_address VARCHAR(42),
    token_symbol VARCHAR(20),
    balance NUMERIC(78, 0),
    balance_formatted TEXT,
    balance_usd NUMERIC(18, 6),
    last_updated_time TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ctb.chain_id,
        CASE ctb.chain_id
            WHEN 1 THEN 'ethereum'
            WHEN 42161 THEN 'arbitrum'
            WHEN 8453 THEN 'base'
            WHEN 137 THEN 'polygon'
            WHEN 10 THEN 'optimism'
            -- Add mappings for all 34 chains
            ELSE 'unknown'
        END as chain_name,
        ctb.contract_address,
        ctb.token_symbol,
        ctb.current_balance,
        FORMAT_TOKEN_BALANCE(ctb.current_balance, ctb.token_decimals) as balance_formatted,
        ctb.balance_usd,
        ctb.last_updated_time
    FROM current_token_balances ctb
    WHERE ctb.holder_address = p_holder_address
      AND ctb.current_balance > 0
      AND (p_min_balance_usd = 0 OR ctb.balance_usd >= p_min_balance_usd)
    ORDER BY ctb.balance_usd DESC NULLS LAST, ctb.current_balance DESC;
END;
$$ LANGUAGE plpgsql;

-- Helper function to format token balances with proper decimals
CREATE OR REPLACE FUNCTION format_token_balance(
    p_balance NUMERIC(78, 0),
    p_decimals INTEGER
)
RETURNS TEXT AS $$
BEGIN
    RETURN TRIM(TO_CHAR(p_balance / POWER(10, p_decimals), 'FM999999999999999990.999999'));
END;
$$ LANGUAGE plpgsql;
```

### 5.2 GraphQL Schema Extensions

```graphql
# Extended GraphQL types for materialized view integration
extend type Query {
  # Get current balance for specific address and token
  currentBalance(
    chainId: Int!
    contractAddress: String!
    holderAddress: String!
  ): TokenBalance

  # Get complete portfolio for an address across all chains
  addressPortfolio(
    holderAddress: String!
    minBalanceUsd: Float = 1.0
  ): [TokenBalance!]!

  # Get top holders for a specific token
  topHolders(
    chainId: Int!
    contractAddress: String!
    limit: Int = 100
  ): [TokenBalance!]!

  # Get queue health metrics
  queueHealth: [QueueHealthMetric!]!
}

type TokenBalance {
  chainId: Int!
  chainName: String!
  contractAddress: String!
  holderAddress: String!
  tokenSymbol: String!
  balance: String! # Raw balance as string to avoid precision loss
  balanceFormatted: String! # Human-readable formatted balance
  balanceUsd: Float
  lastUpdatedBlock: String!
  lastUpdatedTime: String!
}

type QueueHealthMetric {
  chainId: Int!
  chainName: String!
  pendingCount: Int!
  processingCount: Int!
  completedCountLastHour: Int!
  errorCountLastHour: Int!
  avgProcessingTimeMs: Float!
  oldestPendingAgeMinutes: Int
  healthStatus: String! # HEALTHY, HIGH_LOAD, DELAYED, ERRORS
  recordedAt: String!
}
```

---

## Phase 6: Implementation Timeline

### Week 1: Database Schema Setup
- **Days 1-2**: Create core tables (current_token_balances, balance_update_queue)
- **Days 3-4**: Set up partitioning for all 34 chains
- **Days 5-7**: Implement and test core balance calculation functions

### Week 2: Queue Processing System
- **Days 1-3**: Implement queue management functions
- **Days 4-5**: Create and test triggers for all chain tables
- **Days 6-7**: Set up token metadata population

### Week 3: Background Processing & Monitoring
- **Days 1-3**: Implement queue worker system
- **Days 4-5**: Set up health monitoring and alerting
- **Days 6-7**: Performance testing and optimization

### Week 4: API Integration & Testing
- **Days 1-3**: Implement GraphQL resolvers
- **Days 4-5**: End-to-end testing across all chains
- **Days 6-7**: Documentation and deployment preparation

---

## Phase 7: Performance Benchmarks and Monitoring

### Expected Performance Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Queue Processing Rate | 1000+ updates/second | `process_balance_update_queue()` stats |
| Balance Query Response Time | <10ms | `get_current_balance()` execution time |
| Portfolio Query Response Time | <50ms | `get_address_portfolio()` execution time |
| Queue Lag (High Volume Chains) | <30 seconds | `oldest_pending_age_minutes` metric |
| Queue Lag (Low Volume Chains) | <5 seconds | `oldest_pending_age_minutes` metric |
| Database Storage Efficiency | <1TB for 1M addresses | Partition size monitoring |

### Monitoring Alerts

```sql
-- Critical alerts for queue health
SELECT
    chain_id,
    chain_name,
    'CRITICAL: High queue lag' as alert_type,
    FORMAT('Queue lag: %s minutes', oldest_pending_age_minutes) as message
FROM queue_health_summary
WHERE oldest_pending_age_minutes > 60;

SELECT
    chain_id,
    chain_name,
    'WARNING: High error rate' as alert_type,
    FORMAT('Error rate: %s/hour', error_count_last_hour) as message
FROM queue_health_summary
WHERE error_count_last_hour > 100;
```

---

## Phase 8: Maintenance and Optimization

### Automated Maintenance Tasks

1. **Daily**: Collect queue health metrics
2. **Weekly**: Clean old processed queue entries
3. **Monthly**: Create daily balance snapshots
4. **Quarterly**: Analyze and optimize partition performance

### Scaling Considerations

- **Horizontal Scaling**: Add more queue workers for high-volume chains
- **Vertical Scaling**: Increase batch sizes for efficient processing
- **Archive Strategy**: Move old queue entries to cold storage
- **Cache Layer**: Add Redis for frequently accessed balances

This comprehensive plan ensures consistent, scalable queue-based balance tracking across all 34 chains in the Eco Foundation ecosystem.