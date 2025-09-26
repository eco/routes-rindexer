-- Performance indexes for Eco Rindexer database
-- These indexes optimize common query patterns for Portal events and stable token transfers

-- Essential indexes for event lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_chain_block
  ON chain_events (chain_id, block_number DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_address_event
  ON chain_events (contract_address, event_name);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_timestamp
  ON chain_events (block_timestamp DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_tx_hash
  ON chain_events (transaction_hash);

-- Portal-specific indexes for intent lifecycle tracking
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_intent_activities_hash
  ON intent_activities (intent_hash);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_intent_activities_creator
  ON intent_activities (creator_address);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_intent_activities_status
  ON intent_activities (status, block_timestamp DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_intent_activities_destination
  ON intent_activities (destination_chain_id);

-- Stable token transfer indexes for balance calculations
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stable_transfers_from_address
  ON stable_transfers (from_address, contract_address, block_number DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stable_transfers_to_address
  ON stable_transfers (to_address, contract_address, block_number DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stable_transfers_composite
  ON stable_transfers (from_address, to_address, contract_address, block_number);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stable_transfers_token_time
  ON stable_transfers (contract_address, block_timestamp DESC);

-- Native transfer indexes (for native token balance tracking)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_native_transfers_from_address
  ON native_transfers (from_address, chain_id, block_timestamp DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_native_transfers_to_address
  ON native_transfers (to_address, chain_id, block_timestamp DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_native_balances_address_chain
  ON native_balances (address, chain_id, block_number DESC);

-- Composite indexes for complex queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_chain_contract_event
  ON chain_events (chain_id, contract_address, event_name, block_number DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stable_transfers_address_token_time
  ON stable_transfers (from_address, contract_address, block_timestamp DESC);

-- Partitioning support indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_ethereum
  ON chain_events (block_number DESC, event_name)
  WHERE chain_id = 1;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_arbitrum
  ON chain_events (block_number DESC, event_name)
  WHERE chain_id = 42161;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_base
  ON chain_events (block_number DESC, event_name)
  WHERE chain_id = 8453;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_polygon
  ON chain_events (block_number DESC, event_name)
  WHERE chain_id = 137;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chain_events_optimism
  ON chain_events (block_number DESC, event_name)
  WHERE chain_id = 10;

-- Index for monitoring and health checks
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_network_health_status
  ON network_health (chain_id, last_indexed_block DESC, status);

-- Vacuum and analyze recommendations
-- Run these periodically to maintain index performance:
-- VACUUM ANALYZE chain_events;
-- VACUUM ANALYZE stable_transfers;
-- VACUUM ANALYZE intent_activities;
-- VACUUM ANALYZE native_transfers;