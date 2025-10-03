-- ============================================================================
-- Stablecoin Metadata Table
-- Created: 2025-10-01
-- Purpose: Store token metadata for dynamic decimal handling in dashboards
-- ============================================================================

-- Create metadata table for stablecoin contract information
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.stablecoin_metadata (
    schema_name VARCHAR(100) PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    decimals INTEGER NOT NULL DEFAULT 6,
    description TEXT,
    contract_addresses JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.stablecoin_metadata IS 'Metadata for stablecoin tokens indexed by rindexer';
COMMENT ON COLUMN public.stablecoin_metadata.schema_name IS 'Schema name in format ecorindexer_stable_*';
COMMENT ON COLUMN public.stablecoin_metadata.symbol IS 'Token symbol (e.g., USDT0, USDC)';
COMMENT ON COLUMN public.stablecoin_metadata.decimals IS 'Number of decimals for the token (default: 6)';
COMMENT ON COLUMN public.stablecoin_metadata.contract_addresses IS 'JSON object mapping network to contract address';

-- Insert initial metadata for USDT0
-- ----------------------------------------------------------------------------

INSERT INTO public.stablecoin_metadata (schema_name, symbol, decimals, description, contract_addresses)
VALUES (
    'ecorindexer_stable_usdt_0',
    'USDT0',
    6,
    'Plasma Chain Stable Token',
    '{"plasma-mainnet": "0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb"}'::jsonb
)
ON CONFLICT (schema_name) DO UPDATE SET
    decimals = EXCLUDED.decimals,
    description = EXCLUDED.description,
    contract_addresses = EXCLUDED.contract_addresses,
    updated_at = NOW();

-- Future stablecoin metadata entries (uncomment when contracts are enabled)
-- ----------------------------------------------------------------------------

-- USDC - Most widely deployed stable
-- INSERT INTO public.stablecoin_metadata (schema_name, symbol, decimals, description, contract_addresses)
-- VALUES (
--     'ecorindexer_stable_usdc',
--     'USDC',
--     6,
--     'USD Coin - Circle stablecoin',
--     '{
--         "ethereum": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
--         "arbitrum-one": "0xaf88d065e77c8cc2239327c5edb3a432268e5831",
--         "base": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
--         "polygon": "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
--         "op-mainnet": "0x0b2c639c533813f4aa9d7837caf62653d097ff85"
--     }'::jsonb
-- )
-- ON CONFLICT (schema_name) DO NOTHING;

-- USDT - Tether stablecoin
-- INSERT INTO public.stablecoin_metadata (schema_name, symbol, decimals, description, contract_addresses)
-- VALUES (
--     'ecorindexer_stable_usdt',
--     'USDT',
--     6,
--     'Tether USD - Most widely used stablecoin',
--     '{
--         "ethereum": "0xdac17f958d2ee523a2206206994597c13d831ec7",
--         "polygon": "0xc2132d05d31c914a87c6611c10748aeb04b58e8f",
--         "op-mainnet": "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58"
--     }'::jsonb
-- )
-- ON CONFLICT (schema_name) DO NOTHING;

-- USDCe - Bridged USDC
-- INSERT INTO public.stablecoin_metadata (schema_name, symbol, decimals, description, contract_addresses)
-- VALUES (
--     'ecorindexer_stable_usdce',
--     'USDC.e',
--     6,
--     'Bridged USD Coin',
--     '{
--         "arbitrum-one": "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8",
--         "polygon": "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
--         "op-mainnet": "0x7F5c764cBc14f9669B88837ca1490cCa17c31607"
--     }'::jsonb
-- )
-- ON CONFLICT (schema_name) DO NOTHING;

-- Helper function to get decimals for a schema
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_stablecoin_decimals(schema_name_param TEXT)
RETURNS INTEGER AS $$
DECLARE
    decimals_val INTEGER;
BEGIN
    SELECT decimals INTO decimals_val
    FROM public.stablecoin_metadata
    WHERE schema_name = schema_name_param;

    -- Return 6 as default if not found
    RETURN COALESCE(decimals_val, 6);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION public.get_stablecoin_decimals IS 'Returns decimals for a given schema, defaults to 6';

-- Helper function to scale value based on decimals
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.scale_token_value(value_param TEXT, schema_name_param TEXT)
RETURNS NUMERIC AS $$
DECLARE
    decimals_val INTEGER;
    divisor NUMERIC;
BEGIN
    decimals_val := public.get_stablecoin_decimals(schema_name_param);
    divisor := POWER(10, decimals_val);

    RETURN (value_param::NUMERIC / divisor);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION public.scale_token_value IS 'Scales a token value string to human-readable decimal based on schema decimals';

-- Create view for all stablecoin transfers across all schemas
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_all_stablecoin_transfers AS
SELECT
    'ecorindexer_stable_usdt_0' as schema_name,
    m.symbol,
    m.decimals,
    t.block_timestamp,
    t."from",
    t."to",
    t.value::NUMERIC as value_raw,
    (t.value::NUMERIC / POWER(10, m.decimals)) as value_scaled,
    t.network,
    t.tx_hash,
    t.block_number,
    t.contract_address
FROM ecorindexer_stable_usdt_0.transfer t
LEFT JOIN public.stablecoin_metadata m ON m.schema_name = 'ecorindexer_stable_usdt_0';

-- Add more UNION ALL clauses when additional stablecoin schemas are added
-- UNION ALL
-- SELECT
--     'ecorindexer_stable_usdc' as schema_name,
--     m.symbol,
--     m.decimals,
--     ...
-- FROM ecorindexer_stable_usdc.transfer t
-- LEFT JOIN public.stablecoin_metadata m ON m.schema_name = 'ecorindexer_stable_usdc';

COMMENT ON VIEW public.v_all_stablecoin_transfers IS 'Unified view of all stablecoin transfers with automatic decimal scaling';

-- Grant permissions
-- ----------------------------------------------------------------------------

-- GRANT SELECT ON public.stablecoin_metadata TO ${DATABASE_USER};
-- GRANT EXECUTE ON FUNCTION public.get_stablecoin_decimals TO ${DATABASE_USER};
-- GRANT EXECUTE ON FUNCTION public.scale_token_value TO ${DATABASE_USER};
-- GRANT SELECT ON public.v_all_stablecoin_transfers TO ${DATABASE_USER};

-- Verification queries
-- ----------------------------------------------------------------------------

-- Test the helper functions
SELECT
    schema_name,
    symbol,
    decimals,
    public.get_stablecoin_decimals(schema_name) as retrieved_decimals,
    public.scale_token_value('5000000', schema_name) as scaled_example
FROM public.stablecoin_metadata;

-- Show sample transfers with scaling
SELECT
    symbol,
    value_raw,
    value_scaled,
    network,
    block_timestamp
FROM public.v_all_stablecoin_transfers
ORDER BY block_timestamp DESC
LIMIT 10;
