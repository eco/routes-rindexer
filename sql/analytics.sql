-- Analytics queries for Eco Rindexer
-- These queries provide insights into Portal usage, token flows, and network activity

-- Intent success rate analysis by chain
SELECT
  chain_id,
  COUNT(*) as total_published,
  COUNT(CASE WHEN current_status = 'fulfilled' THEN 1 END) as fulfilled,
  COUNT(CASE WHEN current_status = 'refunded' THEN 1 END) as refunded,
  COUNT(CASE WHEN current_status IN ('published', 'funded', 'proven') THEN 1 END) as pending,
  ROUND(
    COUNT(CASE WHEN current_status = 'fulfilled' THEN 1 END)::decimal /
    NULLIF(COUNT(*), 0) * 100, 2
  ) as success_rate_pct
FROM intent_lifecycle_summary
GROUP BY chain_id
ORDER BY total_published DESC;

-- Intent processing time analysis
WITH processing_times AS (
  SELECT
    intent_hash,
    chain_id,
    published_at,
    fulfilled_at,
    refunded_at,
    CASE
      WHEN fulfilled_at IS NOT NULL THEN EXTRACT(EPOCH FROM (fulfilled_at - published_at))/3600
      WHEN refunded_at IS NOT NULL THEN EXTRACT(EPOCH FROM (refunded_at - published_at))/3600
      ELSE NULL
    END as processing_time_hours
  FROM intent_lifecycle_summary
  WHERE published_at IS NOT NULL
)
SELECT
  chain_id,
  COUNT(*) as processed_intents,
  ROUND(AVG(processing_time_hours), 2) as avg_processing_hours,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY processing_time_hours), 2) as median_processing_hours,
  ROUND(MIN(processing_time_hours), 2) as min_processing_hours,
  ROUND(MAX(processing_time_hours), 2) as max_processing_hours
FROM processing_times
WHERE processing_time_hours IS NOT NULL
GROUP BY chain_id
ORDER BY avg_processing_hours;

-- Daily volume trends for stable tokens
SELECT
  DATE(block_timestamp) as transfer_date,
  contract_address,
  token_symbol,
  COUNT(*) as transfer_count,
  COUNT(DISTINCT from_address) as unique_senders,
  COUNT(DISTINCT to_address) as unique_receivers,
  SUM(value) as total_volume,
  AVG(value) as avg_transfer_size
FROM stable_transfers st
JOIN (
  SELECT DISTINCT contract_address,
    CASE contract_address
      WHEN '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48' THEN 'USDC'
      WHEN '0xdac17f958d2ee523a2206206994597c13d831ec7' THEN 'USDT'
      ELSE 'OTHER'
    END as token_symbol
  FROM stable_transfers
) tokens ON st.contract_address = tokens.contract_address
WHERE block_timestamp >= NOW() - INTERVAL '30 days'
GROUP BY DATE(block_timestamp), st.contract_address, token_symbol
ORDER BY transfer_date DESC, total_volume DESC;

-- Cross-chain intent flow analysis
SELECT
  source_chain.chain_id as source_chain,
  dest_chain.chain_id as destination_chain,
  COUNT(*) as intent_count,
  COUNT(CASE WHEN ils.current_status = 'fulfilled' THEN 1 END) as successful_intents,
  ROUND(AVG(EXTRACT(EPOCH FROM (ils.fulfilled_at - ils.published_at))/3600), 2) as avg_fulfillment_time_hours
FROM intent_activities ia
JOIN intent_lifecycle_summary ils ON ia.intent_hash = ils.intent_hash
CROSS JOIN LATERAL (VALUES (ia.chain_id)) AS source_chain(chain_id)
CROSS JOIN LATERAL (VALUES (ia.destination_chain_id)) AS dest_chain(chain_id)
WHERE ia.event_name = 'IntentPublished'
  AND ia.destination_chain_id IS NOT NULL
GROUP BY source_chain.chain_id, dest_chain.chain_id
HAVING COUNT(*) > 5
ORDER BY intent_count DESC;

-- Top creators by intent volume and success rate
SELECT
  creator_address,
  COUNT(*) as total_intents,
  COUNT(CASE WHEN ils.current_status = 'fulfilled' THEN 1 END) as fulfilled_intents,
  COUNT(CASE WHEN ils.current_status = 'refunded' THEN 1 END) as refunded_intents,
  ROUND(
    COUNT(CASE WHEN ils.current_status = 'fulfilled' THEN 1 END)::decimal /
    NULLIF(COUNT(*), 0) * 100, 2
  ) as success_rate_pct,
  COUNT(DISTINCT ia.chain_id) as chains_used,
  MIN(ia.block_timestamp) as first_intent,
  MAX(ia.block_timestamp) as last_intent
