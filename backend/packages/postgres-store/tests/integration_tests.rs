use chrono::{DateTime, Utc, Duration};
use postgres_store::{Event, PostgresStore, TimeInterval};
use sqlx::Row;
use std::env;

// Helper function to create a test database connection
async fn setup_test_db() -> PostgresStore {
    let database_url = env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home".to_string());
    
    let store = PostgresStore::new(&database_url).await
        .expect("Failed to connect to test database");
    
    // Clean up any existing test data
    cleanup_test_data(&store).await;
    
    store
}

async fn cleanup_test_data(store: &PostgresStore) {
    // Delete test data - we'll use a specific test sensor MAC
    let _ = sqlx::query("DELETE FROM sensor_data WHERE sensor_mac LIKE 'AA:BB:CC:DD:EE:%'")
        .execute(&store.pool)
        .await;
}

fn create_test_event(sensor_mac: &str, timestamp: DateTime<Utc>) -> Event {
    Event {
        sensor_mac: sensor_mac.to_string(),
        gateway_mac: "FF:FF:FF:FF:FF:01".to_string(),
        temperature: 22.5,
        humidity: 65.0,
        pressure: 1013.25,
        battery: 3000,
        tx_power: 4,
        movement_counter: 10,
        measurement_sequence_number: 1,
        acceleration: 1.0,
        acceleration_x: 100,
        acceleration_y: 200,
        acceleration_z: 1000,
        rssi: -45,
        timestamp,
    }
}

#[tokio::test]
async fn test_database_connection() {
    let store = setup_test_db().await;
    
    // Test basic query to ensure connection works
    let result = sqlx::query("SELECT 1 as test")
        .fetch_one(&store.pool)
        .await;
    
    assert!(result.is_ok());
    let row = result.unwrap();
    let test_value: i32 = row.get("test");
    assert_eq!(test_value, 1);
}

