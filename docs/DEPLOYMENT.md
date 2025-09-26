# Deployment Guide

This guide covers deploying the Eco Rindexer in production environments.

## Prerequisites

- **Node.js**: v18 or higher
- **PostgreSQL**: v13 or higher
- **Redis**: v6 or higher (optional, for caching)
- **Docker**: For containerized deployment
- **Minimum Hardware**: 16GB RAM, 8 CPU cores, 500GB SSD storage

## Environment Setup

1. **Clone Repository**
```bash
git clone <repository-url>
cd eco-rindexer
```

2. **Install Dependencies**
```bash
npm install
```

3. **Configure Environment**
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. **Database Setup**
```bash
# Create database
createdb eco_rindexer

# Run migrations (if using custom migrations)
npm run migrate

# Apply indexes and views
psql eco_rindexer < sql/indexes.sql
psql eco_rindexer < sql/views.sql
```

## Production Deployment

### Docker Deployment

1. **Build Image**
```bash
docker build -t eco-rindexer .
```

2. **Run with Docker Compose**
```bash
docker-compose up -d
```

### Manual Deployment

1. **Start Services**
```bash
# Start Rindexer
rindexer start

# Start monitoring (optional)
cd monitoring
docker-compose up -d
```

2. **Verify Deployment**
```bash
# Check indexing status
curl http://localhost:8080/health

# Check GraphQL endpoint
curl http://localhost:4000/graphql
```

## Monitoring Setup

1. **Prometheus + Grafana**
```bash
cd monitoring
docker-compose up -d prometheus grafana
```

2. **Access Dashboards**
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090

## Scaling Configuration

### Horizontal Scaling
- Deploy multiple indexer instances for different chain sets
- Use load balancer for GraphQL API
- Implement database read replicas

### Vertical Scaling
- Increase worker processes
- Optimize batch sizes
- Tune database connections

## Security Considerations

- Secure API keys in environment variables
- Use HTTPS in production
- Implement rate limiting
- Regular security updates

## Backup Strategy

1. **Database Backups**
```bash
# Daily backup
pg_dump eco_rindexer > backup_$(date +%Y%m%d).sql

# Automated backup with retention
0 2 * * * /scripts/backup.sh
```

2. **Configuration Backups**
- Version control for configurations
- Backup API keys securely
- Document recovery procedures