FROM intent_activities ia
JOIN intent_lifecycle_summary ils ON ia.intent_hash = ils.intent_hash
WHERE ia.event_name = 'IntentPublished'
  AND ia.creator_address IS NOT NULL
GROUP BY creator_address
HAVING COUNT(*) >= 10
ORDER BY total_intents DESC, success_rate_pct DESC
LIMIT 20;

-- Token holder concentration analysis
WITH holder_stats AS (
  SELECT
    contract_address,
    token_symbol,
    COUNT(*) as total_holders,
    SUM(current_balance) as total_supply_tracked,
    AVG(current_balance) as avg_balance,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY current_balance) as median_balance,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY current_balance) as p90_balance,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY current_balance) as p99_balance
  FROM current_stable_balances
  GROUP BY contract_address, token_symbol
)
SELECT
  token_symbol,
  total_holders,
  ROUND(total_supply_tracked::decimal / 1e6, 2) as total_supply_millions,
  ROUND(avg_balance::decimal / 1e6, 2) as avg_balance_tokens,
  ROUND(median_balance::decimal / 1e6, 2) as median_balance_tokens,
  ROUND(p90_balance::decimal / 1e6, 2) as p90_balance_tokens,
  ROUND(p99_balance::decimal / 1e6, 2) as p99_balance_tokens,
  -- Calculate concentration: top 1% holders' share
  (SELECT ROUND(SUM(current_balance)::decimal / hs.total_supply_tracked * 100, 2)
   FROM current_stable_balances csb
   WHERE csb.contract_address = hs.contract_address
     AND csb.current_balance >= hs.p99_balance) as top_1pct_share
FROM holder_stats hs
ORDER BY total_supply_tracked DESC;

-- Network performance and reliability metrics
SELECT
  nhs.chain_id,
  nhs.health_grade,
  nhs.blocks_behind,
  nhs.avg_response_time_ms,
  nhs.error_count,
  -- Activity metrics from last 24h
  COALESCE(recent.recent_events, 0) as events_last_24h,
  COALESCE(recent.recent_intents, 0) as intents_last_24h,
  -- Overall activity
  COALESCE(total.total_events, 0) as total_events,
  COALESCE(total.total_intents, 0) as total_intents
FROM network_health_status nhs
LEFT JOIN (
  SELECT
    chain_id,
    COUNT(*) as recent_events,
    COUNT(DISTINCT intent_hash) as recent_intents
  FROM intent_activities
  WHERE block_timestamp >= NOW() - INTERVAL '24 hours'
  GROUP BY chain_id
) recent ON nhs.chain_id = recent.chain_id
LEFT JOIN (
  SELECT
    chain_id,
    COUNT(*) as total_events,
    COUNT(DISTINCT intent_hash) as total_intents
  FROM intent_activities
  GROUP BY chain_id
) total ON nhs.chain_id = total.chain_id
ORDER BY nhs.chain_id;

-- Intent reward analysis
SELECT
  chain_id,
  COUNT(*) as intents_with_rewards,
  COUNT(CASE WHEN reward_native_amount > 0 THEN 1 END) as native_reward_count,
  AVG(reward_native_amount) as avg_native_reward,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY reward_native_amount) as median_native_reward,
  MAX(reward_native_amount) as max_native_reward,
  -- Reward effectiveness (fulfilled vs total)
  COUNT(CASE WHEN ils.current_status = 'fulfilled' THEN 1 END) as fulfilled_with_rewards,
  ROUND(
    COUNT(CASE WHEN ils.current_status = 'fulfilled' THEN 1 END)::decimal /
    NULLIF(COUNT(*), 0) * 100, 2
  ) as reward_success_rate_pct
FROM intent_activities ia
JOIN intent_lifecycle_summary ils ON ia.intent_hash = ils.intent_hash
WHERE ia.event_name = 'IntentPublished'
  AND ia.reward_native_amount IS NOT NULL
GROUP BY chain_id
ORDER BY avg_native_reward DESC;

-- Time-based usage patterns
SELECT
  EXTRACT(HOUR FROM block_timestamp) as hour_of_day,
  EXTRACT(DOW FROM block_timestamp) as day_of_week, -- 0=Sunday, 6=Saturday
  COUNT(*) as event_count,
  COUNT(DISTINCT intent_hash) as unique_intents,
  AVG(EXTRACT(EPOCH FROM (
    block_timestamp - LAG(block_timestamp) OVER (ORDER BY block_timestamp)
  ))) as avg_seconds_between_events
FROM intent_activities
WHERE block_timestamp >= NOW() - INTERVAL '7 days'
  AND event_name = 'IntentPublished'
GROUP BY EXTRACT(HOUR FROM block_timestamp), EXTRACT(DOW FROM block_timestamp)
ORDER BY day_of_week, hour_of_day;