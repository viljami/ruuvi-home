#!/bin/bash
set -e

# TimescaleDB tuning script for ARM64/Raspberry Pi environments
# This script replaces the default timescaledb-tune which fails on ARM64 due to cgroup issues

echo "=== ARM64-compatible TimescaleDB tuning ==="

# Get the PostgreSQL configuration file path
PG_CONF="${PGDATA}/postgresql.conf"

# Only proceed if the config file exists
if [ ! -f "$PG_CONF" ]; then
    echo "PostgreSQL config file not found at $PG_CONF, skipping tuning"
    exit 0
fi

echo "Using postgresql.conf at: $PG_CONF"

# Create backup
BACKUP_FILE="/tmp/timescaledb_tune.backup$(date +%Y%m%d%H%M)"
echo "Writing backup to: $BACKUP_FILE"
cp "$PG_CONF" "$BACKUP_FILE"

# ARM64/Pi-optimized settings for TimescaleDB
cat >> "$PG_CONF" << 'EOF'

# TimescaleDB ARM64/Raspberry Pi optimized settings
# Applied by custom tuning script to avoid cgroup issues

# Memory settings (conservative for Pi)
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 4MB
maintenance_work_mem = 64MB

# Checkpoint settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100

# Connection settings
max_connections = 100

# TimescaleDB specific settings
timescaledb.max_background_workers = 2
max_worker_processes = 4
max_parallel_workers_per_gather = 1
max_parallel_workers = 2

# Performance optimizations for ARM64
random_page_cost = 1.1
effective_io_concurrency = 200

# Logging (reduce for Pi storage)
log_statement = 'none'
log_min_duration_statement = 1000

# Autovacuum tuning for TimescaleDB
autovacuum_max_workers = 2
autovacuum_naptime = 30s

EOF

echo "TimescaleDB ARM64 tuning completed successfully"
echo "Configuration applied to: $PG_CONF"
