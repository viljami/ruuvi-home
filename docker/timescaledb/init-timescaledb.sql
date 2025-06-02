-- TimescaleDB initialization script for Ruuvi Home
-- This script consolidates backend migrations and sets up the migration tracking system
-- Compatible with both development (backend sqlx) and production (Docker) environments

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Create schema migrations tracking table first
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(20) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_schema_migrations_applied_at ON schema_migrations(applied_at);

-- Initialize migration tracking (equivalent to backend migrations)
INSERT INTO schema_migrations (version, description, applied_at)
SELECT '001_initial', 'Initial schema from backend postgres-store migration', NOW()
WHERE NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '001_initial');

INSERT INTO schema_migrations (version, description, applied_at)
SELECT '002_continuous_aggregates', 'Continuous aggregates from backend postgres-store migration', NOW()
WHERE NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '002_continuous_aggregates');

-- Core sensor_data table (from backend/packages/postgres-store/migrations/001_initial.sql)
CREATE TABLE IF NOT EXISTS sensor_data (
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

-- Convert to TimescaleDB hypertable (idempotent)
SELECT create_hypertable('sensor_data', 'timestamp', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);

-- Create indexes optimized for TimescaleDB
CREATE INDEX IF NOT EXISTS idx_sensor_data_sensor_mac ON sensor_data(sensor_mac, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_data_gateway_mac ON sensor_data(gateway_mac, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_data_active ON sensor_data(sensor_mac, gateway_mac, timestamp DESC);

-- Add check constraints for reasonable sensor values
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_temperature') THEN
        ALTER TABLE sensor_data ADD CONSTRAINT chk_temperature CHECK (temperature BETWEEN -100 AND 100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_humidity') THEN
        ALTER TABLE sensor_data ADD CONSTRAINT chk_humidity CHECK (humidity BETWEEN 0 AND 100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_pressure') THEN
        ALTER TABLE sensor_data ADD CONSTRAINT chk_pressure CHECK (pressure BETWEEN 300 AND 1300);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_battery') THEN
        ALTER TABLE sensor_data ADD CONSTRAINT chk_battery CHECK (battery BETWEEN 0 AND 4000);
    END IF;
END $$;

-- Core functions (from backend postgres-store migration)
CREATE OR REPLACE FUNCTION get_sensor_data_bucketed(
    p_sensor_mac TEXT,
    p_interval INTERVAL,
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ
)
RETURNS TABLE(
    bucket TIMESTAMPTZ,
    avg_temperature DOUBLE PRECISION,
    min_temperature DOUBLE PRECISION,
    max_temperature DOUBLE PRECISION,
    avg_humidity DOUBLE PRECISION,
    min_humidity DOUBLE PRECISION,
    max_humidity DOUBLE PRECISION,
    avg_pressure DOUBLE PRECISION,
    min_pressure DOUBLE PRECISION,
    max_pressure DOUBLE PRECISION,
    reading_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        time_bucket(p_interval, timestamp) AS bucket,
        AVG(temperature) AS avg_temperature,
        MIN(temperature) AS min_temperature,
        MAX(temperature) AS max_temperature,
        AVG(humidity) AS avg_humidity,
        MIN(humidity) AS min_humidity,
        MAX(humidity) AS max_humidity,
        AVG(pressure) AS avg_pressure,
        MIN(pressure) AS min_pressure,
        MAX(pressure) AS max_pressure,
        COUNT(*) AS reading_count
    FROM sensor_data
    WHERE sensor_mac = p_sensor_mac
      AND timestamp >= p_start_time
      AND timestamp <= p_end_time
    GROUP BY bucket
    ORDER BY bucket;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_storage_stats()
RETURNS TABLE(
    table_name TEXT,
    raw_size_mb NUMERIC,
    compressed_size_mb NUMERIC,
    compression_ratio NUMERIC,
    row_count BIGINT,
    oldest_data TIMESTAMPTZ,
    newest_data TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'sensor_data'::TEXT,
        ROUND(pg_total_relation_size('sensor_data') / 1024.0 / 1024.0, 2) AS raw_size_mb,
        ROUND(
            CASE
                WHEN compressed_chunk_size.compressed_size IS NOT NULL
                THEN compressed_chunk_size.compressed_size / 1024.0 / 1024.0
                ELSE pg_total_relation_size('sensor_data') / 1024.0 / 1024.0
            END, 2
        ) AS compressed_size_mb,
        ROUND(
            CASE
                WHEN compressed_chunk_size.compressed_size IS NOT NULL
                THEN pg_total_relation_size('sensor_data')::NUMERIC / compressed_chunk_size.compressed_size
                ELSE 1.0
            END, 2
        ) AS compression_ratio,
        (SELECT COUNT(*) FROM sensor_data) AS row_count,
        (SELECT MIN(timestamp) FROM sensor_data) AS oldest_data,
        (SELECT MAX(timestamp) FROM sensor_data) AS newest_data
    FROM (
        SELECT COALESCE(SUM(compressed_total_bytes), 0) AS compressed_size
        FROM timescaledb_information.compressed_chunk_stats
        WHERE hypertable_name = 'sensor_data'
    ) compressed_chunk_size;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION estimate_storage_requirements(
    sensor_count INTEGER DEFAULT 10,
    reading_interval_seconds INTEGER DEFAULT 10,
    retention_years INTEGER DEFAULT 5
)
RETURNS TABLE(
    scenario TEXT,
    total_readings BIGINT,
    uncompressed_size_gb NUMERIC,
    compressed_size_gb NUMERIC,
    daily_aggregates_size_mb NUMERIC,
    hourly_aggregates_size_mb NUMERIC,
    total_estimated_size_gb NUMERIC
) AS $$
DECLARE
    readings_per_sensor_per_year BIGINT;
    total_readings_count BIGINT;
    bytes_per_reading INTEGER := 200;
    compression_ratio NUMERIC := 10.0;
BEGIN
    readings_per_sensor_per_year := (365 * 24 * 3600) / reading_interval_seconds;
    total_readings_count := readings_per_sensor_per_year * sensor_count * retention_years;

    RETURN QUERY
    SELECT
        FORMAT('%s sensors, %s sec intervals, %s years',
               sensor_count, reading_interval_seconds, retention_years)::TEXT AS scenario,
        total_readings_count AS total_readings,
        ROUND((total_readings_count * bytes_per_reading) / 1024.0 / 1024.0 / 1024.0, 2) AS uncompressed_size_gb,
        ROUND((total_readings_count * bytes_per_reading) / compression_ratio / 1024.0 / 1024.0 / 1024.0, 2) AS compressed_size_gb,
        ROUND((sensor_count * 365 * retention_years * 150) / 1024.0 / 1024.0, 2) AS daily_aggregates_size_mb,
        ROUND((sensor_count * 365 * 24 * retention_years * 150) / 1024.0 / 1024.0, 2) AS hourly_aggregates_size_mb,
        ROUND(
            ((total_readings_count * bytes_per_reading) / compression_ratio / 1024.0 / 1024.0 / 1024.0) +
            ((sensor_count * 365 * retention_years * 150) / 1024.0 / 1024.0 / 1024.0) +
            ((sensor_count * 365 * 24 * retention_years * 150) / 1024.0 / 1024.0 / 1024.0), 2
        ) AS total_estimated_size_gb;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_growth_statistics(days_back INTEGER DEFAULT 30)
RETURNS TABLE(
    period_days INTEGER,
    readings_added BIGINT,
    readings_per_day NUMERIC,
    storage_growth_mb NUMERIC,
    estimated_yearly_growth_gb NUMERIC
) AS $$
DECLARE
    start_time TIMESTAMPTZ;
    current_size_mb NUMERIC;
    size_30_days_ago_mb NUMERIC;
BEGIN
    start_time := NOW() - (days_back || ' days')::INTERVAL;

    SELECT raw_size_mb INTO current_size_mb
    FROM get_storage_stats()
    LIMIT 1;

    size_30_days_ago_mb := COALESCE(current_size_mb * 0.9, 0);

    RETURN QUERY
    SELECT
        days_back AS period_days,
        COUNT(*) AS readings_added,
        ROUND(COUNT(*)::NUMERIC / GREATEST(days_back, 1), 2) AS readings_per_day,
        ROUND(current_size_mb - size_30_days_ago_mb, 2) AS storage_growth_mb,
        ROUND((current_size_mb - size_30_days_ago_mb) * 365.0 / GREATEST(days_back, 1) / 1024.0, 2) AS estimated_yearly_growth_gb
    FROM sensor_data
    WHERE timestamp >= start_time;
END;
$$ LANGUAGE plpgsql;

-- Storage monitoring view
CREATE OR REPLACE VIEW storage_monitoring AS
SELECT
    *,
    CASE
        WHEN compressed_size_mb > 0 AND raw_size_mb > 0
        THEN ROUND((raw_size_mb - compressed_size_mb) / raw_size_mb * 100, 1)
        ELSE 0
    END AS compression_savings_percent
FROM get_storage_stats();

-- Continuous aggregates (from backend/packages/postgres-store/migrations/002_continuous_aggregates.sql)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM timescaledb_information.continuous_aggregates WHERE view_name = 'sensor_data_hourly') THEN
        CREATE MATERIALIZED VIEW sensor_data_hourly
        WITH (timescaledb.continuous) AS
        SELECT
            sensor_mac,
            gateway_mac,
            time_bucket('1 hour', timestamp) AS bucket,
            AVG(temperature) AS avg_temperature,
            MIN(temperature) AS min_temperature,
            MAX(temperature) AS max_temperature,
            AVG(humidity) AS avg_humidity,
            MIN(humidity) AS min_humidity,
            MAX(humidity) AS max_humidity,
            AVG(pressure) AS avg_pressure,
            MIN(pressure) AS min_pressure,
            MAX(pressure) AS max_pressure,
            AVG(battery) AS avg_battery,
            MIN(battery) AS min_battery,
            MAX(battery) AS max_battery,
            COUNT(*) AS reading_count
        FROM sensor_data
        GROUP BY sensor_mac, gateway_mac, bucket;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM timescaledb_information.continuous_aggregates WHERE view_name = 'sensor_data_daily') THEN
        CREATE MATERIALIZED VIEW sensor_data_daily
        WITH (timescaledb.continuous) AS
        SELECT
            sensor_mac,
            gateway_mac,
            time_bucket('1 day', timestamp) AS bucket,
            AVG(temperature) AS avg_temperature,
            MIN(temperature) AS min_temperature,
            MAX(temperature) AS max_temperature,
            AVG(humidity) AS avg_humidity,
            MIN(humidity) AS min_humidity,
            MAX(humidity) AS max_humidity,
            AVG(pressure) AS avg_pressure,
            MIN(pressure) AS min_pressure,
            MAX(pressure) AS max_pressure,
            AVG(battery) AS avg_battery,
            MIN(battery) AS min_battery,
            MAX(battery) AS max_battery,
            COUNT(*) AS reading_count
        FROM sensor_data
        GROUP BY sensor_mac, gateway_mac, bucket;
    END IF;
END $$;

-- Add refresh policies and retention policies (idempotent)
DO $$
BEGIN
    -- Hourly aggregate policies
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_refresh_continuous_aggregate'
        AND config->>'mat_hypertable_id' = (
            SELECT id::text FROM timescaledb_information.continuous_aggregates
            WHERE view_name = 'sensor_data_hourly'
        )
    ) THEN
        PERFORM add_continuous_aggregate_policy('sensor_data_hourly',
            start_offset => INTERVAL '3 hours',
            end_offset => INTERVAL '1 hour',
            schedule_interval => INTERVAL '1 hour');
    END IF;

    -- Daily aggregate policies
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_refresh_continuous_aggregate'
        AND config->>'mat_hypertable_id' = (
            SELECT id::text FROM timescaledb_information.continuous_aggregates
            WHERE view_name = 'sensor_data_daily'
        )
    ) THEN
        PERFORM add_continuous_aggregate_policy('sensor_data_daily',
            start_offset => INTERVAL '3 days',
            end_offset => INTERVAL '1 day',
            schedule_interval => INTERVAL '1 day');
    END IF;

    -- Compression policy
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression'
        AND config->>'hypertable_id' = (
            SELECT id::text FROM timescaledb_information.hypertables
            WHERE table_name = 'sensor_data'
        )
    ) THEN
        PERFORM add_compression_policy('sensor_data', INTERVAL '7 days');
    END IF;

    -- Retention policies
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
        AND config->>'hypertable_id' = (
            SELECT id::text FROM timescaledb_information.hypertables
            WHERE table_name = 'sensor_data'
        )
    ) THEN
        PERFORM add_retention_policy('sensor_data', INTERVAL '5 years');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
        AND config->>'hypertable_id' = (
            SELECT id::text FROM timescaledb_information.continuous_aggregates
            WHERE view_name = 'sensor_data_hourly'
        )
    ) THEN
        PERFORM add_retention_policy('sensor_data_hourly', INTERVAL '7 years');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
        AND config->>'hypertable_id' = (
            SELECT id::text FROM timescaledb_information.continuous_aggregates
            WHERE view_name = 'sensor_data_daily'
        )
    ) THEN
        PERFORM add_retention_policy('sensor_data_daily', INTERVAL '10 years');
    END IF;
END $$;

-- Create indexes on continuous aggregates
CREATE INDEX IF NOT EXISTS idx_sensor_data_hourly_sensor_bucket ON sensor_data_hourly(sensor_mac, bucket DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_data_daily_sensor_bucket ON sensor_data_daily(sensor_mac, bucket DESC);

-- Production-specific enhancements
CREATE OR REPLACE FUNCTION notify_sensor_update()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('sensor_updates',
        json_build_object(
            'sensor_mac', NEW.sensor_mac,
            'timestamp', NEW.timestamp
        )::text
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sensor_data_notify ON sensor_data;
CREATE TRIGGER sensor_data_notify
    AFTER INSERT ON sensor_data
    FOR EACH ROW
    EXECUTE FUNCTION notify_sensor_update();

-- Grant permissions to the ruuvi user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ruuvi;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ruuvi;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ruuvi;
GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_information TO ruuvi;

-- Record that the consolidated migration was applied
INSERT INTO schema_migrations (version, description, applied_at)
SELECT '00000000000001', 'Consolidated Docker initialization with backend compatibility', NOW()
WHERE NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '00000000000001');
