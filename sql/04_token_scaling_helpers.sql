-- ============================================================================
-- Token Scaling Helper Functions
-- Created: 2025-10-01
-- Purpose: Dynamic token amount scaling for both native and ERC20 tokens
-- ============================================================================

-- Function to get decimals for a token by contract address
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_token_decimals_by_address(
    contract_addr TEXT,
    network_name TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    decimals_val INTEGER;
    metadata_record RECORD;
BEGIN
    -- Special case: NULL or zero address = native token (18 decimals)
    IF contract_addr IS NULL
       OR contract_addr = '0x0000000000000000000000000000000000000000'
       OR contract_addr = '' THEN
        RETURN 18;
    END IF;

    -- Normalize address to lowercase for comparison
    contract_addr := LOWER(contract_addr);

    -- Search through stablecoin metadata
    FOR metadata_record IN
        SELECT decimals, contract_addresses
        FROM public.stablecoin_metadata
    LOOP
        -- Check if this contract address exists in the JSONB addresses
        IF network_name IS NOT NULL THEN
            -- If network specified, check specific network
            IF metadata_record.contract_addresses ? network_name AND
               LOWER(metadata_record.contract_addresses->>network_name) = contract_addr THEN
                RETURN metadata_record.decimals;
            END IF;
        ELSE
            -- If no network specified, search all networks in JSONB
            IF EXISTS (
                SELECT 1 FROM jsonb_each_text(metadata_record.contract_addresses)
                WHERE LOWER(value) = contract_addr
            ) THEN
                RETURN metadata_record.decimals;
            END IF;
        END IF;
    END LOOP;

    -- Default: assume stablecoin with 6 decimals if not found
    RETURN 6;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.get_token_decimals_by_address IS 'Returns decimals for a token by contract address. Returns 18 for native (NULL/zero address), 6 default for unknown tokens.';

-- Function to scale any token value based on contract address
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.scale_token_by_address(
    amount_str TEXT,
    contract_addr TEXT,
    network_name TEXT DEFAULT NULL
)
RETURNS NUMERIC AS $$
DECLARE
    decimals_val INTEGER;
    divisor NUMERIC;
BEGIN
    -- Handle NULL amounts
    IF amount_str IS NULL OR amount_str = '' THEN
        RETURN 0;
    END IF;

    -- Get decimals for this token
    decimals_val := public.get_token_decimals_by_address(contract_addr, network_name);
    divisor := POWER(10, decimals_val);

    RETURN (amount_str::NUMERIC / divisor);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.scale_token_by_address IS 'Scales a token amount string to human-readable decimal based on contract address and network.';

-- Function to scale native token amounts (always 18 decimals)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.scale_native_token(amount_str TEXT)
RETURNS NUMERIC AS $$
BEGIN
    IF amount_str IS NULL OR amount_str = '' THEN
        RETURN 0;
    END IF;

    RETURN (amount_str::NUMERIC / 1e18);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION public.scale_native_token IS 'Scales native token amounts (ETH, MATIC, etc.) with 18 decimals.';

-- Function to calculate total reward combining native and token rewards
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.total_reward_value(
    native_amount TEXT,
    token_amount TEXT,
    token_address TEXT,
    network_name TEXT,
    token_price_in_native NUMERIC DEFAULT 1.0
)
RETURNS NUMERIC AS $$
DECLARE
    native_scaled NUMERIC;
    token_scaled NUMERIC;
BEGIN
    -- Scale native amount (18 decimals)
    native_scaled := COALESCE(public.scale_native_token(native_amount), 0);

    -- Scale token amount (variable decimals based on token)
    token_scaled := COALESCE(
        public.scale_token_by_address(token_amount, token_address, network_name),
        0
    );

    -- Convert token to native equivalent and sum
    -- Default to 1:1 ratio if price not provided
    RETURN native_scaled + (token_scaled * token_price_in_native);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION public.total_reward_value IS 'Calculates total reward value in native token terms, combining native and ERC20 token rewards.';

-- View for all portal rewards with proper scaling
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_portal_rewards_scaled AS
SELECT
    rindexer_id,
    intent_hash,
    creator,
    prover,
    destination,
    network,
    block_timestamp,

    -- Native rewards (18 decimals)
    reward_native_amount as reward_native_raw,
    public.scale_native_token(reward_native_amount) as reward_native_scaled,

    -- Token rewards (variable decimals)
    reward_tokens_token,
    reward_tokens_amount as reward_token_raw,
    public.scale_token_by_address(
        reward_tokens_amount,
        reward_tokens_token,
        network
    ) as reward_token_scaled,

    -- Token decimals for reference
    public.get_token_decimals_by_address(
        reward_tokens_token,
        network
    ) as reward_token_decimals,

    -- Total reward in native terms (assuming 1:1 price)
    public.total_reward_value(
        reward_native_amount,
        reward_tokens_amount,
        reward_tokens_token,
        network,
        1.0
    ) as total_reward_native_equivalent,

    -- Original fields
    tx_hash,
    block_number,
    block_hash
FROM ecorindexer_portal.intent_published;

COMMENT ON VIEW public.v_portal_rewards_scaled IS 'Portal intent rewards with automatic decimal scaling for both native and ERC20 tokens.';

-- Grant permissions
-- ----------------------------------------------------------------------------

-- GRANT EXECUTE ON FUNCTION public.get_token_decimals_by_address TO ${DATABASE_USER};
-- GRANT EXECUTE ON FUNCTION public.scale_token_by_address TO ${DATABASE_USER};
-- GRANT EXECUTE ON FUNCTION public.scale_native_token TO ${DATABASE_USER};
-- GRANT EXECUTE ON FUNCTION public.total_reward_value TO ${DATABASE_USER};
-- GRANT SELECT ON public.v_portal_rewards_scaled TO ${DATABASE_USER};

-- Verification queries
-- ----------------------------------------------------------------------------

-- Test native token scaling
SELECT
    public.scale_native_token('1000000000000000000') as one_eth,
    public.scale_native_token('500000000000000000') as half_eth;

-- Test token address lookup (when metadata exists)
SELECT
    public.get_token_decimals_by_address(
        '0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb',
        'plasma-mainnet'
    ) as usdt0_decimals,
    public.get_token_decimals_by_address(
        '0x0000000000000000000000000000000000000000',
        'plasma-mainnet'
    ) as native_decimals;

-- Test token scaling
SELECT
    public.scale_token_by_address(
        '5000000',
        '0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb',
        'plasma-mainnet'
    ) as usdt0_scaled;

-- Show sample scaled rewards (when data exists)
SELECT
    creator,
    reward_native_scaled,
    reward_token_scaled,
    reward_token_decimals,
    total_reward_native_equivalent,
    block_timestamp
FROM public.v_portal_rewards_scaled
WHERE reward_native_scaled > 0 OR reward_token_scaled > 0
ORDER BY block_timestamp DESC
LIMIT 10;
