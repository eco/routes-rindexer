# eRPC Quick Reference Guide

## Quick Start Commands

### 1. Start the Stack
```bash
# Start all services including eRPC
docker-compose up -d

# View logs
docker-compose logs -f erpc
docker-compose logs -f rindexer
```

### 2. Health Checks
```bash
# Check eRPC health
curl http://localhost:4000/health

# Check all services
docker-compose ps
```

### 3. Test RPC Endpoints
```bash
# Test Ethereum mainnet
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:4000/main/evm/1

# Test Arbitrum One
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:4000/main/evm/42161

# Test Base
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:4000/main/evm/8453
```

## Network URL Format

All networks use the same URL pattern in rindexer.yaml:
```
http://erpc:4000/main/evm/{chainId}
```

### Major Networks
| Network | Chain ID | URL |
|---------|----------|-----|
| Ethereum | 1 | `http://erpc:4000/main/evm/1` |
| Arbitrum One | 42161 | `http://erpc:4000/main/evm/42161` |
| Base | 8453 | `http://erpc:4000/main/evm/8453` |
| Polygon | 137 | `http://erpc:4000/main/evm/137` |
| Optimism | 10 | `http://erpc:4000/main/evm/10` |

## Environment Variables

Required for API key substitution in erpc.yaml:
```bash
ALCHEMY_API_KEY=your_alchemy_key
INFURA_API_KEY=your_infura_key
```

## Monitoring & Metrics

### eRPC Metrics Endpoint
```bash
# View all metrics
curl http://localhost:4001/metrics

# Filter specific metrics (requires jq)
curl -s http://localhost:4001/metrics | grep -E "(rpc_requests|cache_hits|upstream_errors)"
```

### Service Status
```bash
# Check container health
docker inspect eco-rindexer-erpc --format='{{.State.Health.Status}}'

# View resource usage
docker stats eco-rindexer-erpc --no-stream
```

## Configuration Updates

### Adding New RPC Provider
1. Add upstream to `erpc.yaml` upstreams section
2. Add to appropriate network in networks section
3. Restart eRPC service: `docker-compose restart erpc`

### Changing Failover Priority
Edit the `priority` field in erpc.yaml networks section:
- Higher numbers = higher priority
- eRPC routes to highest available priority upstream

### Example Priority Configuration
```yaml
networks:
  - chainId: 1
    upstreams:
      - id: alchemy-mainnet
        priority: 100  # Primary
      - id: infura-mainnet
        priority: 90   # Secondary
      - id: eth-merkle
        priority: 80   # Tertiary
```

## Troubleshooting

### Common Issues

1. **eRPC won't start**
   - Check API keys are set: `docker-compose config`
   - Verify erpc.yaml syntax: `docker-compose logs erpc`

2. **RPC requests fail**
   - Test individual upstreams directly
   - Check upstream health in eRPC logs
   - Verify chain ID mapping

3. **Performance issues**
   - Monitor cache hit rates in metrics
   - Check upstream response times
   - Consider adding more RPC providers

### Debug Commands
```bash
# Check eRPC configuration
docker exec eco-rindexer-erpc cat /root/erpc.yaml

# View detailed logs
docker-compose logs --tail=100 erpc

# Test specific upstream (example)
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY
```

## Performance Optimization

### Cache Configuration
Current settings in erpc.yaml:
- **Driver**: Memory-based (fast)
- **Max Items**: 10,000 cached responses
- **TTL**: Automatic based on blockchain finality

### Rate Limiting
Default configuration:
- **Global limit**: 1000 requests per second
- **Per-method**: All methods included
- **Scope**: Applied across all networks

### Timeout Settings
- **Request timeout**: 30 seconds
- **Retry attempts**: 3 per upstream
- **Backoff**: Exponential (1s, 2s, 4s)
- **Circuit breaker**: 5 failures trigger temp disable

## Monitoring Dashboard Ideas

Metrics to track:
- RPC request success/failure rates per chain
- Cache hit/miss ratios
- Upstream response latencies
- Failover events frequency
- Total requests per second

Connect to Prometheus at `http://localhost:4001/metrics` for visualization in Grafana.

## Migration Benefits Realized

✅ **Eliminated manual fallback configuration**
✅ **Automatic failover with circuit breakers**
✅ **Intelligent caching for better performance**
✅ **Centralized RPC endpoint management**
✅ **Built-in monitoring and metrics**
✅ **Reduced maintenance overhead**