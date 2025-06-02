-- Migration: 20241202090000_add_sensor_metadata.sql
-- Description: Add sensor metadata table for location, naming, and calibration data

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM schema_migrations
        WHERE version = '20241202090000'
    ) THEN

        -- Create sensor_metadata table (extends existing sensor_data)
        CREATE TABLE IF NOT EXISTS sensor_metadata (
            sensor_mac VARCHAR(17) PRIMARY KEY,
            name VARCHAR(100),
            location VARCHAR(100),
            description TEXT,
            room VARCHAR(50),
            building VARCHAR(50),
            floor INTEGER,
            latitude DOUBLE PRECISION,
            longitude DOUBLE PRECISION,
            altitude DOUBLE PRECISION,
            temperature_offset DOUBLE PRECISION DEFAULT 0.0,
            humidity_offset DOUBLE PRECISION DEFAULT 0.0,
            pressure_offset DOUBLE PRECISION DEFAULT 0.0,
            calibration_date TIMESTAMPTZ,
            installation_date TIMESTAMPTZ DEFAULT NOW(),
            last_maintenance TIMESTAMPTZ,
            is_active BOOLEAN DEFAULT true,
            notes TEXT,
            tags TEXT[],
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW()
        );

        -- Create indexes for common queries
        CREATE INDEX idx_sensor_metadata_location ON sensor_metadata(location, room) WHERE is_active = true;
        CREATE INDEX idx_sensor_metadata_building_floor ON sensor_metadata(building, floor) WHERE is_active = true;
        CREATE INDEX idx_sensor_metadata_active ON sensor_metadata(is_active) WHERE is_active = true;
        CREATE INDEX idx_sensor_metadata_calibration ON sensor_metadata(calibration_date) WHERE temperature_offset != 0 OR humidity_offset != 0 OR pressure_offset != 0;
        CREATE INDEX idx_sensor_metadata_tags ON sensor_metadata USING GIN(tags);
        CREATE INDEX idx_sensor_metadata_coordinates ON sensor_metadata(latitude, longitude) WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

        -- Add check constraints for reasonable values
        ALTER TABLE sensor_metadata ADD CONSTRAINT chk_latitude CHECK (latitude BETWEEN -90 AND 90);
        ALTER TABLE sensor_metadata ADD CONSTRAINT chk_longitude CHECK (longitude BETWEEN -180 AND 180);
        ALTER TABLE sensor_metadata ADD CONSTRAINT chk_temperature_offset CHECK (temperature_offset BETWEEN -50 AND 50);
        ALTER TABLE sensor_metadata ADD CONSTRAINT chk_humidity_offset CHECK (humidity_offset BETWEEN -100 AND 100);
        ALTER TABLE sensor_metadata ADD CONSTRAINT chk_pressure_offset CHECK (pressure_offset BETWEEN -500 AND 500);

        -- Create function to update updated_at timestamp
        CREATE OR REPLACE FUNCTION update_sensor_metadata_updated_at()
        RETURNS TRIGGER AS $func$
        BEGIN
            NEW.updated_at = NOW();
            RETURN NEW;
        END;
        $func$ LANGUAGE plpgsql;

        -- Create trigger for automatic updated_at timestamp
        CREATE TRIGGER trigger_sensor_metadata_updated_at
            BEFORE UPDATE ON sensor_metadata
            FOR EACH ROW
            EXECUTE FUNCTION update_sensor_metadata_updated_at();

        -- Create enhanced view combining sensor data with metadata
        CREATE OR REPLACE VIEW sensor_data_with_metadata AS
        SELECT
            sd.*,
            sm.name,
            sm.location,
            sm.room,
            sm.building,
            sm.floor,
            sm.description,
            sm.latitude,
            sm.longitude,
            sm.altitude,
            CASE
                WHEN sm.temperature_offset IS NOT NULL THEN sd.temperature + sm.temperature_offset
                ELSE sd.temperature
            END as corrected_temperature,
            CASE
                WHEN sm.humidity_offset IS NOT NULL THEN sd.humidity + sm.humidity_offset
                ELSE sd.humidity
            END as corrected_humidity,
            CASE
                WHEN sm.pressure_offset IS NOT NULL THEN sd.pressure + sm.pressure_offset
                ELSE sd.pressure
            END as corrected_pressure,
            sm.tags,
            sm.is_active
        FROM sensor_data sd
        LEFT JOIN sensor_metadata sm ON sd.sensor_mac = sm.sensor_mac;

        -- Create function to get sensor summary with metadata
        CREATE OR REPLACE FUNCTION get_sensor_summary()
        RETURNS TABLE(
            sensor_mac VARCHAR(17),
            name VARCHAR(100),
            location VARCHAR(100),
            latest_reading TIMESTAMPTZ,
            readings_today BIGINT,
            avg_temperature_today DOUBLE PRECISION,
            avg_humidity_today DOUBLE PRECISION,
            avg_pressure_today DOUBLE PRECISION,
            is_online BOOLEAN,
            days_since_maintenance INTEGER
        ) AS $func$
        BEGIN
            RETURN QUERY
            SELECT
                sm.sensor_mac,
                sm.name,
                sm.location,
                MAX(sd.timestamp) as latest_reading,
                COUNT(CASE WHEN sd.timestamp >= CURRENT_DATE THEN 1 END) as readings_today,
                AVG(CASE WHEN sd.timestamp >= CURRENT_DATE THEN sd.temperature END) as avg_temperature_today,
                AVG(CASE WHEN sd.timestamp >= CURRENT_DATE THEN sd.humidity END) as avg_humidity_today,
                AVG(CASE WHEN sd.timestamp >= CURRENT_DATE THEN sd.pressure END) as avg_pressure_today,
                (MAX(sd.timestamp) > NOW() - INTERVAL '10 minutes') as is_online,
                CASE
                    WHEN sm.last_maintenance IS NOT NULL
                    THEN EXTRACT(DAYS FROM NOW() - sm.last_maintenance)::INTEGER
                    ELSE NULL
                END as days_since_maintenance
            FROM sensor_metadata sm
            LEFT JOIN sensor_data sd ON sm.sensor_mac = sd.sensor_mac
            WHERE sm.is_active = true
            GROUP BY sm.sensor_mac, sm.name, sm.location, sm.last_maintenance
            ORDER BY sm.name, sm.location;
        END;
        $func$ LANGUAGE plpgsql;

        -- Create function to get sensors by location
        CREATE OR REPLACE FUNCTION get_sensors_by_location(p_location TEXT DEFAULT NULL, p_building TEXT DEFAULT NULL, p_room TEXT DEFAULT NULL)
        RETURNS TABLE(
            sensor_mac VARCHAR(17),
            name VARCHAR(100),
            location VARCHAR(100),
            room VARCHAR(50),
            building VARCHAR(50),
            floor INTEGER,
            is_online BOOLEAN,
            latest_temperature DOUBLE PRECISION,
            latest_humidity DOUBLE PRECISION,
            latest_pressure DOUBLE PRECISION,
            latest_reading TIMESTAMPTZ
        ) AS $func$
        BEGIN
            RETURN QUERY
            SELECT
                sm.sensor_mac,
                sm.name,
                sm.location,
                sm.room,
                sm.building,
                sm.floor,
                (latest_data.timestamp > NOW() - INTERVAL '10 minutes') as is_online,
                latest_data.temperature as latest_temperature,
                latest_data.humidity as latest_humidity,
                latest_data.pressure as latest_pressure,
                latest_data.timestamp as latest_reading
            FROM sensor_metadata sm
            LEFT JOIN LATERAL (
                SELECT temperature, humidity, pressure, timestamp
                FROM sensor_data sd
                WHERE sd.sensor_mac = sm.sensor_mac
                ORDER BY timestamp DESC
                LIMIT 1
            ) latest_data ON true
            WHERE sm.is_active = true
            AND (p_location IS NULL OR sm.location ILIKE '%' || p_location || '%')
            AND (p_building IS NULL OR sm.building ILIKE '%' || p_building || '%')
            AND (p_room IS NULL OR sm.room ILIKE '%' || p_room || '%')
            ORDER BY sm.building, sm.floor, sm.room, sm.name;
        END;
        $func$ LANGUAGE plpgsql;

        -- Grant permissions
        GRANT ALL PRIVILEGES ON sensor_metadata TO ruuvi;
        GRANT SELECT ON sensor_data_with_metadata TO ruuvi;
        GRANT EXECUTE ON FUNCTION get_sensor_summary() TO ruuvi;
        GRANT EXECUTE ON FUNCTION get_sensors_by_location(TEXT, TEXT, TEXT) TO ruuvi;
        GRANT EXECUTE ON FUNCTION update_sensor_metadata_updated_at() TO ruuvi;

        -- Record migration
        INSERT INTO schema_migrations (version, description, applied_at)
        VALUES ('20241202090000', 'Add sensor metadata table for location, naming, and calibration', NOW());

        RAISE NOTICE 'Migration 20241202090000 applied successfully';

    ELSE
        RAISE NOTICE 'Migration 20241202090000 already applied, skipping';
    END IF;
END $$;

COMMIT;
