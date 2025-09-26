-- Useful data views for Eco Rindexer
-- These views provide convenient access to commonly queried data patterns

-- Intent lifecycle summary view
CREATE OR REPLACE VIEW intent_lifecycle_summary AS
WITH intent_events AS (
  SELECT
    intent_hash,
    event_name,
    block_number,
    block_timestamp,
    transaction_hash,
    chain_id,
    CASE event_name
      WHEN 'IntentPublished' THEN 1
      WHEN 'IntentFunded' THEN 2
      WHEN 'IntentProven' THEN 3
      WHEN 'IntentFulfilled' THEN 4
      WHEN 'IntentWithdrawn' THEN 5
      WHEN 'IntentRefunded' THEN 6
      ELSE 99
    END as event_order
  FROM intent_activities
)
SELECT
  intent_hash,
  chain_id,
  MIN(CASE WHEN event_name = 'IntentPublished' THEN block_timestamp END) as published_at,
  MIN(CASE WHEN event_name = 'IntentFunded' THEN block_timestamp END) as funded_at,
  MIN(CASE WHEN event_name = 'IntentProven' THEN block_timestamp END) as proven_at,
  MIN(CASE WHEN event_name = 'IntentFulfilled' THEN block_timestamp END) as fulfilled_at,
  MIN(CASE WHEN event_name = 'IntentWithdrawn' THEN block_timestamp END) as withdrawn_at,
  MIN(CASE WHEN event_name = 'IntentRefunded' THEN block_timestamp END) as refunded_at,
  CASE
    WHEN MAX(CASE WHEN event_name = 'IntentFulfilled' THEN 1 ELSE 0 END) = 1 THEN 'fulfilled'
    WHEN MAX(CASE WHEN event_name = 'IntentRefunded' THEN 1 ELSE 0 END) = 1 THEN 'refunded'
    WHEN MAX(CASE WHEN event_name = 'IntentWithdrawn' THEN 1 ELSE 0 END) = 1 THEN 'withdrawn'
    WHEN MAX(CASE WHEN event_name = 'IntentProven' THEN 1 ELSE 0 END) = 1 THEN 'proven'
    WHEN MAX(CASE WHEN event_name = 'IntentFunded' THEN 1 ELSE 0 END) = 1 THEN 'funded'
    WHEN MAX(CASE WHEN event_name = 'IntentPublished' THEN 1 ELSE 0 END) = 1 THEN 'published'
    ELSE 'unknown'
  END as current_status,
  COUNT(*) as total_events,
  MAX(block_timestamp) as last_updated
FROM intent_events
GROUP BY intent_hash, chain_id;

-- Cross-chain activity summary
CREATE OR REPLACE VIEW cross_chain_activity_summary AS
SELECT
  chain_id,
  COUNT(DISTINCT intent_hash) as unique_intents,
  COUNT(*) as total_events,
  COUNT(CASE WHEN event_name = 'IntentPublished' THEN 1 END) as intents_published,
  COUNT(CASE WHEN event_name = 'IntentFulfilled' THEN 1 END) as intents_fulfilled,
  COUNT(CASE WHEN event_name = 'IntentRefunded' THEN 1 END) as intents_refunded,
  MIN(block_timestamp) as first_activity,
  MAX(block_timestamp) as last_activity,
  COUNT(DISTINCT DATE(block_timestamp)) as active_days
FROM intent_activities
GROUP BY chain_id;

-- Current stable token balances view (materialized for performance)
CREATE MATERIALIZED VIEW IF NOT EXISTS current_stable_balances AS
WITH holder_balances AS (
  SELECT
    contract_address,
    COALESCE(credits.holder, debits.holder) as holder_address,
    COALESCE(credits.total_received, 0) - COALESCE(debits.total_sent, 0) as current_balance,
    GREATEST(
      COALESCE(credits.last_received_block, 0),
      COALESCE(debits.last_sent_block, 0)
    ) as last_updated_block,
    GREATEST(
      COALESCE(credits.last_received_time, '1970-01-01'::timestamp),
      COALESCE(debits.last_sent_time, '1970-01-01'::timestamp)
    ) as last_updated_time
  FROM (
    -- Aggregate all incoming transfers (credits)
    SELECT
      contract_address,
      to_address as holder,
      SUM(value) as total_received,
      MAX(block_number) as last_received_block,
      MAX(block_timestamp) as last_received_time
    FROM stable_transfers
    WHERE to_address != '0x0000000000000000000000000000000000000000'
    GROUP BY contract_address, to_address
  ) credits
  FULL OUTER JOIN (
    -- Aggregate all outgoing transfers (debits)
    SELECT
      contract_address,
      from_address as holder,
      SUM(value) as total_sent,
      MAX(block_number) as last_sent_block,
      MAX(block_timestamp) as last_sent_time
    FROM stable_transfers
    WHERE from_address != '0x0000000000000000000000000000000000000000'
    GROUP BY contract_address, from_address
  ) debits ON credits.contract_address = debits.contract_address
              AND credits.holder = debits.holder
)
SELECT
  contract_address,
  holder_address,
  current_balance,
  last_updated_block,
  last_updated_time,
  -- Add token metadata for easier querying
  CASE contract_address
    WHEN '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48' THEN 'USDC'
    WHEN '0xdac17f958d2ee523a2206206994597c13d831ec7' THEN 'USDT'
    WHEN '0x6b175474e89094c44da98b954eedeac495271d0f' THEN 'DAI'
    ELSE 'UNKNOWN'
  END as token_symbol
