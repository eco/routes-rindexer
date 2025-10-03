# Adding New Stablecoins to Rindexer

This guide explains how to add new stablecoin tracking to the eco-rindexer system. The system automatically handles decimal scaling for display purposes in both transfer events and portal rewards.

## Overview

The system uses a metadata-driven approach for token decimals:
- **Native tokens**: 18 decimals (ETH, MATIC, etc.) - automatic
- **Stablecoins**: 6 decimals default (USDT, USDC, etc.) - configurable
- **Metadata storage**: PostgreSQL `public.stablecoin_metadata` table
- **Dynamic scaling**: SQL helper functions automatically scale values in dashboards
- **Portal rewards**: Supports both native and ERC20 token rewards with automatic scaling

## Step 1: Add Stablecoin to rindexer.yaml

Add the new stablecoin contract configuration with metadata:

```yaml
contracts:
  - name: StableNewToken
    details:
      - network: ethereum
        address: "0x..."
        start_block: "12345678"
      - network: arbitrum-one
        address: "0x..."
        start_block: "87654321"
    abi: /abis/tokens/ERC20.abi.json
    include_events:
      - Transfer
      - Approval
    # Token metadata for dashboards
    metadata:
      symbol: "NEWTOKEN"
      decimals: 6  # Change if different (e.g., 18 for DAI, 8 for WBTC)
      description: "New Stablecoin Token"
```

### Common Token Decimals

- **6 decimals**: USDT, USDC, USDC.e (most stablecoins)
- **18 decimals**: DAI, FRAX (Ethereum-native tokens)
- **8 decimals**: WBTC (Bitcoin-pegged)
- **2 decimals**: GUSD (Gemini Dollar)

## Step 2: Add Metadata to PostgreSQL

After rindexer indexes the new token, add metadata to the database:

```sql
INSERT INTO public.stablecoin_metadata (
    schema_name,
    symbol,
    decimals,
    description,
    contract_addresses
)
VALUES (
    'ecorindexer_stable_newtoken',  -- Schema name created by rindexer
    'NEWTOKEN',
    6,  -- Match the decimals from rindexer.yaml
    'New Stablecoin Token',
    '{
        "ethereum": "0x...",
        "arbitrum-one": "0x..."
    }'::jsonb
)
ON CONFLICT (schema_name) DO UPDATE SET
    decimals = EXCLUDED.decimals,
    description = EXCLUDED.description,
    contract_addresses = EXCLUDED.contract_addresses,
    updated_at = NOW();
```

You can run this SQL via:

```bash
docker exec eco-rindexer-postgres psql -U postgres -d eco_rindexer -c "INSERT INTO..."
```

## Step 3: Update Dashboard Queries (Optional)

The stablecoin-transfers dashboard currently queries only `ecorindexer_stable_usdt_0`. To include the new token:

### Option A: Query Specific Schema

Add the schema name to existing queries (requires manual updates):

```sql
-- Update each query to add UNION ALL
SELECT ... FROM ecorindexer_stable_usdt_0.transfer ...
UNION ALL
SELECT ... FROM ecorindexer_stable_newtoken.transfer ...
```

### Option B: Use the Unified View (Recommended)

The system provides `public.v_all_stablecoin_transfers` which automatically includes all configured stablecoins:

```sql
SELECT
    symbol,
    value_scaled as amount,
    network,
    block_timestamp
FROM public.v_all_stablecoin_transfers
WHERE $__timeFilter(block_timestamp)
ORDER BY block_timestamp DESC
```

**Note**: The view needs to be manually updated to include new schemas (see sql/03_stablecoin_metadata.sql).

## Step 4: Verify Setup

### Check Metadata

```sql
SELECT * FROM public.stablecoin_metadata;
```

### Test Decimal Scaling

```sql
SELECT
    schema_name,
    public.get_stablecoin_decimals(schema_name) as decimals,
    public.scale_token_value('1000000', schema_name) as scaled_value
FROM public.stablecoin_metadata;
```

Expected output:
```
       schema_name        | decimals | scaled_value
--------------------------+----------+--------------
 ecorindexer_stable_usdt_0|        6 |            1
 ecorindexer_stable_dai   |       18 | 0.000000000001
```

### Verify Dashboard Queries

