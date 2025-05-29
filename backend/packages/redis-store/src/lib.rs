use std::collections::HashMap;
use anyhow::Result;
use chrono::{DateTime, Utc};
use redis::{AsyncCommands, Client, Connection};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;
use tracing::{error, info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
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

    fn to_redis_fields(&self) -> Vec<(String, String)> {
        vec![
            ("sensor_mac".to_string(), self.sensor_mac.clone()),
            ("gateway_mac".to_string(), self.gateway_mac.clone()),
            ("temperature".to_string(), self.temperature.to_string()),
            ("humidity".to_string(), self.humidity.to_string()),
            ("pressure".to_string(), self.pressure.to_string()),
            ("battery".to_string(), self.battery.to_string()),
            ("tx_power".to_string(), self.tx_power.to_string()),
            ("movement_counter".to_string(), self.movement_counter.to_string()),
            ("measurement_sequence_number".to_string(), self.measurement_sequence_number.to_string()),
            ("acceleration".to_string(), self.acceleration.to_string()),
            ("acceleration_x".to_string(), self.acceleration_x.to_string()),
            ("acceleration_y".to_string(), self.acceleration_y.to_string()),
            ("acceleration_z".to_string(), self.acceleration_z.to_string()),
            ("rssi".to_string(), self.rssi.to_string()),
            ("timestamp".to_string(), self.timestamp.timestamp_millis().to_string()),
        ]
    }

    fn from_redis_fields(fields: &[(String, String)]) -> Result<Self> {
        let mut field_map: HashMap<String, String> = fields.iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();

        let sensor_mac = field_map.remove("sensor_mac")
            .ok_or_else(|| anyhow::anyhow!("Missing sensor_mac field"))?;
        let gateway_mac = field_map.remove("gateway_mac")
            .ok_or_else(|| anyhow::anyhow!("Missing gateway_mac field"))?;
        
        let temperature = field_map.remove("temperature")
            .ok_or_else(|| anyhow::anyhow!("Missing temperature field"))?
            .parse::<f64>()?;
        let humidity = field_map.remove("humidity")
            .ok_or_else(|| anyhow::anyhow!("Missing humidity field"))?
            .parse::<f64>()?;
        let pressure = field_map.remove("pressure")
            .ok_or_else(|| anyhow::anyhow!("Missing pressure field"))?
            .parse::<f64>()?;
        let battery = field_map.remove("battery")
            .ok_or_else(|| anyhow::anyhow!("Missing battery field"))?
            .parse::<i64>()?;
        let tx_power = field_map.remove("tx_power")
            .ok_or_else(|| anyhow::anyhow!("Missing tx_power field"))?
            .parse::<i64>()?;
        let movement_counter = field_map.remove("movement_counter")
            .ok_or_else(|| anyhow::anyhow!("Missing movement_counter field"))?
            .parse::<i64>()?;
        let measurement_sequence_number = field_map.remove("measurement_sequence_number")
            .ok_or_else(|| anyhow::anyhow!("Missing measurement_sequence_number field"))?
            .parse::<i64>()?;
        let acceleration = field_map.remove("acceleration")
            .ok_or_else(|| anyhow::anyhow!("Missing acceleration field"))?
            .parse::<f64>()?;
        let acceleration_x = field_map.remove("acceleration_x")
            .ok_or_else(|| anyhow::anyhow!("Missing acceleration_x field"))?
            .parse::<i64>()?;
        let acceleration_y = field_map.remove("acceleration_y")
            .ok_or_else(|| anyhow::anyhow!("Missing acceleration_y field"))?
            .parse::<i64>()?;
        let acceleration_z = field_map.remove("acceleration_z")
            .ok_or_else(|| anyhow::anyhow!("Missing acceleration_z field"))?
            .parse::<i64>()?;
        let rssi = field_map.remove("rssi")
            .ok_or_else(|| anyhow::anyhow!("Missing rssi field"))?
            .parse::<i64>()?;
        
        let timestamp_millis = field_map.remove("timestamp")
            .ok_or_else(|| anyhow::anyhow!("Missing timestamp field"))?
            .parse::<i64>()?;
        let timestamp = DateTime::from_timestamp_millis(timestamp_millis)
            .ok_or_else(|| anyhow::anyhow!("Invalid timestamp"))?
            .with_timezone(&Utc);

        Ok(Self {
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
            timestamp,
        })
    }
}

#[derive(Debug, Clone)]
pub struct RedisStore {
    client: Client,
    event_sender: broadcast::Sender<Event>,
}

impl RedisStore {
    pub async fn new(redis_url: &str) -> Result<Self> {
        let client = Client::open(redis_url)?;
        
        // Test connection
        let mut conn = client.get_multiplexed_async_connection().await?;
        let _: String = conn.ping().await?;
        
        let (event_sender, _) = broadcast::channel(1000);
        
        info!("Connected to Redis at {}", redis_url);
        
        Ok(Self {
            client,
            event_sender,
        })
    }

    pub async fn insert_event(&self, event: &Event) -> Result<()> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        
        // Store in Redis Stream for time-series data
        let stream_key = format!("sensor_data:{}", event.sensor_mac);
        let fields = event.to_redis_fields();
        
        let _: String = conn.xadd(&stream_key, "*", &fields).await?;
        
