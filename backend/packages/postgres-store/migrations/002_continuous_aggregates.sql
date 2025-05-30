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
SELECT add_retention_policy('sensor_data', INTERVAL '5 years');

-- Keep continuous aggregates longer than raw data for historical analysis
-- Hourly aggregates: keep for 7 years
-- Daily aggregates: keep for 10 years (minimal storage overhead)
SELECT add_retention_policy('sensor_data_hourly', INTERVAL '7 years');
SELECT add_retention_policy('sensor_data_daily', INTERVAL '10 years');

-- Create indexes on continuous aggregates
CREATE INDEX idx_sensor_data_hourly_sensor_bucket ON sensor_data_hourly(sensor_mac, bucket DESC);
CREATE INDEX idx_sensor_data_daily_sensor_bucket ON sensor_data_daily(sensor_mac, bucket DESC);