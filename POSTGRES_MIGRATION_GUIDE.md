# PostgreSQL + TimescaleDB Migration Guide

## Overview

This guide covers the migration from InfluxDB to PostgreSQL + TimescaleDB for the Ruuvi Home sensor data storage system. The new implementation provides better Rust support, real-time notifications, and 5-year data retention with excellent compression.

## What Changed

### Database Stack
- **Before**: InfluxDB 2.x with Flux query language
- **After**: PostgreSQL 15 + TimescaleDB with SQL queries

### Rust Dependencies
- **Removed**: `influxdb2`, `influxdb2-derive`, `influxdb-ruuvi-event`
- **Added**: `postgres-store` (custom crate), `sqlx`, `chrono`

### API Endpoints
- **Enhanced**: All existing endpoints now work with PostgreSQL
- **New**: Time bucketing, aggregates, storage monitoring endpoints

## Prerequisites

1. **Docker & Docker Compose**: Latest version
2. **Rust**: 1.75+ with Cargo
3. **PostgreSQL Client** (optional): For manual database access

## Quick Start

### 1. Environment Setup

Copy the environment template:
```bash
cp .env.example .env
```

Update `.env` with your settings:
```env
# PostgreSQL Configuration
DATABASE_URL=postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home

# API Configuration
API_PORT=8080

# MQTT Configuration
MQTT_HOST=localhost
MQTT_PORT=1883
MQTT_TOPIC=ruuvi/gateway/data
```

### 2. Start the Services

Start all services with Docker Compose:
```bash
docker-compose up -d
```

This will start:
- **TimescaleDB**: PostgreSQL with TimescaleDB extension
- **MQTT Broker**: Eclipse Mosquitto
- **API Server**: Rust API with PostgreSQL backend
- **MQTT Reader**: Sensor data ingestion service
- **Frontend**: React web interface

### 3. Verify Setup

Check service status:
```bash
docker-compose ps
```

Check TimescaleDB initialization:
```bash
docker-compose logs timescaledb
```

Test API health:
```bash
curl http://localhost:8080/health
```

## Database Schema

### Core Table: `sensor_data`

The main hypertable stores all sensor readings:
```sql
CREATE TABLE sensor_data (
    sensor_mac VARCHAR(17) NOT NULL,
    gateway_mac VARCHAR(17) NOT NULL,
    temperature DOUBLE PRECISION NOT NULL,
    humidity DOUBLE PRECISION NOT NULL,
    pressure DOUBLE PRECISION NOT NULL,
    battery BIGINT NOT NULL,
    tx_power BIGINT NOT NULL,
    movement_counter BIGINT NOT NULL,
    measurement_sequence_number BIGINT NOT NULL,
    acceleration DOUBLE PRECISION NOT NULL,
    acceleration_x BIGINT NOT NULL,
    acceleration_y BIGINT NOT NULL,
    acceleration_z BIGINT NOT NULL,
    rssi BIGINT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### TimescaleDB Features

1. **Hypertable**: Automatic time-based partitioning (1-day chunks)
2. **Continuous Aggregates**: Pre-computed hourly and daily summaries
3. **Compression**: 90% space savings after 7 days
4. **Retention**: 5-year retention for raw data, longer for aggregates

### Monitoring Views

- `storage_monitoring`: Current storage usage and compression stats
- `get_storage_stats()`: Detailed storage analysis
- `estimate_storage_requirements()`: Storage estimation for different scenarios

## API Endpoints

### Sensor Data
- `GET /api/sensors` - List active sensors
- `GET /api/sensors/{mac}/latest` - Latest reading for sensor
- `GET /api/sensors/{mac}/history` - Historical data with optional time range

### Time-Series Aggregates
- `GET /api/sensors/{mac}/aggregates?interval=1h&start=&end=` - Flexible time bucketing
- `GET /api/sensors/{mac}/hourly?start=&end=` - Pre-computed hourly aggregates
- `GET /api/sensors/{mac}/daily?start=&end=` - Pre-computed daily aggregates

### Storage Monitoring
- `GET /api/storage/stats` - Current storage usage
- `GET /api/storage/estimate?sensor_count=10&interval_seconds=10&retention_years=5` - Storage estimates

### Query Parameters

**Time Formats**: ISO 8601 (`2024-01-15T10:30:00Z`)
**Intervals**: `15m`, `1h`, `1d`, `1w`

Example queries:
```bash
# Get last 24 hours of data
curl "http://localhost:8080/api/sensors/AA:BB:CC:DD:EE:FF/history?start=2024-01-14T00:00:00Z&end=2024-01-15T00:00:00Z"

