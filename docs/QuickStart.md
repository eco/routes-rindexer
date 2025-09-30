# Quick Start Guide - Eco Rindexer Local Development

This guide will help you set up a local development environment for the Eco Rindexer to index Portal contracts and stable tokens across EVM chains.

## Prerequisites

Before starting, ensure you have the following installed:

- **Docker** (v20.10+) and **Docker Compose** (v2.0+)
- **Node.js** (v18+) and **pnpm** (v8.0+)
- **PostgreSQL** (v15+) - for local development without Docker
- **Git** - for cloning the repository

### System Requirements

- **Memory**: 8GB RAM minimum (16GB recommended)
- **Storage**: 50GB free space minimum
- **CPU**: 4+ cores recommended
- **Network**: Stable internet connection for RPC calls

## Environment Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd routes-rindexer
```

### 2. Install Dependencies

```bash
pnpm install
```

### 3. Configure Environment Variables

Create your environment file from the template:

```bash
cp .env.example .env
```

Edit the `.env` file with your configuration:

```bash
# Required API Keys
ALCHEMY_API_KEY=your_alchemy_api_key_here
INFURA_API_KEY=your_infura_api_key_here

# Optional API Keys (for specific networks)
CURTIS_API_KEY=your_curtis_api_key
MANTA_API_KEY=your_manta_api_key

# Database Configuration
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=eco_rindexer
DATABASE_USER=postgres
DATABASE_PASSWORD=your_secure_password

# Redis Configuration (optional)
REDIS_PORT=6379

# Monitoring Configuration
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
GRAFANA_PASSWORD=admin

# Native Token Addresses to Track (comma-separated)
TRACK_NATIVE_TOKEN_ADDRESSES=0x742d35Cc6634C0532925a3b8D4ed48C35B4e4b8b,0x456...
```

### 4. API Key Setup

You'll need API keys from RPC providers for reliable blockchain access:

#### Required Keys:
- **Alchemy** (Primary): Sign up at [alchemy.com](https://alchemy.com)
  - Supports: Ethereum, Arbitrum, Base, Polygon, Optimism
  - Free tier: 300M compute units/month

- **Infura** (Backup): Sign up at [infura.io](https://infura.io)
  - Provides failover support
  - Free tier: 100,000 requests/day

#### Optional Keys (for specific networks):
- **Curtis API** - For Curtis chain support
- **Manta API** - For Manta Pacific support

## Local Development Options

Choose one of the following setup methods:

## Option 1: Full Docker Setup (Recommended)

This is the easiest method for getting started quickly.

### Start All Services

```bash
# Start the complete stack
docker-compose up -d

# Check service status
docker-compose ps

# Follow logs
docker-compose logs -f rindexer
```

### Service Endpoints

Once running, you can access:

- **GraphQL API**: http://localhost:4000/graphql
- **eRPC Proxy**: http://localhost:4000 (RPC endpoint)
- **Database**: localhost:5432
- **Redis**: localhost:6379
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin)

### Stop Services

```bash
docker-compose down
```

## Option 2: Hybrid Setup (Local Rindexer + Docker Infrastructure)

Run infrastructure in Docker but Rindexer locally for development.

### Start Infrastructure Services

```bash
# Start only database, Redis, and monitoring
docker-compose up -d postgres redis erpc prometheus grafana
```

### Install Rindexer CLI

```bash
# Install rindexer globally
npm install -g @rindexer/cli

# Or use with npx
npx @rindexer/cli --version
```

### Start Local Rindexer

```bash
# Start indexing
rindexer start

# Start with specific config
rindexer start --config ./rindexer.yaml
```

## Option 3: Full Local Setup

For advanced users who want complete local control.

### Setup PostgreSQL

```bash
# Install PostgreSQL (macOS with Homebrew)
brew install postgresql@15
brew services start postgresql@15

# Create database
createdb eco_rindexer

# Create user and grant permissions
psql eco_rindexer
CREATE USER postgres WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE eco_rindexer TO postgres;
\q
```

### Setup Redis (Optional)

```bash
# Install Redis (macOS with Homebrew)
brew install redis
brew services start redis
```

### Install and Start Rindexer

```bash
# Install Rindexer
npm install -g @rindexer/cli

# Start indexing
rindexer start --config ./rindexer.yaml
```

## Configuration Overview

### Network Configuration

The indexer is configured to use eRPC proxy for fault-tolerant RPC access. Currently configured for testing with:

- **Plasma Mainnet** (Chain ID: 9745)
- All other networks commented out for testing

### Contract Indexing

Currently configured to index:

- **Portal Contract**: `0xB5e58A8206473Df3Ab9b8DDd3B0F84c0ba68F8b5`
  - Events: IntentPublished, IntentFulfilled, IntentFunded, etc.
- **Stable Token Contracts**: USDC, USDT, USDCe, oUSDT (commented out for testing)

### Database Schema

The indexer creates the following main tables:

- `chain_events` - All indexed events with common fields
- `intent_activities` - Portal-specific intent lifecycle tracking
- `stable_transfers` - ERC20 stable token movements
- `native_transfers` - Native token transfer tracking
- `native_balances` - Address balance snapshots
- `network_health` - RPC and indexing health metrics

## Verification and Testing

### 1. Check Service Health

```bash
# Check rindexer health
curl http://localhost:8080/health

