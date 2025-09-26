# eRPC Proxy Migration Documentation

## Overview

The Eco Rindexer project has been migrated from manual RPC fallback configuration to use eRPC (Enhanced RPC), a fault-tolerant RPC proxy with intelligent caching and automatic failover capabilities.

## Architecture Changes

### Before: Manual Fallback Configuration
```yaml
networks:
  - name: ethereum
    chain_id: 1
    rpc: "https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
    rpc_fallbacks:
      - "https://mainnet.infura.io/v3/${INFURA_API_KEY}"
      - "https://eth.merkle.io"
```

### After: eRPC Proxy Configuration
```yaml
networks:
  - name: ethereum
    chain_id: 1
    rpc: "http://erpc:4000/main/evm/1"
```

## Benefits of eRPC Integration

### 1. Automated Failover
- **Intelligent routing**: eRPC automatically routes requests to the best available upstream
- **Priority-based selection**: Higher priority upstreams are preferred when available
- **Circuit breaker pattern**: Failed upstreams are temporarily removed from rotation

### 2. Advanced Caching
- **Re-org aware caching**: Handles blockchain reorganizations intelligently
- **Memory-based cache**: Fast response times for repeated requests
- **Configurable TTL**: Optimized cache duration for blockchain data

### 3. Enhanced Reliability
- **Health monitoring**: Continuous health checks for all RPC endpoints
- **Rate limiting**: Built-in rate limiting to prevent API quota exhaustion
- **Retry logic**: Exponential backoff and configurable retry attempts

### 4. Operational Improvements
- **Centralized configuration**: All RPC endpoints managed in one place
- **Metrics and monitoring**: Built-in metrics for performance analysis
- **Load balancing**: Automatic load distribution across multiple providers

## Network Configuration

### Tier 1 Networks (Premium Support)
All tier 1 networks now use multiple premium RPC providers through eRPC:
- **Ethereum (Chain ID 1)**: Alchemy → Infura → Public RPC
- **Arbitrum One (42161)**: Alchemy → Public RPC
- **Base (8453)**: Alchemy → Public RPC
- **Polygon (137)**: Alchemy → Public RPC
- **Optimism (10)**: Alchemy → Public RPC

### Tier 2 & 3 Networks
Community and specialized networks configured with available public endpoints:
- Single or dual RPC provider configurations
- Automatic failover where multiple providers available
- Consistent proxy routing through eRPC

### Testnet Networks
All testnet networks configured with appropriate test RPC endpoints:
- **Sepolia (11155111)**: Alchemy → Infura → Public
- **OP Sepolia (11155420)**: Alchemy → Infura → Public
- **Base Sepolia (84532)**: Alchemy → Infura → Public

## Docker Compose Integration

### New eRPC Service
```yaml
erpc:
  image: erpc/erpc:latest
  container_name: eco-rindexer-erpc
  environment:
    - ALCHEMY_API_KEY=${ALCHEMY_API_KEY}
    - INFURA_API_KEY=${INFURA_API_KEY}
  volumes:
    - ./erpc.yaml:/root/erpc.yaml
  ports:
    - "4000:4000"  # RPC proxy port
    - "4001:4001"  # Metrics port
```

### Service Dependencies
- **Rindexer** now depends on eRPC service
- **Health checks** include eRPC endpoint monitoring
- **Environment variables** passed to eRPC for API keys

## Configuration Files

### 1. erpc.yaml
- **Project configuration**: Single "main" project with all upstreams
- **Network routing**: Chain ID to upstream mapping
- **Failsafe configuration**: Timeout, retry, and circuit breaker settings
- **Metrics**: Performance monitoring endpoint

### 2. Updated rindexer.yaml
- **Simplified network definitions**: Single RPC URL per network
- **Consistent proxy routing**: All networks use `http://erpc:4000/main/evm/{chainId}`
- **Removed fallback arrays**: eRPC handles all failover logic

### 3. Updated docker-compose.yml
- **eRPC service**: New fault-tolerant proxy service
- **Health monitoring**: Integrated eRPC health checks
- **Metrics exposure**: Prometheus can scrape eRPC metrics

## Migration Benefits Summary

| Aspect | Before | After |
|--------|---------|-------|
| **RPC Management** | Manual fallback arrays | Automated intelligent routing |
| **Caching** | Basic rindexer cache | Advanced re-org aware caching |
| **Failover** | Sequential fallback | Priority-based with circuit breakers |
| **Monitoring** | Limited visibility | Comprehensive metrics and health checks |
| **Configuration** | Duplicated per network | Centralized in eRPC config |
| **Maintenance** | Manual endpoint management | Automatic health monitoring |

## Deployment Considerations

### 1. Environment Variables
Ensure all required API keys are available:
- `ALCHEMY_API_KEY`: Premium Alchemy endpoints
- `INFURA_API_KEY`: Infura fallback endpoints

### 2. Port Configuration
eRPC exposes two ports:
- **4000**: Main RPC proxy endpoint
- **4001**: Metrics and monitoring endpoint

### 3. Health Monitoring
eRPC includes built-in health checks at `/health` endpoint

### 4. Metrics Collection
Prometheus can collect eRPC metrics from port 4001

## Troubleshooting

### Common Issues
1. **API Key Configuration**: Verify environment variables are properly set
2. **Network Connectivity**: Ensure eRPC can reach upstream RPC providers
3. **Chain ID Mapping**: Verify chain IDs match between rindexer.yaml and erpc.yaml
4. **Service Startup Order**: eRPC must start before rindexer service

### Monitoring Commands
```bash
# Check eRPC health
curl http://localhost:4000/health

# View eRPC metrics
curl http://localhost:4001/metrics

# Monitor eRPC logs
docker logs eco-rindexer-erpc

# Test specific chain routing
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:4000/main/evm/1
```

## Performance Expectations

### Improved Metrics
- **Reduced RPC failures**: Automatic failover reduces indexing interruptions
- **Faster response times**: Intelligent caching for repeated requests
- **Better resource utilization**: Load balancing across providers
- **Enhanced reliability**: Circuit breakers prevent cascade failures

### Monitoring Opportunities
- **RPC success rates**: Per-provider success/failure metrics
- **Cache hit rates**: Memory cache effectiveness
- **Response latencies**: Provider performance comparison
- **Failover events**: Automatic switching frequency

This migration represents a significant improvement in the reliability, performance, and maintainability of the Eco Rindexer RPC infrastructure.