#!/bin/bash

# Validation script for eRPC migration
# This script validates the migration from manual RPC fallbacks to eRPC proxy

set -e

echo "🔍 Validating eRPC Migration..."
echo "=================================="

# Check if required files exist
echo "📁 Checking configuration files..."

if [ ! -f "erpc.yaml" ]; then
    echo "❌ erpc.yaml not found"
    exit 1
fi
echo "✅ erpc.yaml exists"

if [ ! -f "rindexer.yaml" ]; then
    echo "❌ rindexer.yaml not found"
    exit 1
fi
echo "✅ rindexer.yaml exists"

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ docker-compose.yml not found"
    exit 1
fi
echo "✅ docker-compose.yml exists"

# Validate rindexer.yaml has no fallback configurations
echo ""
echo "🔧 Validating rindexer.yaml configuration..."

if grep -q "rpc_fallbacks:" rindexer.yaml; then
    echo "❌ rindexer.yaml still contains rpc_fallbacks - migration incomplete"
    exit 1
fi
echo "✅ No rpc_fallbacks found in rindexer.yaml"

# Check if all networks use eRPC proxy format
erpc_pattern="http://erpc:4000/main/evm/"
if ! grep -q "$erpc_pattern" rindexer.yaml; then
    echo "❌ rindexer.yaml doesn't contain eRPC proxy URLs"
    exit 1
fi
echo "✅ eRPC proxy URLs found in rindexer.yaml"

# Count networks using eRPC
network_count=$(grep -c "rpc: \"http://erpc:4000/main/evm/" rindexer.yaml)
echo "✅ Found $network_count networks using eRPC proxy"

# Validate docker-compose.yml has eRPC service
echo ""
echo "🐳 Validating docker-compose.yml configuration..."

if ! grep -q "erpc:" docker-compose.yml; then
    echo "❌ eRPC service not found in docker-compose.yml"
    exit 1
fi
echo "✅ eRPC service found in docker-compose.yml"

if ! grep -q "image: erpc/erpc:latest" docker-compose.yml; then
    echo "❌ eRPC image not configured correctly"
    exit 1
fi
echo "✅ eRPC image configured correctly"

# Check if rindexer depends on erpc
if grep -A 10 "rindexer:" docker-compose.yml | grep -A 5 "depends_on:" | grep -q "erpc"; then
    echo "✅ Rindexer service correctly depends on eRPC"
else
    echo "⚠️  Warning: rindexer service may not depend on eRPC service"
fi

# Validate erpc.yaml configuration
echo ""
echo "⚙️  Validating erpc.yaml configuration..."

if ! grep -q "projects:" erpc.yaml; then
    echo "❌ erpc.yaml missing projects configuration"
    exit 1
fi
echo "✅ Projects configuration found"

if ! grep -q "networks:" erpc.yaml; then
    echo "❌ erpc.yaml missing networks configuration"
    exit 1
fi
echo "✅ Networks configuration found"

if ! grep -q "upstreams:" erpc.yaml; then
    echo "❌ erpc.yaml missing upstreams configuration"
    exit 1
fi
echo "✅ Upstreams configuration found"

# Count chain IDs in erpc.yaml
chain_count=$(grep -c "chainId:" erpc.yaml)
echo "✅ Found $chain_count chain configurations in eRPC"

# Validate environment variables are referenced
echo ""
echo "🔐 Validating environment variable usage..."

if ! grep -q "ALCHEMY_API_KEY" erpc.yaml; then
    echo "⚠️  Warning: ALCHEMY_API_KEY not found in erpc.yaml"
fi

if ! grep -q "INFURA_API_KEY" erpc.yaml; then
    echo "⚠️  Warning: INFURA_API_KEY not found in erpc.yaml"
fi

# Summary
echo ""
echo "📊 Migration Summary"
echo "==================="
echo "Networks in rindexer.yaml: $network_count"
echo "Chain configurations in eRPC: $chain_count"

if [ "$network_count" -ne "$chain_count" ]; then
    echo "⚠️  Warning: Mismatch between network count ($network_count) and chain count ($chain_count)"
    echo "    This may indicate missing chain configurations in eRPC"
fi

echo ""
echo "✅ eRPC migration validation completed successfully!"
echo ""
echo "Next steps:"
echo "1. Set required environment variables (ALCHEMY_API_KEY, INFURA_API_KEY)"
echo "2. Start services: docker-compose up -d"
echo "3. Test eRPC health: curl http://localhost:4000/health"
echo "4. Test specific chain: curl -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://localhost:4000/main/evm/1"
echo "5. Monitor eRPC metrics: curl http://localhost:4001/metrics"