# Check eRPC proxy health
curl http://localhost:4000/health

# Check GraphQL endpoint
curl http://localhost:4000/graphql
```

### 2. Query Data via GraphQL

Open http://localhost:4000/graphql in your browser to access the GraphQL playground.

Example queries:

```graphql
# Get recent intent activities
query GetRecentIntents {
  intents(limit: 10, orderBy: { publishedAt: DESC }) {
    hash
    chainId
    creator
    status
    publishedAt
  }
}

# Check network health
query GetNetworkHealth {
  chains {
    id
    name
    isHealthy
    lastUpdated
    blockNumber
  }
}
```

### 3. Monitor Database

```bash
# Connect to database
psql postgresql://postgres:your_password@localhost:5432/eco_rindexer

# Check indexed events
SELECT
    chain_id,
    event_name,
    COUNT(*) as event_count,
    MAX(block_timestamp) as latest_event
FROM chain_events
GROUP BY chain_id, event_name
ORDER BY latest_event DESC;
```

## Common Issues and Solutions

### Database Connection Issues

```bash
# Check if PostgreSQL is running
brew services list | grep postgresql

# Restart PostgreSQL
brew services restart postgresql@15

# Check connection
psql postgresql://postgres:password@localhost:5432/eco_rindexer
```

### Docker Image Issues

If you get "pull access denied" for erpc image:

```bash
# The correct image is ghcr.io/erpc/erpc:latest
# This should already be fixed in docker-compose.yml

# If still having issues, try pulling manually:
docker pull ghcr.io/erpc/erpc:latest
```

### RPC Issues

```bash
# Check eRPC proxy logs
docker-compose logs erpc

# Test RPC endpoint directly
curl -X POST http://localhost:4000/main/evm/9745 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Memory Issues

```bash
# Check Docker container memory usage
docker stats

# Increase Docker memory limit in Docker Desktop settings
# Recommended: 8GB+ for full stack
```

### Port Conflicts

```bash
# Check what's using specific ports
lsof -i :4000  # GraphQL/eRPC
lsof -i :5432  # PostgreSQL
lsof -i :6379  # Redis

# Kill processes if needed
kill -9 <PID>
```

## Development Workflow

### 1. Enable More Networks

Edit `rindexer.yaml` to uncomment additional networks:

```yaml
networks:
  # Uncomment networks as needed
  - name: ethereum
    chain_id: 1
    rpc: "http://erpc:4000/main/evm/1"

  - name: arbitrum-one
    chain_id: 42161
    rpc: "http://erpc:4000/main/evm/42161"
```

### 2. Add More Contracts

Add stable token contracts or other contracts:

```yaml
contracts:
  - name: StableUSDC
    details:
      - network: ethereum
        address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        start_block: "6082465"
    abi: ./abis/tokens/ERC20.abi.json
    include_events:
      - Transfer
```

### 3. Testing Configuration Changes

```bash
# Restart rindexer with new config
docker-compose restart rindexer

# Or for local development
rindexer stop
rindexer start --config ./rindexer.yaml
```

### 4. Database Monitoring

```bash
# Watch indexing progress
watch -n 5 "psql postgresql://postgres:password@localhost:5432/eco_rindexer -c \"
SELECT
  chain_id,
  MAX(block_number) as latest_block,
  COUNT(*) as total_events,
  MAX(created_at) as last_updated
FROM chain_events
GROUP BY chain_id
ORDER BY chain_id;
\""
```

## Performance Tuning

### Database Optimization

```sql
-- Apply performance indexes
\i sql/indexes.sql

-- Create materialized views
\i sql/views.sql

-- Check query performance
SELECT query, mean_time, calls FROM pg_stat_statements
WHERE mean_time > 100 ORDER BY mean_time DESC;
```

### Docker Resource Limits

Edit `docker-compose.yml` to adjust resources:

```yaml
services:
  rindexer:
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2'
        reservations:
          memory: 2G
          cpus: '1'
```

## Next Steps

Once your local environment is running:

1. **Explore the GraphQL API** - Use the playground to understand available queries
2. **Check Database Schema** - Review [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) for table structure
3. **Configure More Networks** - Gradually enable more chains as needed
4. **Set Up Monitoring** - Access Grafana dashboards for system monitoring
5. **Read API Documentation** - Review [API.md](./API.md) for advanced queries

## Support

For issues and questions:

- Check existing documentation in the `docs/` folder
- Review Docker logs: `docker-compose logs <service-name>`
- Monitor system health via Grafana dashboards

This setup provides a complete local development environment for indexing blockchain data across the Eco Foundation ecosystem.