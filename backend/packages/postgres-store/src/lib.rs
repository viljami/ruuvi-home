use anyhow::Result;
use bigdecimal::ToPrimitive;
use chrono::{
    DateTime,
    Utc,
};
use serde::{
    Deserialize,
    Serialize,
};
use sqlx::{
    types::BigDecimal,
    FromRow,
    PgPool,
    Row,
};
use tokio::sync::broadcast;
use tracing::error;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Event {
    pub sensor_mac: String,
    pub gateway_mac: String,
    pub temperature: f64,
    pub humidity: f64,
    pub pressure: f64,
    pub battery: i64,
    pub tx_power: i64,
    pub movement_counter: i64,
    pub measurement_sequence_number: i64,
    pub acceleration: f64,
    pub acceleration_x: i64,
    pub acceleration_y: i64,
    pub acceleration_z: i64,
    pub rssi: i64,
    pub timestamp: DateTime<Utc>,
}

impl Event {
    pub fn new_with_current_time(
        sensor_mac: String,
        gateway_mac: String,
        temperature: f64,
        humidity: f64,
        pressure: f64,
        battery: i64,
        tx_power: i64,
        movement_counter: i64,
        measurement_sequence_number: i64,
        acceleration: f64,
        acceleration_x: i64,
        acceleration_y: i64,
        acceleration_z: i64,
        rssi: i64,
    ) -> Self {
        Self {
            sensor_mac,
            gateway_mac,
            temperature,
            humidity,
            pressure,
            battery,
            tx_power,
            movement_counter,
            measurement_sequence_number,
            acceleration,
            acceleration_x,
            acceleration_y,
            acceleration_z,
            rssi,
            timestamp: Utc::now(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct PostgresStore {
    pub pool: PgPool,
    event_sender: broadcast::Sender<Event>,
}

impl PostgresStore {
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = PgPool::connect(database_url).await?;

        // Run migrations if needed - for now just test connection
        sqlx::query("SELECT 1").execute(&pool).await?;

        let (event_sender, _) = broadcast::channel(1000);

        Ok(Self { pool, event_sender })
    }

    pub async fn insert_event(&self, event: &Event) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO sensor_data (
                sensor_mac, gateway_mac, temperature, humidity, pressure,
                battery, tx_power, movement_counter, measurement_sequence_number,
                acceleration, acceleration_x, acceleration_y, acceleration_z,
                rssi, timestamp
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
            "#,
        )
        .bind(&event.sensor_mac)
        .bind(&event.gateway_mac)
        .bind(event.temperature)
        .bind(event.humidity)
        .bind(event.pressure)
        .bind(event.battery)
        .bind(event.tx_power)
        .bind(event.movement_counter)
        .bind(event.measurement_sequence_number)
        .bind(event.acceleration)
        .bind(event.acceleration_x)
        .bind(event.acceleration_y)
        .bind(event.acceleration_z)
        .bind(event.rssi)
        .bind(event.timestamp)
        .execute(&self.pool)
        .await?;

        // Notify subscribers of new data
        if self.event_sender.receiver_count() > 0 {
            if let Err(e) = self.event_sender.send(event.clone()) {
                error!("Failed to broadcast new event: {}", e);
            }
        }

        Ok(())
    }

    pub async fn get_active_sensors(&self) -> Result<Vec<Event>> {
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT ON (sensor_mac, gateway_mac)
                sensor_mac, gateway_mac, temperature, humidity, pressure,
                battery, tx_power, movement_counter, measurement_sequence_number,
                acceleration, acceleration_x, acceleration_y, acceleration_z,
                rssi, timestamp
            FROM sensor_data
            WHERE timestamp > NOW() - INTERVAL '24 hours'
            ORDER BY sensor_mac, gateway_mac, timestamp DESC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut events = Vec::new();
        for row in rows {
            events.push(Event {
                sensor_mac: row.get("sensor_mac"),
                gateway_mac: row.get("gateway_mac"),
                temperature: row.get("temperature"),
                humidity: row.get("humidity"),
                pressure: row.get("pressure"),
                battery: row.get("battery"),
                tx_power: row.get("tx_power"),
                movement_counter: row.get("movement_counter"),
                measurement_sequence_number: row.get("measurement_sequence_number"),
                acceleration: row.get("acceleration"),
                acceleration_x: row.get("acceleration_x"),
                acceleration_y: row.get("acceleration_y"),
                acceleration_z: row.get("acceleration_z"),
                rssi: row.get("rssi"),
                timestamp: row.get("timestamp"),
            });
        }

        Ok(events)
    }

    pub async fn get_latest_reading(&self, sensor_mac: &str) -> Result<Option<Event>> {
        let row = sqlx::query(
            r#"
            SELECT sensor_mac, gateway_mac, temperature, humidity, pressure,
                   battery, tx_power, movement_counter, measurement_sequence_number,
                   acceleration, acceleration_x, acceleration_y, acceleration_z,
                   rssi, timestamp
            FROM sensor_data
            WHERE sensor_mac = $1
            ORDER BY timestamp DESC
            LIMIT 1
            "#,
        )
        .bind(sensor_mac)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            Ok(Some(Event {
                sensor_mac: row.get("sensor_mac"),
                gateway_mac: row.get("gateway_mac"),
                temperature: row.get("temperature"),
                humidity: row.get("humidity"),
                pressure: row.get("pressure"),
                battery: row.get("battery"),
                tx_power: row.get("tx_power"),
                movement_counter: row.get("movement_counter"),
                measurement_sequence_number: row.get("measurement_sequence_number"),
                acceleration: row.get("acceleration"),
                acceleration_x: row.get("acceleration_x"),
                acceleration_y: row.get("acceleration_y"),
                acceleration_z: row.get("acceleration_z"),
                rssi: row.get("rssi"),
                timestamp: row.get("timestamp"),
            }))
        } else {
            Ok(None)
        }
    }

    pub async fn get_historical_data(
        &self,
        sensor_mac: &str,
        start: Option<DateTime<Utc>>,
        end: Option<DateTime<Utc>>,
        limit: Option<i64>,
    ) -> Result<Vec<Event>> {
        let start = start.unwrap_or_else(|| Utc::now() - chrono::Duration::hours(1));
        let end = end.unwrap_or_else(Utc::now);
        let limit = limit.unwrap_or(100);

        let rows = sqlx::query(
            r#"
            SELECT sensor_mac, gateway_mac, temperature, humidity, pressure,
                   battery, tx_power, movement_counter, measurement_sequence_number,
                   acceleration, acceleration_x, acceleration_y, acceleration_z,
                   rssi, timestamp
            FROM sensor_data
            WHERE sensor_mac = $1
              AND timestamp >= $2
              AND timestamp <= $3
            ORDER BY timestamp DESC
            LIMIT $4
            "#,
        )
        .bind(sensor_mac)
        .bind(start)
        .bind(end)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let mut events = Vec::new();
        for row in rows {
            events.push(Event {
                sensor_mac: row.get("sensor_mac"),
                gateway_mac: row.get("gateway_mac"),
                temperature: row.get("temperature"),
                humidity: row.get("humidity"),
                pressure: row.get("pressure"),
                battery: row.get("battery"),
                tx_power: row.get("tx_power"),
                movement_counter: row.get("movement_counter"),
                measurement_sequence_number: row.get("measurement_sequence_number"),
                acceleration: row.get("acceleration"),
                acceleration_x: row.get("acceleration_x"),
                acceleration_y: row.get("acceleration_y"),
                acceleration_z: row.get("acceleration_z"),
                rssi: row.get("rssi"),
                timestamp: row.get("timestamp"),
            });
        }

        Ok(events)
    }

    pub async fn get_sensor_data_range(
        &self,
        sensor_mac: &str,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<Event>> {
        let rows = sqlx::query(
            r#"
            SELECT sensor_mac, gateway_mac, temperature, humidity, pressure,
                   battery, tx_power, movement_counter, measurement_sequence_number,
                   acceleration, acceleration_x, acceleration_y, acceleration_z,
                   rssi, timestamp
            FROM sensor_data
            WHERE sensor_mac = $1
              AND timestamp >= $2
              AND timestamp <= $3
            ORDER BY timestamp ASC
            "#,
        )
        .bind(sensor_mac)
        .bind(start)
        .bind(end)
        .fetch_all(&self.pool)
        .await?;

        let mut events = Vec::new();
        for row in rows {
            events.push(Event {
                sensor_mac: row.get("sensor_mac"),
                gateway_mac: row.get("gateway_mac"),
                temperature: row.get("temperature"),
                humidity: row.get("humidity"),
                pressure: row.get("pressure"),
                battery: row.get("battery"),
                tx_power: row.get("tx_power"),
                movement_counter: row.get("movement_counter"),
                measurement_sequence_number: row.get("measurement_sequence_number"),
                acceleration: row.get("acceleration"),
                acceleration_x: row.get("acceleration_x"),
                acceleration_y: row.get("acceleration_y"),
                acceleration_z: row.get("acceleration_z"),
                rssi: row.get("rssi"),
                timestamp: row.get("timestamp"),
            });
        }

        Ok(events)
    }

    pub fn subscribe_to_events(&self) -> broadcast::Receiver<Event> {
        self.event_sender.subscribe()
    }

    pub async fn get_sensor_statistics(&self, sensor_mac: &str, hours: i32) -> Result<SensorStats> {
        let row = sqlx::query(
            r#"
            SELECT
                AVG(temperature) as avg_temp,
                MIN(temperature) as min_temp,
                MAX(temperature) as max_temp,
                AVG(humidity) as avg_humidity,
                MIN(humidity) as min_humidity,
                MAX(humidity) as max_humidity,
                AVG(pressure) as avg_pressure,
                MIN(pressure) as min_pressure,
                MAX(pressure) as max_pressure,
                COUNT(*) as reading_count
            FROM sensor_data
            WHERE sensor_mac = $1
              AND timestamp > NOW() - INTERVAL '1 hour' * $2
            "#,
        )
        .bind(sensor_mac)
        .bind(hours)
        .fetch_one(&self.pool)
        .await?;

        Ok(SensorStats {
            avg_temperature: row.get::<Option<f64>, _>("avg_temp").unwrap_or(0.0),
            min_temperature: row.get::<Option<f64>, _>("min_temp").unwrap_or(0.0),
            max_temperature: row.get::<Option<f64>, _>("max_temp").unwrap_or(0.0),
            avg_humidity: row.get::<Option<f64>, _>("avg_humidity").unwrap_or(0.0),
            min_humidity: row.get::<Option<f64>, _>("min_humidity").unwrap_or(0.0),
            max_humidity: row.get::<Option<f64>, _>("max_humidity").unwrap_or(0.0),
            avg_pressure: row.get::<Option<f64>, _>("avg_pressure").unwrap_or(0.0),
            min_pressure: row.get::<Option<f64>, _>("min_pressure").unwrap_or(0.0),
            max_pressure: row.get::<Option<f64>, _>("max_pressure").unwrap_or(0.0),
            reading_count: row.get::<Option<i64>, _>("reading_count").unwrap_or(0),
        })
    }

    pub async fn cleanup_old_data(&self, days_to_keep: i32) -> Result<u64> {
        let result =
            sqlx::query("DELETE FROM sensor_data WHERE timestamp < NOW() - INTERVAL '1 day' * $1")
                .bind(days_to_keep)
                .execute(&self.pool)
                .await?;

        Ok(result.rows_affected())
    }

    pub async fn get_time_bucketed_data(
        &self,
        sensor_mac: &str,
        interval: &TimeInterval,
        start_time: DateTime<Utc>,
        end_time: DateTime<Utc>,
    ) -> Result<Vec<TimeBucketedData>> {
        let interval_str = interval.to_interval_string();

        // For now, implement basic time bucketing without the custom function
        let query = format!(
            r#"
            SELECT
                time_bucket(INTERVAL '{interval_str}', timestamp) AS bucket,
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
            WHERE sensor_mac = $1
              AND timestamp >= $2
              AND timestamp <= $3
            GROUP BY bucket
            ORDER BY bucket
            "#,
        );

        let rows = sqlx::query(&query)
            .bind(sensor_mac)
            .bind(start_time)
            .bind(end_time)
            .fetch_all(&self.pool)
            .await?;

        let mut data = Vec::new();
        for row in rows {
            data.push(TimeBucketedData {
                bucket: row.get("bucket"),
                avg_temperature: row.get("avg_temperature"),
                min_temperature: row.get("min_temperature"),
                max_temperature: row.get("max_temperature"),
                avg_humidity: row.get("avg_humidity"),
                min_humidity: row.get("min_humidity"),
                max_humidity: row.get("max_humidity"),
                avg_pressure: row.get("avg_pressure"),
                min_pressure: row.get("min_pressure"),
                max_pressure: row.get("max_pressure"),
                reading_count: row.get("reading_count"),
            });
        }

        Ok(data)
    }

    pub async fn get_hourly_aggregates(
        &self,
        sensor_mac: &str,
        start_time: DateTime<Utc>,
        end_time: DateTime<Utc>,
    ) -> Result<Vec<TimeBucketedData>> {
        // Fallback to basic query if continuous aggregates don't exist yet
        self.get_time_bucketed_data(sensor_mac, &TimeInterval::Hours(1), start_time, end_time)
            .await
    }

    pub async fn get_daily_aggregates(
        &self,
        sensor_mac: &str,
        start_time: DateTime<Utc>,
        end_time: DateTime<Utc>,
    ) -> Result<Vec<TimeBucketedData>> {
        // Fallback to basic query if continuous aggregates don't exist yet
        self.get_time_bucketed_data(sensor_mac, &TimeInterval::Days(1), start_time, end_time)
            .await
    }

    pub async fn get_recent_aggregates(
        &self,
        sensor_mac: &str,
        interval: &TimeInterval,
        hours_back: i32,
    ) -> Result<Vec<TimeBucketedData>> {
        let end_time = Utc::now();
        let start_time = end_time - chrono::Duration::hours(hours_back as i64);

        self.get_time_bucketed_data(sensor_mac, interval, start_time, end_time)
            .await
    }

    pub async fn get_temperature_trend(
        &self,
        sensor_mac: &str,
        hours_back: i32,
    ) -> Result<Vec<(DateTime<Utc>, f64)>> {
        let start_time = Utc::now() - chrono::Duration::hours(hours_back as i64);

        let rows = sqlx::query(
            r#"
            SELECT
                time_bucket(INTERVAL '15 minutes', timestamp) AS bucket,
                AVG(temperature) AS avg_temp
            FROM sensor_data
            WHERE sensor_mac = $1
              AND timestamp >= $2
            GROUP BY bucket
            ORDER BY bucket
            "#,
        )
        .bind(sensor_mac)
        .bind(start_time)
        .fetch_all(&self.pool)
        .await?;

        let mut data = Vec::new();
        for row in rows {
            if let (Some(bucket), Some(avg_temp)) = (
                row.get::<Option<DateTime<Utc>>, _>("bucket"),
                row.get::<Option<f64>, _>("avg_temp"),
            ) {
                data.push((bucket, avg_temp));
            }
        }

        Ok(data)
    }

    pub async fn get_sensor_health_metrics(
        &self,
        sensor_mac: &str,
        hours_back: i32,
    ) -> Result<SensorHealthMetrics> {
        let start_time = Utc::now() - chrono::Duration::hours(hours_back as i64);

        let row = sqlx::query(
            r#"
            SELECT
                COUNT(*) as total_readings,
                AVG(battery) as avg_battery,
                MIN(battery) as min_battery,
                AVG(rssi) as avg_rssi,
                MIN(rssi) as min_rssi,
                MAX(timestamp) as last_reading
            FROM sensor_data
            WHERE sensor_mac = $1
              AND timestamp >= $2
            "#,
        )
        .bind(sensor_mac)
        .bind(start_time)
        .fetch_one(&self.pool)
        .await?;

        let avg_battery_bd: Option<BigDecimal> = row.get("avg_battery");
        let avg_rssi_bd: Option<BigDecimal> = row.get("avg_rssi");

        Ok(SensorHealthMetrics {
            total_readings: row.get::<Option<i64>, _>("total_readings").unwrap_or(0),
            avg_battery: avg_battery_bd.and_then(|bd| bd.to_f64()).unwrap_or(0.0),
            min_battery: row.get::<Option<i64>, _>("min_battery").unwrap_or(0),
            avg_rssi: avg_rssi_bd.and_then(|bd| bd.to_f64()).unwrap_or(0.0),
            min_rssi: row.get::<Option<i64>, _>("min_rssi").unwrap_or(0),
            last_reading: row.get("last_reading"),
        })
    }

    pub async fn get_storage_stats(&self) -> Result<StorageStats> {
        // Simplified storage stats without custom functions
        let row = sqlx::query(
            r#"
            SELECT
                'sensor_data' as table_name,
                pg_total_relation_size('sensor_data') / 1024.0 / 1024.0 as raw_size_mb,
                pg_total_relation_size('sensor_data') / 1024.0 / 1024.0 as compressed_size_mb,
                1.0 as compression_ratio,
                COUNT(*) as row_count,
                MIN(timestamp) as oldest_data,
                MAX(timestamp) as newest_data
            FROM sensor_data
            "#,
        )
        .fetch_one(&self.pool)
        .await?;

        let raw_size_mb: Option<BigDecimal> = row.get("raw_size_mb");
        let compressed_size_mb: Option<BigDecimal> = row.get("compressed_size_mb");

        let compression_ratio_bd: Option<BigDecimal> = row.get("compression_ratio");

        Ok(StorageStats {
            table_name: row.get("table_name"),
            raw_size_mb: raw_size_mb.and_then(|a| a.to_f64()),
            compressed_size_mb: compressed_size_mb.and_then(|a| a.to_f64()),
            compression_ratio: compression_ratio_bd.and_then(|bd| bd.to_f64()),
            row_count: row.get("row_count"),
            oldest_data: row.get("oldest_data"),
            newest_data: row.get("newest_data"),
        })
    }

    pub async fn estimate_storage_requirements(
        &self,
        sensor_count: i32,
        reading_interval_seconds: i32,
        retention_years: i32,
    ) -> Result<StorageEstimate> {
        // Simple calculation
        let readings_per_sensor_per_year = (365 * 24 * 3600) / reading_interval_seconds as i64;
        let total_readings =
            readings_per_sensor_per_year * sensor_count as i64 * retention_years as i64;
        let bytes_per_reading = 200;
        let compression_ratio = 10.0;

        let uncompressed_gb =
            (total_readings * bytes_per_reading) as f64 / 1024.0 / 1024.0 / 1024.0;
        let compressed_gb = uncompressed_gb / compression_ratio;

        Ok(StorageEstimate {
            scenario: format!(
                "{sensor_count} sensors, {reading_interval_seconds} sec intervals, \
                 {retention_years} years",
            ),
            total_readings: Some(total_readings),
            uncompressed_size_gb: Some(uncompressed_gb),
            compressed_size_gb: Some(compressed_gb),
            daily_aggregates_size_mb: Some(
                (sensor_count * 365 * retention_years * 150) as f64 / 1024.0 / 1024.0,
            ),
            hourly_aggregates_size_mb: Some(
                (sensor_count * 365 * 24 * retention_years * 150) as f64 / 1024.0 / 1024.0,
            ),
            total_estimated_size_gb: Some(compressed_gb + 0.1), // Add small overhead
        })
    }

    pub async fn get_growth_statistics(&self, days_back: i32) -> Result<GrowthStatistics> {
        let start_time = Utc::now() - chrono::Duration::days(days_back as i64);

        let row = sqlx::query(
            r#"
            SELECT
                $1 as period_days,
                COUNT(*) as readings_added,
                COUNT(*)::NUMERIC / $1 as readings_per_day,
                100.0 as storage_growth_mb,
                365.0 as estimated_yearly_growth_gb
            FROM sensor_data
            WHERE timestamp >= $2
            "#,
        )
        .bind(days_back)
        .bind(start_time)
        .fetch_one(&self.pool)
        .await?;

        let readings_per_day_bd: Option<BigDecimal> = row.get("readings_per_day");
        let storage_growth_mb_bd: Option<BigDecimal> = row.get("storage_growth_mb");
        let estimated_yearly_growth_gb_bd: Option<BigDecimal> =
            row.get("estimated_yearly_growth_gb");

        Ok(GrowthStatistics {
            period_days: row.get("period_days"),
            readings_added: row.get("readings_added"),
            readings_per_day: readings_per_day_bd.and_then(|bd| bd.to_f64()),
            storage_growth_mb: storage_growth_mb_bd.and_then(|bd| bd.to_f64()),
            estimated_yearly_growth_gb: estimated_yearly_growth_gb_bd.and_then(|bd| bd.to_f64()),
        })
    }

    pub async fn get_storage_monitoring_view(&self) -> Result<Vec<StorageStats>> {
        let stats = self.get_storage_stats().await?;
        Ok(vec![stats])
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SensorStats {
    pub avg_temperature: f64,
    pub min_temperature: f64,
    pub max_temperature: f64,
    pub avg_humidity: f64,
    pub min_humidity: f64,
    pub max_humidity: f64,
    pub avg_pressure: f64,
    pub min_pressure: f64,
    pub max_pressure: f64,
    pub reading_count: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SensorHealthMetrics {
    pub total_readings: i64,
    pub avg_battery: f64,
    pub min_battery: i64,
    pub avg_rssi: f64,
    pub min_rssi: i64,
    pub last_reading: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct StorageStats {
    pub table_name: String,
    pub raw_size_mb: Option<f64>,
    pub compressed_size_mb: Option<f64>,
    pub compression_ratio: Option<f64>,
    pub row_count: Option<i64>,
    pub oldest_data: Option<DateTime<Utc>>,
    pub newest_data: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct StorageEstimate {
    pub scenario: String,
    pub total_readings: Option<i64>,
    pub uncompressed_size_gb: Option<f64>,
    pub compressed_size_gb: Option<f64>,
    pub daily_aggregates_size_mb: Option<f64>,
    pub hourly_aggregates_size_mb: Option<f64>,
    pub total_estimated_size_gb: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct GrowthStatistics {
    pub period_days: Option<i32>,
    pub readings_added: Option<i64>,
    pub readings_per_day: Option<f64>,
    pub storage_growth_mb: Option<f64>,
    pub estimated_yearly_growth_gb: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct TimeBucketedData {
    pub bucket: DateTime<Utc>,
    pub avg_temperature: Option<f64>,
    pub min_temperature: Option<f64>,
    pub max_temperature: Option<f64>,
    pub avg_humidity: Option<f64>,
    pub min_humidity: Option<f64>,
    pub max_humidity: Option<f64>,
    pub avg_pressure: Option<f64>,
    pub min_pressure: Option<f64>,
    pub max_pressure: Option<f64>,
    pub reading_count: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum TimeInterval {
    Minutes(i32),
    Hours(i32),
    Days(i32),
    Weeks(i32),
}

impl TimeInterval {
    pub fn to_interval_string(&self) -> String {
        match self {
            TimeInterval::Minutes(m) => format!("{m} minutes"),
            TimeInterval::Hours(h) => format!("{h} hours"),
            TimeInterval::Days(d) => format!("{d} days"),
            TimeInterval::Weeks(w) => format!("{w} weeks"),
        }
    }
}