#[tokio::test]
async fn test_insert_and_retrieve_event() {
    let store = setup_test_db().await;
    let now = Utc::now();
    let test_event = create_test_event("AA:BB:CC:DD:EE:01", now);
    
    // Test insertion
    let result = store.insert_event(&test_event).await;
    assert!(result.is_ok(), "Failed to insert event: {:?}", result.err());
    
    // Test retrieval
    let retrieved = store.get_latest_reading("AA:BB:CC:DD:EE:01").await;
    assert!(retrieved.is_ok(), "Failed to retrieve event: {:?}", retrieved.err());
    
    let event = retrieved.unwrap();
    assert!(event.is_some(), "No event found");
    
    let event = event.unwrap();
    assert_eq!(event.sensor_mac, test_event.sensor_mac);
    assert_eq!(event.temperature, test_event.temperature);
    assert_eq!(event.humidity, test_event.humidity);
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_get_active_sensors() {
    let store = setup_test_db().await;
    let now = Utc::now();
    
    // Insert events for multiple sensors
    let event1 = create_test_event("AA:BB:CC:DD:EE:01", now);
    let event2 = create_test_event("AA:BB:CC:DD:EE:02", now - Duration::minutes(30));
    let event3 = create_test_event("AA:BB:CC:DD:EE:03", now - Duration::hours(25)); // Should not appear in active
    
    store.insert_event(&event1).await.expect("Failed to insert event1");
    store.insert_event(&event2).await.expect("Failed to insert event2");
    store.insert_event(&event3).await.expect("Failed to insert event3");
    
    // Get active sensors (last 24 hours)
    let active = store.get_active_sensors().await;
    assert!(active.is_ok(), "Failed to get active sensors: {:?}", active.err());
    
    let sensors = active.unwrap();
    let test_sensors: Vec<_> = sensors.iter()
        .filter(|s| s.sensor_mac.starts_with("AA:BB:CC:DD:EE:"))
        .collect();
    
    // Should find 2 active sensors (event1 and event2, but not event3 which is > 24h old)
    assert_eq!(test_sensors.len(), 2);
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_historical_data() {
    let store = setup_test_db().await;
    let now = Utc::now();
    
    // Insert multiple events across time
    let events = vec![
        create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(2)),
        create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(1)),
        create_test_event("AA:BB:CC:DD:EE:01", now - Duration::minutes(30)),
        create_test_event("AA:BB:CC:DD:EE:01", now),
    ];
    
    for event in &events {
        store.insert_event(event).await.expect("Failed to insert event");
    }
    
    // Test historical data retrieval
    let start = now - Duration::hours(3);
    let end = now;
    
    let history = store.get_historical_data("AA:BB:CC:DD:EE:01", Some(start), Some(end), Some(10)).await;
    assert!(history.is_ok(), "Failed to get historical data: {:?}", history.err());
    
    let readings = history.unwrap();
    assert_eq!(readings.len(), 4, "Expected 4 historical readings");
    
    // Verify readings are in descending order by timestamp
    for i in 1..readings.len() {
        assert!(readings[i-1].timestamp >= readings[i].timestamp, 
                "Readings should be in descending order");
    }
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_time_bucketing() {
    let store = setup_test_db().await;
    let now = Utc::now();
    
    // Insert events across multiple hours with varying temperatures
    let events = vec![
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(2));
            e.temperature = 20.0;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(2) + Duration::minutes(30));
            e.temperature = 22.0;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(1));
            e.temperature = 25.0;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(1) + Duration::minutes(30));
            e.temperature = 27.0;
            e
        },
    ];
    
    for event in &events {
        store.insert_event(event).await.expect("Failed to insert event");
    }
    
    // Test hourly bucketing
    let start = now - Duration::hours(3);
    let end = now;
    
    let bucketed = store.get_time_bucketed_data(
        "AA:BB:CC:DD:EE:01", 
        &TimeInterval::Hours(1), 
        start, 
        end
    ).await;
    
    assert!(bucketed.is_ok(), "Failed to get bucketed data: {:?}", bucketed.err());
    
    let buckets = bucketed.unwrap();
    assert!(!buckets.is_empty(), "Expected bucketed data");
    
    // Verify bucket structure
    for bucket in &buckets {
        assert!(bucket.avg_temperature.is_some(), "Average temperature should be calculated");
        assert!(bucket.min_temperature.is_some(), "Min temperature should be calculated");
        assert!(bucket.max_temperature.is_some(), "Max temperature should be calculated");
        assert!(bucket.reading_count.is_some(), "Reading count should be calculated");
    }
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_sensor_statistics() {
    let store = setup_test_db().await;
    let now = Utc::now();
    
    // Insert events with varying values
    let events = vec![
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(1));
            e.temperature = 20.0;
            e.battery = 3000;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::minutes(30));
            e.temperature = 25.0;
            e.battery = 2950;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now);
            e.temperature = 22.0;
            e.battery = 2900;
            e
        },
    ];
    
    for event in &events {
        store.insert_event(event).await.expect("Failed to insert event");
    }
    
    // Test statistics calculation
    let stats = store.get_sensor_statistics("AA:BB:CC:DD:EE:01", 2).await;
    assert!(stats.is_ok(), "Failed to get sensor statistics: {:?}", stats.err());
    
    let stats = stats.unwrap();
    assert_eq!(stats.reading_count, 3);
    assert!(stats.avg_temperature > 20.0 && stats.avg_temperature < 25.0);
    assert_eq!(stats.min_temperature, 20.0);
    assert_eq!(stats.max_temperature, 25.0);
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_storage_stats() {
    let store = setup_test_db().await;
    
    let stats = store.get_storage_stats().await;
    assert!(stats.is_ok(), "Failed to get storage stats: {:?}", stats.err());
    
    let stats = stats.unwrap();
    assert_eq!(stats.table_name, "sensor_data");
    assert!(stats.raw_size_mb.is_some());
    assert!(stats.compressed_size_mb.is_some());
    assert!(stats.compression_ratio.is_some());
    assert!(stats.row_count.is_some());
}

