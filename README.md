# Eco Rindexer

Comprehensive blockchain indexer for the Eco Foundation ecosystem, supporting 34 EVM chains with Portal contract intent lifecycle tracking and stable token monitoring.

## Features

- **Portal Contract Indexing**: Complete intent lifecycle tracking across all deployments
- **Stable Token Monitoring**: ERC20 transfer indexing for 9 stable token types (USDC, USDT, USDCe, etc.)
- **Native Token Tracking**: Balance monitoring for specified addresses across all chains
- **Multi-RPC Strategy**: Automatic failover with premium and public RPC endpoints
- **Real-time GraphQL API**: Query indexed data with powerful filtering and aggregation
- **Comprehensive Analytics**: Pre-computed views and analytics queries

## Supported Networks

### Tier 1 Networks (Premium RPC Support)
- Ethereum (1)
- Arbitrum (42161)
- Base (8453)
- Polygon (137)
- Optimism (10)

### Tier 2 Networks (Standard Support)
- Sonic (146)
- Superseed (5330)
- World Chain (480)
- Ink (57073)

### Additional Networks
27 additional chains including Caldera, specialty, and testnet chains.

## Quick Start

1. **Install Dependencies**
```bash
npm install
```

2. **Configure Environment**
```bash
cp .env.example .env
# Edit .env with your API keys and database credentials
```

3. **Start Indexing**
```bash
rindexer start
```

4. **Access GraphQL API**
Open http://localhost:4000/graphql

## Configuration

The indexer is configured via `rindexer.yaml`. Key sections:

- **Networks**: RPC endpoints with failover strategies
- **Contracts**: Portal and stable token contract definitions
- **Storage**: PostgreSQL database configuration
- **GraphQL**: API endpoint settings

## Documentation

- [API Documentation](docs/API.md) - GraphQL schema and queries
- [Database Schema](docs/DATABASE_SCHEMA.md) - Database design and optimization
- [Deployment Guide](docs/DEPLOYMENT.md) - Production deployment instructions

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   RPC Providers │────│   Rindexer Core  │────│   PostgreSQL    │
│                 │    │                  │    │   Database      │
│ • Alchemy       │    │ • Event Indexing │    │                 │
│ • Infura        │    │ • Data Transform │    │ • Partitioned   │
│ • Public RPCs   │    │ • Error Handling │    │ • Optimized     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                               │
                       ┌──────────────────┐
                       │   GraphQL API    │
                       │                  │
                       │ • Real-time      │
                       │ • Analytics      │
                       │ • Subscriptions  │
                       └──────────────────┘
```

## Monitoring

Includes Prometheus/Grafana stack for monitoring:

- Indexing performance and lag
- RPC endpoint health and response times
- Database performance metrics
- Event processing rates

## Project Structure

```
eco-rindexer/
├── rindexer.yaml              # Main configuration
├── abis/                      # Contract ABIs
│   ├── eco-routes/           # Portal contract ABI
│   └── tokens/               # ERC20 token ABI
├── scripts/                  # Deployment and utility scripts
│   ├── extract-abis.js      # Extract ABIs from packages
│   ├── generate-config.js   # Auto-generate configurations
│   └── validate-rpcs.js     # RPC endpoint validation
├── sql/                     # Database optimization
│   ├── indexes.sql         # Performance indexes
│   ├── views.sql           # Useful data views
│   └── analytics.sql       # Analysis queries
├── monitoring/             # Monitoring stack
│   ├── docker-compose.yml # Prometheus + Grafana
│   └── prometheus.yml     # Metrics configuration
└── docs/                  # Documentation
    ├── API.md            # GraphQL API docs
    ├── DATABASE_SCHEMA.md # Database design
    └── DEPLOYMENT.md     # Deployment guide
```

## License

MIT License