# Get hourly averages for last week
curl "http://localhost:8080/api/sensors/AA:BB:CC:DD:EE:FF/aggregates?interval=1h&start=2024-01-08T00:00:00Z"

# Check storage usage
curl "http://localhost:8080/api/storage/stats"
```

## Development Setup

### Local Development Without Docker

1. **Start PostgreSQL + TimescaleDB**:
```bash
# Using Docker for database only
docker run -d \
  --name timescaledb-dev \
  -p 5432:5432 \
  -e POSTGRES_DB=ruuvi_home \
  -e POSTGRES_USER=ruuvi \
  -e POSTGRES_PASSWORD=ruuvi_secret \
  timescale/timescaledb:latest-pg15
```

2. **Run Database Migrations**:
```bash
# Apply schema from initialization script
psql -h localhost -U ruuvi -d ruuvi_home -f docker/timescaledb/init-timescaledb.sql
```

3. **Set Environment Variables**:
```bash
export DATABASE_URL=postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home
export RUST_LOG=info
```

4. **Build and Run Services**:
```bash
# Build all packages
cd backend && cargo build

# Run API server
cd backend/packages/api && cargo run

# Run MQTT reader (in separate terminal)
cd backend/packages/mqtt-reader && cargo run
```

### Working with sqlx

For compile-time query checking:

1. **Prepare queries** (run once after schema changes):
```bash
cd backend/packages/postgres-store
export DATABASE_URL=postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home
cargo sqlx prepare
```

2. **Check queries** during development:
```bash
cargo sqlx check
```

## Data Migration

### From InfluxDB to PostgreSQL

If you have existing InfluxDB data:

1. **Export InfluxDB data**:
```bash
# Export to CSV format
influx query -f csv "from(bucket:\"ruuvi_metrics\") |> range(start: -30d)" > export.csv
```

2. **Convert and import**:
```sql
-- Create temporary table
CREATE TEMP TABLE import_data (
    sensor_mac VARCHAR(17),
    gateway_mac VARCHAR(17),
    temperature DOUBLE PRECISION,
    humidity DOUBLE PRECISION,
    pressure DOUBLE PRECISION,
    battery BIGINT,
    tx_power BIGINT,
    movement_counter BIGINT,
    measurement_sequence_number BIGINT,
    acceleration DOUBLE PRECISION,
    acceleration_x BIGINT,
    acceleration_y BIGINT,
    acceleration_z BIGINT,
    rssi BIGINT,
    timestamp TIMESTAMPTZ
);

-- Import CSV data
\COPY import_data FROM 'export.csv' CSV HEADER;

-- Insert into hypertable
INSERT INTO sensor_data SELECT * FROM import_data;
```

## Performance Optimization

### Query Performance

1. **Use appropriate time ranges**:
   - Raw data queries: < 24 hours
   - Hourly aggregates: 1-30 days
   - Daily aggregates: > 30 days

2. **Leverage indexes**:
   - Queries are optimized for `(sensor_mac, timestamp)` patterns
   - Include sensor_mac in WHERE clauses when possible

3. **Monitor query performance**:
```sql
-- Check slow queries
SELECT query, mean_exec_time, calls 
FROM pg_stat_statements 
WHERE query LIKE '%sensor_data%' 
ORDER BY mean_exec_time DESC;
```

### Storage Optimization

1. **Monitor compression**:
```sql
SELECT * FROM storage_monitoring;
```

2. **Adjust retention policies** if needed:
```sql
-- Update retention period
SELECT remove_retention_policy('sensor_data');
SELECT add_retention_policy('sensor_data', INTERVAL '3 years');
```

3. **Manual compression** for immediate space savings:
```sql
-- Compress specific time range
SELECT compress_chunk(chunk) 
FROM timescaledb_information.chunks 
WHERE hypertable_name = 'sensor_data' 
  AND range_start < NOW() - INTERVAL '7 days';