FROM holder_balances
WHERE current_balance > 0;

-- Create indexes on the materialized view for fast lookups
CREATE INDEX IF NOT EXISTS idx_current_balances_holder ON current_stable_balances (holder_address);
CREATE INDEX IF NOT EXISTS idx_current_balances_token ON current_stable_balances (contract_address);
CREATE INDEX IF NOT EXISTS idx_current_balances_balance ON current_stable_balances (current_balance DESC);
CREATE INDEX IF NOT EXISTS idx_current_balances_composite ON current_stable_balances (holder_address, contract_address);

-- Network health monitoring view
CREATE OR REPLACE VIEW network_health_status AS
SELECT
  chain_id,
  status,
  last_indexed_block,
  blocks_behind,
  last_success_time,
  error_count,
  avg_response_time_ms,
  rpc_endpoint,
  CASE
    WHEN status = 'healthy' AND blocks_behind < 10 THEN 'excellent'
    WHEN status = 'healthy' AND blocks_behind < 50 THEN 'good'
    WHEN status = 'degraded' OR blocks_behind < 100 THEN 'warning'
    ELSE 'critical'
  END as health_grade,
  NOW() - last_success_time as time_since_success
FROM network_health;

-- Daily activity statistics
CREATE OR REPLACE VIEW daily_activity_stats AS
SELECT
  DATE(block_timestamp) as activity_date,
  chain_id,
  COUNT(*) as total_events,
  COUNT(DISTINCT intent_hash) as unique_intents,
  COUNT(DISTINCT creator_address) as unique_creators,
  AVG(EXTRACT(EPOCH FROM (block_timestamp - LAG(block_timestamp) OVER (PARTITION BY chain_id ORDER BY block_timestamp)))) as avg_time_between_events
FROM intent_activities
GROUP BY DATE(block_timestamp), chain_id
ORDER BY activity_date DESC, chain_id;

-- Top token holders per token (materialized for performance)
CREATE MATERIALIZED VIEW IF NOT EXISTS top_token_holders AS
SELECT
  contract_address,
  token_symbol,
  holder_address,
  current_balance,
  ROW_NUMBER() OVER (PARTITION BY contract_address ORDER BY current_balance DESC) as holder_rank,
  last_updated_block,
  last_updated_time
FROM current_stable_balances
WHERE current_balance > 0
ORDER BY contract_address, current_balance DESC;

CREATE INDEX IF NOT EXISTS idx_top_holders_token_rank ON top_token_holders (contract_address, holder_rank);

-- Function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_balance_views()
RETURNS void AS $$
BEGIN
  -- Refresh materialized views concurrently to avoid blocking reads
  REFRESH MATERIALIZED VIEW CONCURRENTLY current_stable_balances;
  REFRESH MATERIALIZED VIEW CONCURRENTLY top_token_holders;

  -- Log the refresh operation
  INSERT INTO view_refresh_log (view_name, refreshed_at, refresh_duration)
  VALUES ('current_stable_balances', NOW(),
          EXTRACT(EPOCH FROM (NOW() - (SELECT last_refresh FROM view_refresh_log WHERE view_name = 'current_stable_balances' ORDER BY refreshed_at DESC LIMIT 1))));
END;
$$ LANGUAGE plpgsql;

-- Create log table for view refresh tracking
CREATE TABLE IF NOT EXISTS view_refresh_log (
  id SERIAL PRIMARY KEY,
  view_name VARCHAR(100) NOT NULL,
  refreshed_at TIMESTAMP DEFAULT NOW(),
  refresh_duration INTERVAL,
  last_refresh TIMESTAMP GENERATED ALWAYS AS (refreshed_at) STORED
);