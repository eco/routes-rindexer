# Database Schema Strategy for Eco Rindexer

This document outlines the database schema design for indexing the Eco Foundation ecosystem across 34 EVM chains, focusing on Portal contracts and stable token tracking.

## Core Tables

### 1. chain_events
**Purpose**: All indexed events with common fields
```sql
CREATE TABLE chain_events (
    id BIGSERIAL PRIMARY KEY,
    chain_id BIGINT NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    transaction_index INTEGER NOT NULL,
    log_index INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 2. intent_activities
**Purpose**: Portal-specific intent lifecycle tracking
```sql
CREATE TABLE intent_activities (
    id BIGSERIAL PRIMARY KEY,
    intent_hash BYTEA NOT NULL,
    chain_id BIGINT NOT NULL,
    event_name VARCHAR(50) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,

    -- IntentPublished specific fields
    creator_address VARCHAR(42),
    prover_address VARCHAR(42),
    destination_chain_id BIGINT,
    reward_deadline BIGINT,
    reward_native_amount NUMERIC(78, 0),
    reward_tokens JSONB,
    route_data BYTEA,

    -- IntentFulfilled/Proven/Withdrawn specific fields
    claimant_address VARCHAR(42),
    claimant_bytes32 BYTEA,

    -- IntentFunded specific fields
    funder_address VARCHAR(42),
    funding_complete BOOLEAN,

    -- IntentRefunded/TokenRecovered specific fields
    refundee_address VARCHAR(42),
    recovered_token_address VARCHAR(42),

    -- Order specific fields
    order_id BYTEA,
    solver_address VARCHAR(42),
    resolved_order JSONB,

    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3. stable_transfers
**Purpose**: ERC20 stable token movements
```sql
CREATE TABLE stable_transfers (
    id BIGSERIAL PRIMARY KEY,
    chain_id BIGINT NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42) NOT NULL,
    value NUMERIC(78, 0) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    token_symbol VARCHAR(20),
    decimals INTEGER DEFAULT 18,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 4. native_transfers
**Purpose**: Native token (ETH/MATIC/BNB etc.) transfer tracking
```sql
CREATE TABLE native_transfers (
    id BIGSERIAL PRIMARY KEY,
    chain_id BIGINT NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42) NOT NULL,
    value NUMERIC(78, 0) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    gas_used BIGINT,
    gas_price NUMERIC(78, 0),
    native_symbol VARCHAR(10),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 5. native_balances
**Purpose**: Address balance snapshots across all chains
```sql
CREATE TABLE native_balances (
    id BIGSERIAL PRIMARY KEY,
    address VARCHAR(42) NOT NULL,
    chain_id BIGINT NOT NULL,
    balance NUMERIC(78, 0) NOT NULL,
    block_number BIGINT NOT NULL,
    block_timestamp TIMESTAMP NOT NULL,
    native_symbol VARCHAR(10),
    updated_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(address, chain_id, block_number)
);
```

### 6. network_health
**Purpose**: RPC and indexing health metrics
```sql
CREATE TABLE network_health (
    id BIGSERIAL PRIMARY KEY,
    chain_id BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL, -- 'healthy', 'degraded', 'down'
    last_indexed_block BIGINT,
    current_chain_block BIGINT,
    blocks_behind BIGINT GENERATED ALWAYS AS (current_chain_block - last_indexed_block) STORED,
    last_success_time TIMESTAMP,
    last_error_time TIMESTAMP,
    error_count INTEGER DEFAULT 0,
    error_message TEXT,
    avg_response_time_ms INTEGER,
    rpc_endpoint VARCHAR(500),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

## Performance Optimizations

### Partitioning Strategy
```sql
-- Partition chain_events by chain_id for better performance
CREATE TABLE chain_events_ethereum PARTITION OF chain_events FOR VALUES (1);
CREATE TABLE chain_events_arbitrum PARTITION OF chain_events FOR VALUES (42161);
CREATE TABLE chain_events_base PARTITION OF chain_events FOR VALUES (8453);
CREATE TABLE chain_events_polygon PARTITION OF chain_events FOR VALUES (137);
CREATE TABLE chain_events_optimism PARTITION OF chain_events FOR VALUES (10);

-- Partition stable_transfers by chain_id
CREATE TABLE stable_transfers_ethereum PARTITION OF stable_transfers FOR VALUES (1);
CREATE TABLE stable_transfers_arbitrum PARTITION OF stable_transfers FOR VALUES (42161);
-- ... continue for all chains

-- Partition native_transfers for high-volume networks
CREATE TABLE native_transfers_ethereum PARTITION OF native_transfers FOR VALUES (1);
CREATE TABLE native_transfers_polygon PARTITION OF native_transfers FOR VALUES (137);
```

### Strategic Indexes
```sql
-- Essential indexes for query performance (see sql/indexes.sql)
CREATE INDEX CONCURRENTLY idx_chain_events_chain_block ON chain_events (chain_id, block_number DESC);
CREATE INDEX CONCURRENTLY idx_chain_events_address_event ON chain_events (contract_address, event_name);
CREATE INDEX CONCURRENTLY idx_chain_events_timestamp ON chain_events (block_timestamp DESC);

-- Intent-specific indexes
CREATE INDEX CONCURRENTLY idx_intent_activities_hash ON intent_activities (intent_hash);
CREATE INDEX CONCURRENTLY idx_intent_activities_creator ON intent_activities (creator_address);
CREATE INDEX CONCURRENTLY idx_intent_activities_status ON intent_activities (event_name, block_timestamp DESC);

-- Balance calculation indexes
CREATE INDEX CONCURRENTLY idx_stable_transfers_from_address ON stable_transfers (from_address, contract_address, block_number DESC);
CREATE INDEX CONCURRENTLY idx_stable_transfers_to_address ON stable_transfers (to_address, contract_address, block_number DESC);
```

### Materialized Views
```sql
-- Pre-computed balance views for performance (see sql/views.sql)
CREATE MATERIALIZED VIEW current_stable_balances AS
-- Complex balance calculation query
-- Refreshed periodically for fast balance lookups

CREATE MATERIALIZED VIEW intent_lifecycle_summary AS
-- Intent status aggregation for quick lifecycle queries

CREATE MATERIALIZED VIEW top_token_holders AS
-- Top holders per token for analytics
```

## Data Lifecycle Management

### Hot/Warm/Cold Strategy

#### Hot Data (0-30 days)
- All current intent activities
- Recent stable token transfers
- Current native balances
- Active network health data

#### Warm Data (30-365 days)
- Historical intent data for analytics
- Aggregated transfer statistics
- Historical balance snapshots

#### Cold Data (365+ days)
- Archived event data
- Long-term analytics data
- Backup and compliance data

### Archive Strategy
```sql
-- Archive old data to separate tables
CREATE TABLE chain_events_archive (
    LIKE chain_events INCLUDING ALL
);

-- Move data older than 1 year to archive
INSERT INTO chain_events_archive
SELECT * FROM chain_events
WHERE block_timestamp < NOW() - INTERVAL '1 year';

DELETE FROM chain_events
WHERE block_timestamp < NOW() - INTERVAL '1 year';
```

## Data Quality and Constraints

### Unique Constraints
```sql
-- Prevent duplicate events
ALTER TABLE chain_events
ADD CONSTRAINT uk_chain_events_unique
UNIQUE (chain_id, transaction_hash, log_index);

-- Prevent duplicate transfers
ALTER TABLE stable_transfers
ADD CONSTRAINT uk_stable_transfers_unique
UNIQUE (chain_id, transaction_hash, log_index);

-- Prevent duplicate native transfers
ALTER TABLE native_transfers
ADD CONSTRAINT uk_native_transfers_unique
UNIQUE (chain_id, transaction_hash);
```

### Data Validation
```sql
-- Check constraints for data integrity
ALTER TABLE chain_events
ADD CONSTRAINT chk_chain_events_chain_id
CHECK (chain_id > 0);

ALTER TABLE stable_transfers
ADD CONSTRAINT chk_stable_transfers_value
CHECK (value >= 0);

ALTER TABLE native_balances
ADD CONSTRAINT chk_native_balances_balance
CHECK (balance >= 0);
```

## Backup and Recovery

### Backup Strategy
```bash
# Daily full backup
pg_dump eco_rindexer > backup_$(date +%Y%m%d).sql

# Hourly incremental backup using WAL-E or similar
# Continuous replication to standby server
```

### Point-in-Time Recovery
```bash
# Restore to specific timestamp
pg_restore --create --dbname=eco_rindexer_restored backup_20231201.sql
```

## Monitoring and Maintenance

### Health Checks
```sql
-- Check for indexing lag
SELECT
    chain_id,
    blocks_behind,
    last_success_time
FROM network_health
WHERE blocks_behind > 100;

-- Check for duplicate events
SELECT
    chain_id,
    transaction_hash,
    log_index,
    COUNT(*)
FROM chain_events
GROUP BY chain_id, transaction_hash, log_index
HAVING COUNT(*) > 1;
```

### Performance Monitoring
```sql
-- Slow query identification
SELECT
    query,
    mean_time,
    calls,
    total_time
FROM pg_stat_statements
WHERE mean_time > 1000
ORDER BY mean_time DESC;
```

### Maintenance Tasks
```sql
-- Weekly maintenance
VACUUM ANALYZE chain_events;
VACUUM ANALYZE stable_transfers;
VACUUM ANALYZE intent_activities;

-- Monthly maintenance
REINDEX INDEX CONCURRENTLY idx_chain_events_chain_block;
REFRESH MATERIALIZED VIEW CONCURRENTLY current_stable_balances;
```

## Scaling Considerations

### Horizontal Scaling
- **Read Replicas**: Multiple read-only replicas for query distribution
- **Sharding**: Partition data by chain_id across multiple databases
- **Microservices**: Separate indexing services per chain or contract type

### Vertical Scaling
- **Memory**: Increased RAM for larger buffer pools and caching
- **Storage**: NVMe SSDs for faster I/O operations
- **CPU**: More cores for parallel query processing

### Database-Specific Optimizations

#### PostgreSQL Settings
```sql
-- Optimized for high-throughput indexing
shared_buffers = 8GB
effective_cache_size = 24GB
work_mem = 256MB
maintenance_work_mem = 2GB
max_connections = 200
checkpoint_completion_target = 0.9
wal_buffers = 64MB
```

This schema is designed to handle the scale and complexity of indexing 34 EVM chains with hundreds of Portal deployments and thousands of stable token contracts, while maintaining query performance and data integrity.