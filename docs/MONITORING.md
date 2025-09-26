# Eco Rindexer Monitoring Setup

This document outlines the comprehensive monitoring setup for the Eco Foundation rindexer deployment across 34 blockchain networks.

## Overview

The monitoring infrastructure consists of:
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and notifications

## Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Rindexer   │───▶│ Prometheus  │───▶│   Grafana   │
│   Metrics   │    │   Server    │    │ Dashboard   │
└─────────────┘    └─────────────┘    └─────────────┘
                           │
                           ▼
                   ┌─────────────┐
                   │AlertManager │
                   │   Alerts    │
                   └─────────────┘
```

## Quick Start

### 1. Start Monitoring Stack

```bash
# Start all monitoring services
docker-compose -f monitoring/docker-compose.yml up -d

# Or start full production stack
docker-compose up -d
```

### 2. Access Dashboards

- **Grafana**: http://localhost:3000
  - Username: `admin`
  - Password: Set via `GRAFANA_PASSWORD` environment variable
- **Prometheus**: http://localhost:9090
- **AlertManager**: http://localhost:9093

## Key Performance Indicators (KPIs)

### Technical Metrics

| Metric | Target | Critical Threshold |
|--------|--------|--------------------|
| Indexing Speed | >1000 blocks/minute per network | <500 blocks/minute |
| Portal Event Processing | >5,000 events/second | <1,000 events/second |
| Native Transfer Processing | >10,000 transfers/second | <2,000 transfers/second |
| Database Query Performance | <100ms avg response | >500ms avg response |
| System Uptime | >99.9% | <99.0% |
| RPC Success Rate | >99.5% | <95.0% |

### Data Quality Metrics

- **Event Completeness**: 100% of emitted events captured
- **Data Consistency**: Zero duplicate or missing events
- **Cross-Chain Coherence**: Consistent intent state across networks
- **Real-time Latency**: <30 seconds behind blockchain head

## Alert Configuration

### Alert Rules

The system monitors the following conditions:

#### Critical Alerts

```yaml
- name: IndexingLag
  condition: "block_lag > 100"
  severity: critical
  description: "Indexer is falling behind blockchain head"

- name: RPCFailure
  condition: "rpc_error_rate > 10%"
  severity: critical
  description: "High RPC failure rate detected"

- name: DatabaseConnections
  condition: "db_connections > 80"
  severity: critical
  description: "Database connection pool exhaustion"
```

#### Warning Alerts

```yaml
- name: HighMemoryUsage
  condition: "memory_usage > 80%"
  severity: warning
  description: "High memory utilization"

- name: NativeTransferLag
  condition: "native_transfer_lag > 50 blocks"
  severity: warning
  description: "Native transfer processing lag"
```

### Notification Channels

Configure alert destinations in your environment:

```bash
# Slack webhook for alerts
ALERT_WEBHOOK_URL=https://hooks.slack.com/your-webhook

# Email notifications (optional)
SMTP_SERVER=smtp.your-domain.com
ALERT_EMAIL=alerts@your-domain.com
```

## Dashboard Overview

### Main Dashboard Panels

1. **System Health**
   - Overall indexer status
   - Database connectivity
   - RPC endpoint health

2. **Indexing Performance**
   - Blocks processed per minute per network
   - Event processing rates
   - Native transfer processing

3. **Database Performance**
   - Query execution times
   - Connection pool usage
   - Storage utilization

4. **Network Activity**
   - Portal intent volumes by chain
   - Stable token transfer activity
   - Native balance tracking metrics

5. **Error Monitoring**
   - RPC failures by endpoint
   - Database errors
   - Processing exceptions

## Troubleshooting

### Common Issues

#### High Indexing Lag

```bash
# Check RPC health
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC_URL

# Monitor database performance
docker exec -it eco-rindexer-postgres psql -U postgres -d eco_rindexer \
  -c "SELECT * FROM pg_stat_activity WHERE state = 'active';"
```

#### High Memory Usage

```bash
# Check container memory usage
docker stats

# Optimize batch sizes in rindexer.yaml
# Reduce from 1000 to 500 if needed
batch_size: 500
```

#### Database Connection Issues

```sql
-- Check active connections
SELECT count(*) FROM pg_stat_activity;

-- Kill long-running queries
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active' AND query_start < now() - interval '5 minutes';
```

### Log Analysis

```bash
# View rindexer logs
docker logs -f eco-rindexer

# View database logs
docker logs -f eco-rindexer-postgres

# View prometheus logs
docker logs -f eco-rindexer-prometheus
```

## Maintenance

### Daily Tasks

- [ ] Check dashboard for any alerts
- [ ] Verify indexing is keeping up with blockchain head
- [ ] Monitor disk space usage
- [ ] Review error logs for any issues

### Weekly Tasks

- [ ] Analyze performance trends
- [ ] Update dashboards if needed
- [ ] Review and tune alert thresholds
- [ ] Check backup status

### Monthly Tasks

- [ ] Archive old metrics data
- [ ] Review capacity planning
- [ ] Update monitoring documentation
- [ ] Security audit of monitoring stack

## Performance Tuning

### Database Optimization

```sql
-- Create performance indexes
CREATE INDEX CONCURRENTLY idx_chain_events_chain_block
  ON chain_events (chain_id, block_number DESC);

-- Update statistics
ANALYZE chain_events;
```

### Memory Management

```bash
# Adjust PostgreSQL memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
```

## Security Considerations

- Grafana admin credentials should be changed from defaults
- AlertManager webhook URLs should use HTTPS
- Database connections should be encrypted in production
- Access to monitoring ports should be restricted

## Support

For monitoring issues:
1. Check the troubleshooting section above
2. Review container logs
3. Verify environment variables are set correctly
4. Ensure network connectivity between services

For further assistance, refer to:
- [Deployment Guide](./DEPLOYMENT.md)
- [Database Schema Documentation](./DATABASE_SCHEMA.md)
- [API Documentation](./API.md)