#[tokio::test]
async fn test_storage_estimation() {
    let store = setup_test_db().await;
    
    let estimate = store.estimate_storage_requirements(10, 10, 5).await;
    assert!(estimate.is_ok(), "Failed to get storage estimate: {:?}", estimate.err());
    
    let estimate = estimate.unwrap();
    assert!(estimate.total_readings.is_some());
    assert!(estimate.compressed_size_gb.is_some());
    assert!(estimate.total_estimated_size_gb.is_some());
    
    let total_readings = estimate.total_readings.unwrap();
    let expected_readings = (365 * 24 * 3600 / 10) * 10 * 5; // 10 sensors, 10sec interval, 5 years
    assert_eq!(total_readings, expected_readings);
}

#[tokio::test]
async fn test_growth_statistics() {
    let store = setup_test_db().await;
    let now = Utc::now();
    
    // Insert some test data
    let event = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::days(1));
    store.insert_event(&event).await.expect("Failed to insert event");
    
    let stats = store.get_growth_statistics(30).await;
    assert!(stats.is_ok(), "Failed to get growth statistics: {:?}", stats.err());
    
    let stats = stats.unwrap();
    assert!(stats.period_days.is_some());
    assert!(stats.readings_added.is_some());
    assert!(stats.readings_per_day.is_some());
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_temperature_trend() {
    let store = setup_test_db().await;
    let now = Utc::now();
    
    // Insert events across time
    let events = vec![
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(1));
            e.temperature = 20.0;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::minutes(30));
            e.temperature = 22.0;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now);
            e.temperature = 24.0;
            e
        },
    ];
    
    for event in &events {
        store.insert_event(event).await.expect("Failed to insert event");
    }
    
    let trend = store.get_temperature_trend("AA:BB:CC:DD:EE:01", 2).await;
    assert!(trend.is_ok(), "Failed to get temperature trend: {:?}", trend.err());
    
    let trend = trend.unwrap();
    assert!(!trend.is_empty(), "Expected temperature trend data");
    
    // Verify trend data structure
    for (timestamp, temperature) in &trend {
        assert!(temperature > &0.0, "Temperature should be positive");
        assert!(timestamp < &Utc::now(), "Timestamp should be in the past");
    }
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_sensor_health_metrics() {
    let store = setup_test_db().await;
    let now = Utc::now();
    
    // Insert events with health data
    let events = vec![
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::hours(1));
            e.battery = 3000;
            e.rssi = -40;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now - Duration::minutes(30));
            e.battery = 2950;
            e.rssi = -45;
            e
        },
        {
            let mut e = create_test_event("AA:BB:CC:DD:EE:01", now);
            e.battery = 2900;
            e.rssi = -50;
            e
        },
    ];
    
    for event in &events {
        store.insert_event(event).await.expect("Failed to insert event");
    }
    
    let health = store.get_sensor_health_metrics("AA:BB:CC:DD:EE:01", 2).await;
    assert!(health.is_ok(), "Failed to get sensor health metrics: {:?}", health.err());
    
    let health = health.unwrap();
    assert_eq!(health.total_readings, 3);
    assert!(health.avg_battery > 2900.0 && health.avg_battery < 3000.0);
    assert_eq!(health.min_battery, 2900);
    assert!(health.avg_rssi < 0.0); // RSSI should be negative
    assert_eq!(health.min_rssi, -50);
    assert!(health.last_reading.is_some());
    
    cleanup_test_data(&store).await;
}

#[tokio::test]
async fn test_error_handling() {
    let store = setup_test_db().await;
    
    // Test retrieval of non-existent sensor
    let result = store.get_latest_reading("NONEXISTENT:SENSOR").await;
    assert!(result.is_ok());
    assert!(result.unwrap().is_none());
    
    // Test historical data for non-existent sensor
    let now = Utc::now();
    let history = store.get_historical_data(
        "NONEXISTENT:SENSOR", 
        Some(now - Duration::hours(1)), 
        Some(now), 
        Some(10)
    ).await;
    assert!(history.is_ok());
    let readings = history.unwrap();
    assert!(readings.is_empty());
}