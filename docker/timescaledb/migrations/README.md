# TimescaleDB Migration System

## Overview

When TimescaleDB finds existing data, it skips initialization scripts, preventing schema updates from being applied. This migration system ensures database schema stays current across updates.

## How It Works

1. **Migration Tracking**: Uses `schema_migrations` table to track applied migrations
2. **Version-Based**: Each migration has a unique version number (timestamp format)
3. **Idempotent**: Migrations can be run multiple times safely
4. **Automatic**: Runs on container startup via `migrate.sh`

## Migration Files

### Naming Convention
```
YYYYMMDDHHMMSS_description.sql
```

Examples:
- `20231201120000_add_sensor_calibration.sql`
- `20231215140000_create_user_management.sql`
- `20240101000000_add_sensor_location.sql`

### Migration Template
```sql
-- Migration: 20231201120000_add_sensor_calibration.sql
-- Description: Add calibration offset fields to sensor_data table

BEGIN;

-- Check if migration already applied
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM schema_migrations
        WHERE version = '20231201120000'
    ) THEN

        -- Your migration code here
        ALTER TABLE sensor_data
        ADD COLUMN temperature_offset DOUBLE PRECISION DEFAULT 0.0,
        ADD COLUMN humidity_offset DOUBLE PRECISION DEFAULT 0.0,
        ADD COLUMN pressure_offset DOUBLE PRECISION DEFAULT 0.0;

        -- Create indexes if needed
        CREATE INDEX IF NOT EXISTS idx_sensor_calibration
        ON sensor_data(sensor_mac)
        WHERE temperature_offset != 0 OR humidity_offset != 0 OR pressure_offset != 0;

        -- Record migration
        INSERT INTO schema_migrations (version, description, applied_at)
        VALUES ('20231201120000', 'Add calibration offset fields', NOW());

        RAISE NOTICE 'Migration 20231201120000 applied successfully';

    ELSE
        RAISE NOTICE 'Migration 20231201120000 already applied, skipping';
    END IF;
END $$;

COMMIT;
```

## Usage

### Automatic Migration (Recommended)
Migrations run automatically when containers start:

```bash
# Migrations run automatically on startup
docker compose up -d

# Check migration status
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -c "SELECT * FROM schema_migrations ORDER BY applied_at;"
```

### Manual Migration
```bash
# Run all pending migrations
docker exec ruuvi-timescaledb /migrations/migrate.sh

# Run specific migration
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -f /migrations/20231201120000_add_sensor_calibration.sql

# Check what migrations are available
docker exec ruuvi-timescaledb ls -la /migrations/
```

### Development Migration
```bash
# During development, test migration before committing
docker exec -it ruuvi-timescaledb psql -U ruuvi -d ruuvi_home

# In psql:
\i /migrations/20231201120000_add_sensor_calibration.sql
SELECT * FROM schema_migrations;
```

## Creating New Migrations

### 1. Generate Migration File
```bash
# Create new migration with current timestamp
MIGRATION_VERSION=$(date +%Y%m%d%H%M%S)
MIGRATION_NAME="add_sensor_alerts"
cat > docker/timescaledb/migrations/${MIGRATION_VERSION}_${MIGRATION_NAME}.sql << 'EOF'
-- Migration: [VERSION]_[DESCRIPTION].sql
-- Description: Add sensor alert system

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM schema_migrations
        WHERE version = '[VERSION]'
    ) THEN

        -- Create alerts table
        CREATE TABLE IF NOT EXISTS sensor_alerts (
            id SERIAL PRIMARY KEY,
            sensor_mac VARCHAR(17) NOT NULL,
            alert_type VARCHAR(50) NOT NULL,
            threshold_value DOUBLE PRECISION,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            enabled BOOLEAN DEFAULT true
        );

        -- Add indexes
        CREATE INDEX idx_sensor_alerts_sensor ON sensor_alerts(sensor_mac);
        CREATE INDEX idx_sensor_alerts_enabled ON sensor_alerts(enabled) WHERE enabled = true;

        -- Record migration
        INSERT INTO schema_migrations (version, description, applied_at)
        VALUES ('[VERSION]', 'Add sensor alert system', NOW());

        RAISE NOTICE 'Migration [VERSION] applied successfully';

    ELSE
        RAISE NOTICE 'Migration [VERSION] already applied, skipping';
    END IF;
END $$;

COMMIT;
EOF

# Replace placeholders
sed -i "s/\[VERSION\]/${MIGRATION_VERSION}/g" docker/timescaledb/migrations/${MIGRATION_VERSION}_${MIGRATION_NAME}.sql
```

### 2. Test Migration
```bash
# Test on development database
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -f /migrations/${MIGRATION_VERSION}_${MIGRATION_NAME}.sql

# Verify migration was recorded
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -c "SELECT * FROM schema_migrations WHERE version = '${MIGRATION_VERSION}';"
```

