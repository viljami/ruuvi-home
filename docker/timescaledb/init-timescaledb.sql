-- TimescaleDB initialization script for Ruuvi Home
-- This script sets up the complete database schema with TimescaleDB features

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Create sensor_data table for storing Ruuvi sensor readings
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

-- Convert to TimescaleDB hypertable
SELECT create_hypertable('sensor_data', 'timestamp', chunk_time_interval => INTERVAL '1 day');

-- Create indexes optimized for TimescaleDB
CREATE INDEX idx_sensor_data_sensor_mac ON sensor_data(sensor_mac, timestamp DESC);
CREATE INDEX idx_sensor_data_gateway_mac ON sensor_data(gateway_mac, timestamp DESC);
CREATE INDEX idx_sensor_data_active ON sensor_data(sensor_mac, gateway_mac, timestamp DESC);

-- Add check constraints for reasonable sensor values
ALTER TABLE sensor_data ADD CONSTRAINT chk_temperature CHECK (temperature BETWEEN -100 AND 100);
ALTER TABLE sensor_data ADD CONSTRAINT chk_humidity CHECK (humidity BETWEEN 0 AND 100);
ALTER TABLE sensor_data ADD CONSTRAINT chk_pressure CHECK (pressure BETWEEN 300 AND 1300);
ALTER TABLE sensor_data ADD CONSTRAINT chk_battery CHECK (battery BETWEEN 0 AND 4000);

-- Create continuous aggregates for time bucketing
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

-- Add refresh policies for continuous aggregates
SELECT add_continuous_aggregate_policy('sensor_data_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

SELECT add_continuous_aggregate_policy('sensor_data_daily',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day');

-- Tiered compression policy for long-term storage optimization
-- Compress data older than 7 days (saves ~90% space)
SELECT add_compression_policy('sensor_data', INTERVAL '7 days');

-- 5-year retention policy for raw sensor data
-- Storage estimate for 10 sensors @ 10-second intervals:
-- - Raw data: ~30GB over 5 years
-- - With compression: ~3GB over 5 years (very manageable)
SELECT add_retention_policy('sensor_data', INTERVAL '5 years');

-- Keep continuous aggregates longer than raw data for historical analysis
-- Hourly aggregates: keep for 7 years
-- Daily aggregates: keep for 10 years (minimal storage overhead)
SELECT add_retention_policy('sensor_data_hourly', INTERVAL '7 years');
SELECT add_retention_policy('sensor_data_daily', INTERVAL '10 years');

-- Create indexes on continuous aggregates
CREATE INDEX idx_sensor_data_hourly_sensor_bucket ON sensor_data_hourly(sensor_mac, bucket DESC);
CREATE INDEX idx_sensor_data_daily_sensor_bucket ON sensor_data_daily(sensor_mac, bucket DESC);

-- Create a function for time bucket queries with flexible intervals
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

-- Storage monitoring and estimation functions

-- Function to get current storage usage statistics
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
        SELECT SUM(compressed_total_bytes) AS compressed_size
        FROM timescaledb_information.compressed_chunk_stats
        WHERE hypertable_name = 'sensor_data'
    ) compressed_chunk_size;
END;
$$ LANGUAGE plpgsql;

-- Function to estimate storage requirements for different scenarios
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
    bytes_per_reading INTEGER := 200; -- Estimated bytes per sensor reading
    compression_ratio NUMERIC := 10.0; -- TimescaleDB typically achieves 10:1 compression
BEGIN
    -- Calculate readings per sensor per year
    readings_per_sensor_per_year := (365 * 24 * 3600) / reading_interval_seconds;
    total_readings_count := readings_per_sensor_per_year * sensor_count * retention_years;

    RETURN QUERY
    SELECT
        FORMAT('%s sensors, %s sec intervals, %s years',
               sensor_count, reading_interval_seconds, retention_years)::TEXT AS scenario,
        total_readings_count AS total_readings,
        ROUND((total_readings_count * bytes_per_reading) / 1024.0 / 1024.0 / 1024.0, 2) AS uncompressed_size_gb,
        ROUND((total_readings_count * bytes_per_reading) / compression_ratio / 1024.0 / 1024.0 / 1024.0, 2) AS compressed_size_gb,
        ROUND(
            -- Daily aggregates: one row per sensor per day
            (sensor_count * 365 * retention_years * 150) / 1024.0 / 1024.0, 2
        ) AS daily_aggregates_size_mb,
        ROUND(
            -- Hourly aggregates: 24 rows per sensor per day
            (sensor_count * 365 * 24 * retention_years * 150) / 1024.0 / 1024.0, 2
        ) AS hourly_aggregates_size_mb,
        ROUND(
            ((total_readings_count * bytes_per_reading) / compression_ratio / 1024.0 / 1024.0 / 1024.0) +
            ((sensor_count * 365 * retention_years * 150) / 1024.0 / 1024.0 / 1024.0) +
            ((sensor_count * 365 * 24 * retention_years * 150) / 1024.0 / 1024.0 / 1024.0), 2
        ) AS total_estimated_size_gb;
END;
$$ LANGUAGE plpgsql;

-- Function to monitor database growth rate
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

    -- Get current storage size
    SELECT raw_size_mb INTO current_size_mb
    FROM get_storage_stats()
    LIMIT 1;

    -- Estimate size 30 days ago (this is approximate)
    size_30_days_ago_mb := current_size_mb * 0.9; -- Rough estimate

    RETURN QUERY
    SELECT
        days_back AS period_days,
        COUNT(*) AS readings_added,
        ROUND(COUNT(*)::NUMERIC / days_back, 2) AS readings_per_day,
        ROUND(current_size_mb - size_30_days_ago_mb, 2) AS storage_growth_mb,
        ROUND((current_size_mb - size_30_days_ago_mb) * 365.0 / days_back / 1024.0, 2) AS estimated_yearly_growth_gb
    FROM sensor_data
    WHERE timestamp >= start_time;
END;
$$ LANGUAGE plpgsql;

-- Create a view for easy storage monitoring
CREATE OR REPLACE VIEW storage_monitoring AS
SELECT
    *,
    CASE
        WHEN compressed_size_mb > 0 AND raw_size_mb > 0
        THEN ROUND((raw_size_mb - compressed_size_mb) / raw_size_mb * 100, 1)
        ELSE 0
    END AS compression_savings_percent
FROM get_storage_stats();

-- Grant permissions to the ruuvi user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ruuvi;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ruuvi;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ruuvi;

-- Create a notification trigger for real-time updates
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

CREATE TRIGGER sensor_data_notify
    AFTER INSERT ON sensor_data
    FOR EACH ROW
    EXECUTE FUNCTION notify_sensor_update();