```

## Troubleshooting

### Common Issues

**1. Database Connection Errors**
```
Error: failed to connect to database
```
Solution: Check if TimescaleDB is running and DATABASE_URL is correct.

**2. sqlx Compile Errors**
```
Error: set `DATABASE_URL` to use query macros online
```
Solution: Either set DATABASE_URL or run `cargo sqlx prepare` for offline mode.

**3. Migration Script Fails**
```
Error: relation "sensor_data" already exists
```
Solution: The init script is idempotent, but you may need to drop and recreate the database.

**4. High Memory Usage**
```
TimescaleDB using too much memory
```
Solution: Adjust PostgreSQL settings in docker-compose.yaml:
```yaml
command: ["postgres", "-c", "shared_preload_libraries=timescaledb", "-c", "shared_buffers=256MB"]
```

### Debug Commands

**Check service logs**:
```bash
docker-compose logs -f timescaledb
docker-compose logs -f api-server
docker-compose logs -f mqtt-reader
```

**Connect to database**:
```bash
docker-compose exec timescaledb psql -U ruuvi -d ruuvi_home
```

**Test MQTT connection**:
```bash
# Subscribe to messages
mosquitto_sub -h localhost -t "ruuvi/gateway/data"

# Publish test message
mosquitto_pub -h localhost -t "ruuvi/gateway/data" -m '{"gw_mac":"AA:BB:CC:DD:EE:FF","ts":1640995200,"data":"0201060303aafe1516aafe10f9035e5f7f0c0004ffdc040c0357512d80fb"}'
```

**Monitor storage usage**:
```sql
-- Current storage stats
SELECT * FROM get_storage_stats();

-- Estimate future requirements
SELECT * FROM estimate_storage_requirements(10, 10, 5);

-- Check chunk information
SELECT * FROM timescaledb_information.chunks 
WHERE hypertable_name = 'sensor_data' 
ORDER BY range_start DESC;
```

### Performance Monitoring

**Database performance**:
```sql
-- Active queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';

-- Table statistics
SELECT * FROM pg_stat_user_tables WHERE relname = 'sensor_data';

-- Index usage
SELECT * FROM pg_stat_user_indexes WHERE relname = 'sensor_data';
```

## Production Deployment

### Security Considerations

1. **Change default passwords**:
```env
POSTGRES_PASSWORD=your_strong_password_here
```

2. **Enable SSL** for database connections:
```env
DATABASE_URL=postgresql://ruuvi:password@localhost:5432/ruuvi_home?sslmode=require
```

3. **Restrict CORS origins**:
```env
CORS_ALLOWED_ORIGINS=https://yourdomain.com
```

4. **Set appropriate log levels**:
```env
RUST_LOG=warn
```

### Backup Strategy

1. **Automated backups**:
```bash
# Create backup script
cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
docker-compose exec -T timescaledb pg_dump -U ruuvi ruuvi_home | gzip > "$BACKUP_DIR/ruuvi_home_$DATE.sql.gz"
# Keep only last 30 days
find $BACKUP_DIR -name "ruuvi_home_*.sql.gz" -mtime +30 -delete
EOF

chmod +x backup.sh

# Add to crontab
echo "0 2 * * * /path/to/backup.sh" | crontab -
```

2. **Restore from backup**:
```bash
# Stop services
docker-compose down

# Restore database
gunzip -c backup.sql.gz | docker-compose exec -T timescaledb psql -U ruuvi ruuvi_home

# Restart services
docker-compose up -d
```

### Monitoring Setup

1. **Health checks**:
```bash
# Add to monitoring system
curl -f http://localhost:8080/health || exit 1
```

2. **Storage alerts**:
```sql
-- Alert if compression ratio drops
SELECT 
    CASE 
        WHEN compression_ratio < 5 THEN 'ALERT: Poor compression ratio'
        ELSE 'OK'
    END as status,
    compression_ratio
FROM storage_monitoring;
```

3. **Performance metrics**:
```sql
-- Monitor query performance
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch
FROM pg_stat_user_tables 
WHERE tablename = 'sensor_data';
```

## Summary

The PostgreSQL + TimescaleDB migration provides:

- ✅ **Better Rust support**: Zero unwraps, compile-time query checking
- ✅ **Real-time notifications**: Built-in LISTEN/NOTIFY + broadcast channels
- ✅ **5-year retention**: Efficient storage with 90% compression
- ✅ **Rich analytics**: Time bucketing, continuous aggregates, statistics
- ✅ **Production ready**: ACID compliance, backup/restore, monitoring

The new system maintains API compatibility while providing significant improvements in reliability, performance, and developer experience.