        // Store latest reading for quick access
        let latest_key = format!("latest:{}", event.sensor_mac);
        let serialized = serde_json::to_string(event)?;
        let _: () = conn.set(&latest_key, &serialized).await?;
        let _: () = conn.expire(&latest_key, 86400).await?; // Expire after 24 hours
        
        // Add to active sensors set
        let active_key = "active_sensors";
        let _: () = conn.sadd(&active_key, &event.sensor_mac).await?;
        
        // Publish to pub/sub channel for real-time notifications
        let channel = "sensor_events";
        let _: () = conn.publish(channel, &serialized).await?;
        
        // Send to local broadcast channel
        if let Err(e) = self.event_sender.send(event.clone()) {
            error!("Failed to broadcast new event: {}", e);
        }
        
        Ok(())
    }

    pub async fn get_active_sensors(&self) -> Result<Vec<Event>> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        
        // Get all active sensor MACs
        let active_key = "active_sensors";
        let sensor_macs: Vec<String> = conn.smembers(&active_key).await?;
        
        let mut events = Vec::new();
        
        for sensor_mac in sensor_macs {
            if let Ok(Some(event)) = self.get_latest_reading(&sensor_mac).await {
                // Check if the reading is within the last 24 hours
                let hours_ago_24 = Utc::now() - chrono::Duration::hours(24);
                if event.timestamp >= hours_ago_24 {
                    events.push(event);
                } else {
                    // Remove from active sensors if too old
                    let _: () = conn.srem(&active_key, &sensor_mac).await?;
                }
            }
        }
        
        Ok(events)
    }

    pub async fn get_latest_reading(&self, sensor_mac: &str) -> Result<Option<Event>> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        
        let latest_key = format!("latest:{}", sensor_mac);
        let serialized: Option<String> = conn.get(&latest_key).await?;
        
        match serialized {
            Some(data) => {
                let event: Event = serde_json::from_str(&data)?;
                Ok(Some(event))
            },
            None => Ok(None),
        }
    }

    pub async fn get_historical_data(
        &self,
        sensor_mac: &str,
        start: Option<DateTime<Utc>>,
        end: Option<DateTime<Utc>>,
        limit: Option<i64>,
    ) -> Result<Vec<Event>> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        
        let stream_key = format!("sensor_data:{}", sensor_mac);
        let limit = limit.unwrap_or(100);
        
        // Convert timestamps to Redis stream IDs if provided
        let start_id = match start {
            Some(ts) => ts.timestamp_millis().to_string(),
            None => "-".to_string(),
        };
        
        let end_id = match end {
            Some(ts) => ts.timestamp_millis().to_string(),
            None => "+".to_string(),
        };
        
        // Use XREVRANGE to get data in reverse chronological order
        let stream_data: Vec<redis::streams::StreamRangeReply> = conn
            .xrevrange_count(&stream_key, &end_id, &start_id, limit as usize)
            .await?;
        
        let mut events = Vec::new();
        
        for entry in stream_data {
            for stream_entry in entry.ids {
                match Event::from_redis_fields(&stream_entry.map) {
                    Ok(event) => events.push(event),
                    Err(e) => warn!("Failed to parse event from Redis: {}", e),
                }
            }
        }
        
        Ok(events)
    }

    pub async fn get_sensor_data_range(
        &self,
        sensor_mac: &str,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<Event>> {
        self.get_historical_data(sensor_mac, Some(start), Some(end), None).await
    }

    pub fn subscribe_to_events(&self) -> broadcast::Receiver<Event> {
        self.event_sender.subscribe()
    }

    pub async fn cleanup_old_data(&self, sensor_mac: &str, days_to_keep: i32) -> Result<u64> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        
        let stream_key = format!("sensor_data:{}", sensor_mac);
        let cutoff_time = Utc::now() - chrono::Duration::days(days_to_keep as i64);
        let cutoff_id = cutoff_time.timestamp_millis().to_string();
        
        // Count entries before deletion
        let count_before: usize = conn.xlen(&stream_key).await.unwrap_or(0);
        
        // Delete old entries using XTRIM
        let _: () = conn.xtrim(&stream_key, redis::streams::StreamMaxlen::Approx(1000)).await?;
        
        // Get count after deletion
        let count_after: usize = conn.xlen(&stream_key).await.unwrap_or(0);
        
        Ok((count_before - count_after) as u64)
    }

    pub async fn subscribe_to_redis_pubsub(&self) -> Result<redis::aio::PubSub> {
        let conn = self.client.get_async_connection().await?;
        let mut pubsub = conn.into_pubsub();
        pubsub.subscribe("sensor_events").await?;
        Ok(pubsub)
    }

    pub async fn get_sensor_count(&self) -> Result<usize> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        let active_key = "active_sensors";
        let count: usize = conn.scard(&active_key).await?;
        Ok(count)
    }

    pub async fn remove_sensor(&self, sensor_mac: &str) -> Result<()> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        
        // Remove from active sensors
        let active_key = "active_sensors";
        let _: () = conn.srem(&active_key, sensor_mac).await?;
        
        // Remove latest reading
        let latest_key = format!("latest:{}", sensor_mac);
        let _: () = conn.del(&latest_key).await?;
        
        Ok(())
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