Open Grafana and check that:
1. New token data appears in appropriate dashboards
2. Values are correctly scaled (no huge numbers like "5000000")
3. Aggregations (SUM, AVG) work correctly

## Architecture

### SQL Helper Functions

```sql
-- Returns decimals for a schema (defaults to 6)
public.get_stablecoin_decimals(schema_name TEXT) RETURNS INTEGER

-- Scales a raw value string to human-readable decimal
public.scale_token_value(value_param TEXT, schema_name_param TEXT) RETURNS NUMERIC
```

### Query Patterns

**Stablecoin Transfers** use schema-based scaling:

```sql
SELECT
    SUM(value::numeric / POWER(10, public.get_stablecoin_decimals('ecorindexer_stable_usdt_0')))
FROM ecorindexer_stable_usdt_0.transfer
```

**Portal Rewards** use contract address-based scaling:

```sql
-- Native tokens (18 decimals)
SELECT public.scale_native_token(reward_native_amount) FROM intent_published

-- ERC20 tokens (variable decimals by contract address)
SELECT public.scale_token_by_address(
    reward_tokens_amount,
    reward_tokens_token,
    network
) FROM intent_published

-- Combined rewards (native + token in native equivalent)
SELECT public.total_reward_value(
    reward_native_amount,
    reward_tokens_amount,
    reward_tokens_token,
    network,
    1.0  -- price ratio
) FROM intent_published
```

This ensures:
- **Automatic scaling** based on metadata table
- **Native tokens**: Always 18 decimals
- **Stablecoins**: Default to 6 if not found in metadata
- **Easy updates** - change decimals in one place (metadata table)
- **Portal rewards**: Automatically lookup decimals by contract address

## Troubleshooting

### Values showing as huge numbers (e.g., 5000000 instead of 5)

**Cause**: Metadata not configured or query not using helper function

**Fix**:
```sql
-- Check if metadata exists
SELECT * FROM public.stablecoin_metadata WHERE schema_name = 'ecorindexer_stable_yourtoken';

-- Add if missing
INSERT INTO public.stablecoin_metadata ...
```

### Query returns NULL or 0 for scaled values

**Cause**: Schema name mismatch or decimals = 0

**Fix**:
```sql
-- Verify schema name matches
SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'ecorindexer_stable_%';

-- Check decimals value
SELECT decimals FROM public.stablecoin_metadata WHERE schema_name = 'your_schema';
```

### New token not appearing in dashboard

**Cause**: Dashboard queries don't include the new schema

**Fix**: Update queries to include new schema or use unified view (see Step 3)

## Files Modified

When adding a new stablecoin, these files are involved:

1. **rindexer.yaml** - Contract configuration with metadata
2. **sql/03_stablecoin_metadata.sql** - Add INSERT statement (optional, for version control)
3. **dashboards/blockchain/stablecoin-transfers.json** - Update queries to include new schema (optional)

## Example: Adding DAI

```yaml
# rindexer.yaml
- name: StableDAI
  details:
    - network: ethereum
      address: "0x6B175474E89094C44Da98b954EedeAC495271d0F"
      start_block: "8928158"
  abi: /abis/tokens/ERC20.abi.json
  include_events:
    - Transfer
    - Approval
  metadata:
    symbol: "DAI"
    decimals: 18  # DAI uses 18 decimals!
    description: "MakerDAO Stablecoin"
```

```sql
-- Add to PostgreSQL
INSERT INTO public.stablecoin_metadata (schema_name, symbol, decimals, description, contract_addresses)
VALUES (
    'ecorindexer_stable_dai',
    'DAI',
    18,
    'MakerDAO Stablecoin',
    '{"ethereum": "0x6B175474E89094C44Da98b954EedeAC495271d0F"}'::jsonb
);
```

## Best Practices

1. **Always verify decimals** by checking the contract or documentation
2. **Test queries** with small datasets before running on full data
3. **Update metadata table** immediately after adding contract to rindexer.yaml
4. **Document custom decimals** in comments if not using 6
5. **Keep contract_addresses JSONB** up to date for reference

## Support

For issues or questions, check:
- `/sql/03_stablecoin_metadata.sql` - Complete metadata table definition
- `/dashboards/blockchain/stablecoin-transfers.json` - Example query patterns
- PostgreSQL logs: `docker logs eco-rindexer-postgres`
