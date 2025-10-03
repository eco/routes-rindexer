-- ============================================================================
-- Grafana Dashboard Performance Indexes
-- Created: 2025-09-30
-- Purpose: Optimize queries for Grafana dashboards
-- ============================================================================

-- Portal Contract Indexes
-- ----------------------------------------------------------------------------

-- Intent Published - Primary queries
CREATE INDEX IF NOT EXISTS idx_intent_published_timestamp
    ON ecorindexer_portal.intent_published(block_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_intent_published_network
    ON ecorindexer_portal.intent_published(network);

CREATE INDEX IF NOT EXISTS idx_intent_published_network_timestamp
    ON ecorindexer_portal.intent_published(network, block_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_intent_published_creator
    ON ecorindexer_portal.intent_published(creator);

CREATE INDEX IF NOT EXISTS idx_intent_published_prover
    ON ecorindexer_portal.intent_published(prover);

CREATE INDEX IF NOT EXISTS idx_intent_published_hash
    ON ecorindexer_portal.intent_published(intent_hash);

-- Intent Fulfilled - Join optimization
CREATE INDEX IF NOT EXISTS idx_intent_fulfilled_hash
    ON ecorindexer_portal.intent_fulfilled(intent_hash);

CREATE INDEX IF NOT EXISTS idx_intent_fulfilled_timestamp
    ON ecorindexer_portal.intent_fulfilled(block_timestamp DESC);

-- Intent Funded
CREATE INDEX IF NOT EXISTS idx_intent_funded_hash
    ON ecorindexer_portal.intent_funded(intent_hash);

CREATE INDEX IF NOT EXISTS idx_intent_funded_funder
    ON ecorindexer_portal.intent_funded(funder);

-- Intent Withdrawn
CREATE INDEX IF NOT EXISTS idx_intent_withdrawn_hash
    ON ecorindexer_portal.intent_withdrawn(intent_hash);

CREATE INDEX IF NOT EXISTS idx_intent_withdrawn_claimant
    ON ecorindexer_portal.intent_withdrawn(claimant);

-- Order Filled
CREATE INDEX IF NOT EXISTS idx_order_filled_solver
    ON ecorindexer_portal.order_filled(solver);

CREATE INDEX IF NOT EXISTS idx_order_filled_timestamp
    ON ecorindexer_portal.order_filled(block_timestamp DESC);

-- Stablecoin Transfer Indexes
-- ----------------------------------------------------------------------------

-- USDT0 Transfers
CREATE INDEX IF NOT EXISTS idx_transfer_from
    ON ecorindexer_stable_usdt_0.transfer("from");

CREATE INDEX IF NOT EXISTS idx_transfer_to
    ON ecorindexer_stable_usdt_0.transfer("to");

CREATE INDEX IF NOT EXISTS idx_transfer_timestamp
    ON ecorindexer_stable_usdt_0.transfer(block_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_transfer_network_timestamp
    ON ecorindexer_stable_usdt_0.transfer(network, block_timestamp DESC);

-- Network Metadata View (for dashboard variables)
-- ----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_network_metadata;

CREATE MATERIALIZED VIEW mv_network_metadata AS
SELECT
    network,
    chain_id,
    MIN(block_timestamp) as first_seen,
    MAX(block_timestamp) as last_seen,
    COUNT(*) as event_count
FROM (
    SELECT network, chain_id, block_timestamp
    FROM ecorindexer_portal.intent_published
    UNION ALL
    SELECT network, chain_id, block_timestamp
    FROM ecorindexer_stable_usdt_0.transfer
) all_events
GROUP BY network, chain_id;

CREATE UNIQUE INDEX ON mv_network_metadata(network, chain_id);

-- Refresh function (call periodically)
-- Can be executed manually or via cron:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_network_metadata;

-- Daily Intent Statistics (for performance)
-- ----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_daily_intent_stats;

CREATE MATERIALIZED VIEW mv_daily_intent_stats AS
SELECT
    DATE(block_timestamp) as date,
    network,
    chain_id,
    COUNT(*) as total_intents,
    COUNT(DISTINCT creator) as unique_creators,
    SUM(reward_native_amount) as total_rewards,
    AVG(reward_native_amount) as avg_reward
FROM ecorindexer_portal.intent_published
GROUP BY DATE(block_timestamp), network, chain_id;

CREATE INDEX ON mv_daily_intent_stats(date DESC, network);

-- Grant permissions (using template variable for substitution)
-- Note: This will be replaced with actual user from environment variable
-- GRANT SELECT ON mv_network_metadata TO ${DATABASE_USER};
-- GRANT SELECT ON mv_daily_intent_stats TO ${DATABASE_USER};

-- Analysis queries to verify indexes
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname LIKE 'ecorindexer_%'
ORDER BY schemaname, tablename, indexname;