### 3. Commit Migration
```bash
git add docker/timescaledb/migrations/${MIGRATION_VERSION}_${MIGRATION_NAME}.sql
git commit -m "Add migration: ${MIGRATION_NAME}"
```

## Rollback Procedures

### Creating Rollback Migrations
```sql
-- Migration: 20231201120001_rollback_sensor_calibration.sql
-- Description: Remove calibration offset fields

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM schema_migrations
        WHERE version = '20231201120001'
    ) THEN

        -- Drop columns (careful with data loss!)
        ALTER TABLE sensor_data
        DROP COLUMN IF EXISTS temperature_offset,
        DROP COLUMN IF EXISTS humidity_offset,
        DROP COLUMN IF EXISTS pressure_offset;

        -- Drop indexes
        DROP INDEX IF EXISTS idx_sensor_calibration;

        -- Record rollback migration
        INSERT INTO schema_migrations (version, description, applied_at)
        VALUES ('20231201120001', 'Rollback: Remove calibration offset fields', NOW());

        RAISE NOTICE 'Rollback migration 20231201120001 applied successfully';

    ELSE
        RAISE NOTICE 'Rollback migration 20231201120001 already applied, skipping';
    END IF;
END $$;

COMMIT;
```

## Migration Best Practices

### 1. Safe Operations
```sql
-- ✅ Safe: Add columns with defaults
ALTER TABLE sensor_data ADD COLUMN new_field TEXT DEFAULT 'default_value';

-- ✅ Safe: Create new indexes
CREATE INDEX CONCURRENTLY idx_new_field ON sensor_data(new_field);

-- ✅ Safe: Create new tables
CREATE TABLE new_feature (...);

-- ⚠️ Careful: Dropping columns (data loss)
ALTER TABLE sensor_data DROP COLUMN old_field;

-- ⚠️ Careful: Changing column types
ALTER TABLE sensor_data ALTER COLUMN some_field TYPE NEW_TYPE;
```

### 2. Large Table Migrations
```sql
-- For large tables, use CONCURRENTLY for indexes
CREATE INDEX CONCURRENTLY idx_large_table ON sensor_data(timestamp, sensor_mac);

-- For data updates, use batches
DO $$
DECLARE
    batch_size INTEGER := 10000;
    rows_updated INTEGER;
BEGIN
    LOOP
        UPDATE sensor_data
        SET new_field = calculated_value
        WHERE new_field IS NULL
        AND ctid IN (
            SELECT ctid FROM sensor_data
            WHERE new_field IS NULL
            LIMIT batch_size
        );

        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        EXIT WHEN rows_updated = 0;

        RAISE NOTICE 'Updated % rows', rows_updated;
        COMMIT;
    END LOOP;
END $$;
```

### 3. Testing Migrations
```bash
# Create test database copy
docker exec ruuvi-timescaledb pg_dump -U ruuvi ruuvi_home > backup.sql
docker exec ruuvi-timescaledb createdb -U ruuvi ruuvi_home_test
docker exec ruuvi-timescaledb psql -U ruuvi ruuvi_home_test < backup.sql

# Test migration on copy
docker exec ruuvi-timescaledb psql -U ruuvi ruuvi_home_test -f /migrations/new_migration.sql

# Cleanup test database
docker exec ruuvi-timescaledb dropdb -U ruuvi ruuvi_home_test
```

## Troubleshooting

### Migration Failed
```bash
# Check migration status
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -c "SELECT * FROM schema_migrations ORDER BY applied_at DESC LIMIT 10;"

# Check PostgreSQL logs
docker logs ruuvi-timescaledb

# Manual rollback (if needed)
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home
# In psql: DELETE FROM schema_migrations WHERE version = 'failed_version';
```

### Missing schema_migrations Table
```bash
# Recreate migration tracking table
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -c "
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(20) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ DEFAULT NOW()
);
"
```

### Check Current Schema Version
```bash
# Show latest applied migration
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -c "
SELECT version, description, applied_at
FROM schema_migrations
ORDER BY version DESC
LIMIT 1;
"
```

## Directory Structure
```
docker/timescaledb/
├── init-timescaledb.sql          # Initial schema (new installations)
├── migrate.sh                    # Migration runner script
└── migrations/
    ├── README.md                 # This file
    ├── 20231201120000_add_sensor_calibration.sql
    ├── 20231215140000_create_user_management.sql
    └── 20240101000000_add_sensor_location.sql
```

## Integration with Setup-Pi

The setup-pi scripts automatically:
1. Mount migrations directory to container
2. Run migrations on container startup
3. Verify migration status during health checks

```yaml
# In docker-compose.yml
timescaledb:
  volumes:
    - ./docker/timescaledb/migrations:/migrations:ro
    - ./docker/timescaledb/migrate.sh:/docker-entrypoint-initdb.d/99-migrate.sh:ro
```

This ensures that whether you're doing a fresh install or updating an existing system, the database schema stays current automatically.
