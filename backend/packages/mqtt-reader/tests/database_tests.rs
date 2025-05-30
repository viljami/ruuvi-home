//! Database writing tests for mqtt-reader
//!
//! These tests verify the database writing functionality of the mqtt-reader,
//! including PostgreSQL integration, error handling, and data persistence.

use anyhow::Result;
use chrono::Utc;
use mqtt_reader::write::{
    config::Config,
    db::PostgresWriter,
};
use postgres_store::Event;
use testcontainers_modules::{
    postgres,
    testcontainers::runners::AsyncRunner,
};
use tokio;

/// Helper to create a test event for database writing tests
fn create_test_event(sensor_mac: &str) -> Event {
    Event::new_with_current_time(
        sensor_mac.to_string(),
        "FF:FF:FF:FF:FF:01".to_string(),
        22.5,
        65.0,
        1013.25,
        3000,
        4,
        10,
        1,
        1.0,
        -16,
        -20,
        1044,
        -40,
    )
}

/// Helper to create multiple test events with different sensor MACs
fn create_multiple_test_events() -> Vec<Event> {
    vec![
        create_test_event("AA:BB:CC:DD:EE:01"),
        create_test_event("AA:BB:CC:DD:EE:02"),
        create_test_event("AA:BB:CC:DD:EE:03"),
    ]
}

/// Helper to create a test event with specific values
fn create_custom_test_event(
    sensor_mac: &str,
    temperature: f64,
    humidity: f64,
    pressure: f64,
) -> Event {
    Event::new_with_current_time(
        sensor_mac.to_string(),
        "GW:GW:GW:GW:GW:01".to_string(),
        temperature,
        humidity,
        pressure,
        2800,
        0,
        5,
        100,
        0.98,
        10,
        -5,
        1000,
        -50,
    )
}

#[tokio::test]
async fn test_config_creation() {
    let config = Config::new("postgresql://test:test@localhost:5432/test".to_string());
    assert_eq!(
        config.database_url,
        "postgresql://test:test@localhost:5432/test"
    );

    let cloned = config.clone();
    assert_eq!(config.database_url, cloned.database_url);
}

#[tokio::test]
async fn test_config_from_env() {
    // Save original value
    let original_db_url = std::env::var("DATABASE_URL").ok();

    // Set test value
    let test_url = "postgresql://envtest:envtest@localhost:5432/envtest";
    std::env::set_var("DATABASE_URL", test_url);

    let config = Config::from_env();
    assert_eq!(config.database_url, test_url);

    // Restore original value or remove if it wasn't set
    match original_db_url {
        Some(url) => std::env::set_var("DATABASE_URL", url),
        None => std::env::remove_var("DATABASE_URL"),
    }
}

#[tokio::test]
async fn test_postgres_writer_creation_invalid_url() {
    let config = Config::new("invalid://url".to_string());
    let result = PostgresWriter::new(&config.database_url).await;
    assert!(result.is_err());
}

#[tokio::test]
async fn test_event_creation_and_validation() {
    let event = create_test_event("AA:BB:CC:DD:EE:01");

    assert_eq!(event.sensor_mac, "AA:BB:CC:DD:EE:01");
    assert_eq!(event.gateway_mac, "FF:FF:FF:FF:FF:01");
    assert_eq!(event.temperature, 22.5);
    assert_eq!(event.humidity, 65.0);
    assert_eq!(event.pressure, 1013.25);
    assert_eq!(event.battery, 3000);
    assert_eq!(event.tx_power, 4);
    assert_eq!(event.movement_counter, 10);
    assert_eq!(event.measurement_sequence_number, 1);
    assert_eq!(event.acceleration, 1.0);
    assert_eq!(event.acceleration_x, -16);
    assert_eq!(event.acceleration_y, -20);
    assert_eq!(event.acceleration_z, 1044);
    assert_eq!(event.rssi, -40);
}

#[tokio::test]
async fn test_multiple_events_creation() {
    let events = create_multiple_test_events();
    assert_eq!(events.len(), 3);

    assert_eq!(events[0].sensor_mac, "AA:BB:CC:DD:EE:01");
    assert_eq!(events[1].sensor_mac, "AA:BB:CC:DD:EE:02");
    assert_eq!(events[2].sensor_mac, "AA:BB:CC:DD:EE:03");

    // All events should have the same gateway MAC
    for event in &events {
        assert_eq!(event.gateway_mac, "FF:FF:FF:FF:FF:01");
    }
}

#[tokio::test]
async fn test_custom_event_creation() {
    let event = create_custom_test_event("CUSTOM:MAC", 25.0, 45.0, 1020.0);

    assert_eq!(event.sensor_mac, "CUSTOM:MAC");
    assert_eq!(event.temperature, 25.0);
    assert_eq!(event.humidity, 45.0);
    assert_eq!(event.pressure, 1020.0);
}

#[tokio::test]
async fn test_event_timestamp_generation() {
    let before = Utc::now();
    let event = create_test_event("TIME:TEST");
    let after = Utc::now();

    assert!(event.timestamp >= before);
    assert!(event.timestamp <= after);
}

#[tokio::test]
async fn test_event_edge_values() {
    let event = Event::new_with_current_time(
        "EDGE:TEST".to_string(),
        "GW:EDGE:TEST".to_string(),
        -40.0, // Cold temperature
        0.0,   // Minimum humidity
        800.0, // Low pressure
        0,     // Empty battery
        -20,   // Low TX power
        255,   // Max movement counter
        65535, // Max sequence number
        0.0,   // No acceleration
        -2000, // Min acceleration X
        2000,  // Max acceleration Y
        0,     // No Z acceleration
        -120,  // Very weak signal
    );

    assert_eq!(event.sensor_mac, "EDGE:TEST");
    assert_eq!(event.temperature, -40.0);
    assert_eq!(event.humidity, 0.0);
    assert_eq!(event.battery, 0);
    assert_eq!(event.movement_counter, 255);
    assert_eq!(event.measurement_sequence_number, 65535);
    assert_eq!(event.rssi, -120);
}

#[tokio::test]
async fn test_write_config_validation() {
    // Test various database URL formats
    let valid_urls = vec![
        "postgresql://user:pass@localhost:5432/db",
        "postgres://user:pass@localhost:5432/db",
        "postgresql://localhost/db",
        "postgresql://user@localhost/db",
    ];

    for url in valid_urls {
        let config = Config::new(url.to_string());
        assert_eq!(config.database_url, url);
    }
}

// Integration tests with real database (marked as ignored by default)
// These require Docker to run

#[tokio::test]
#[ignore = "Requires Docker for PostgreSQL"]
async fn test_postgres_writer_integration() -> Result<()> {
    let container = postgres::Postgres::default()
        .start()
        .await
        .expect("postgres");

    let connection_string = format!(
        "postgresql://postgres:postgres@localhost:{}/postgres",
        container
            .get_host_port_ipv4(5432)
            .await
            .expect("Failed to get host port")
    );

    // Wait for database to be ready
    tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

    let writer = PostgresWriter::new(&connection_string)
        .await
        .expect("Failed to create PostgresWriter");
    let events = create_multiple_test_events();

    let result = writer.write_sensor_data(events).await;
    assert!(result.is_ok());

    Ok(())
}

#[tokio::test]
#[ignore = "Requires Docker for PostgreSQL"]
async fn test_postgres_writer_single_event() -> Result<()> {
    let container = postgres::Postgres::default()
        .start()
        .await
        .expect("postgres");

    let connection_string = format!(
        "postgresql://postgres:postgres@localhost:{}/postgres",
        container
            .get_host_port_ipv4(5432)
            .await
            .expect("Failed to get host port")
    );

    // Wait for database to be ready
    tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

    let writer = PostgresWriter::new(&connection_string)
        .await
        .expect("Failed to create PostgresWriter");
    let event = create_test_event("SINGLE:EVENT");

    let result = writer.write_sensor_data(vec![event]).await;
    assert!(result.is_ok());

    Ok(())
}

#[tokio::test]
#[ignore = "Requires Docker for PostgreSQL"]
async fn test_postgres_writer_empty_events() -> Result<()> {
    let container = postgres::Postgres::default()
        .start()
        .await
        .expect("postgres");

    let connection_string = format!(
        "postgresql://postgres:postgres@localhost:{}/postgres",
        container
            .get_host_port_ipv4(5432)
            .await
            .expect("Failed to get host port")
    );

    // Wait for database to be ready
    tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

    let writer = PostgresWriter::new(&connection_string)
        .await
        .expect("Failed to create PostgresWriter");
    let events: Vec<Event> = vec![];

    let result = writer.write_sensor_data(events).await;
    assert!(result.is_ok()); // Writing empty events should succeed

    Ok(())
}

#[tokio::test]
#[ignore = "Requires Docker for PostgreSQL"]
async fn test_postgres_writer_large_batch() -> Result<()> {
    let container = postgres::Postgres::default()
        .start()
        .await
        .expect("postgres");

    let connection_string = format!(
        "postgresql://postgres:postgres@localhost:{}/postgres",
        container
            .get_host_port_ipv4(5432)
            .await
            .expect("Failed to get host port")
    );

    // Wait for database to be ready
    tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

    let writer = PostgresWriter::new(&connection_string).await.expect("");

    // Create a large batch of events
    let mut events = Vec::new();
    for i in 0..100 {
        let mac = format!("BATCH:{:03}:TEST", i);
        events.push(create_test_event(&mac));
    }

    let result = writer.write_sensor_data(events).await;
    assert!(result.is_ok());

    Ok(())
}

#[tokio::test]
#[ignore = "Requires Docker for PostgreSQL"]
async fn test_postgres_writer_realistic_data() -> Result<()> {
    let container = postgres::Postgres::default()
        .start()
        .await
        .expect("postgres");

    let connection_string = format!(
        "postgresql://postgres:postgres@localhost:{}/postgres",
        container
            .get_host_port_ipv4(5432)
            .await
            .expect("Failed to get host port")
    );

    // Wait for database to be ready
    tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

    let writer = PostgresWriter::new(&connection_string)
        .await
        .expect("Failed to create PostgresWriter");

    // Create realistic sensor data
    let events = vec![
        create_custom_test_event("LIVING:ROOM", 21.5, 45.0, 1013.25),
        create_custom_test_event("BEDROOM", 19.0, 55.0, 1012.0),
        create_custom_test_event("KITCHEN", 23.0, 60.0, 1014.0),
        create_custom_test_event("BATHROOM", 22.0, 70.0, 1013.0),
        create_custom_test_event("OUTDOOR", 15.0, 80.0, 1015.0),
    ];

    let result = writer.write_sensor_data(events).await;
    assert!(result.is_ok());

    Ok(())
}

// Mock tests that don't require a real database

#[tokio::test]
async fn test_database_config_variations() {
    let configs = vec![
        "postgresql://user:pass@host:5432/db",
        "postgres://user:pass@host:5432/db",
        "postgresql://localhost/test",
        "postgresql://127.0.0.1:5432/db",
        "postgresql://user@host/db",
    ];

    for config_str in configs {
        let config = Config::new(config_str.to_string());
        assert_eq!(config.database_url, config_str);

        // Test cloning
        let cloned = config.clone();
        assert_eq!(cloned.database_url, config_str);
    }
}

#[tokio::test]
async fn test_event_data_integrity() {
    let original_event = create_test_event("INTEGRITY:TEST");

    // Create a clone and verify all fields match
    let cloned_event = Event::new_with_current_time(
        original_event.sensor_mac.clone(),
        original_event.gateway_mac.clone(),
        original_event.temperature,
        original_event.humidity,
        original_event.pressure,
        original_event.battery,
        original_event.tx_power,
        original_event.movement_counter,
        original_event.measurement_sequence_number,
        original_event.acceleration,
        original_event.acceleration_x,
        original_event.acceleration_y,
        original_event.acceleration_z,
        original_event.rssi,
    );

    assert_eq!(original_event.sensor_mac, cloned_event.sensor_mac);
    assert_eq!(original_event.gateway_mac, cloned_event.gateway_mac);
    assert_eq!(original_event.temperature, cloned_event.temperature);
    assert_eq!(original_event.humidity, cloned_event.humidity);
    assert_eq!(original_event.pressure, cloned_event.pressure);
    assert_eq!(original_event.battery, cloned_event.battery);
    assert_eq!(original_event.tx_power, cloned_event.tx_power);
    assert_eq!(
        original_event.movement_counter,
        cloned_event.movement_counter
    );
    assert_eq!(
        original_event.measurement_sequence_number,
        cloned_event.measurement_sequence_number
    );
    assert_eq!(original_event.acceleration, cloned_event.acceleration);
    assert_eq!(original_event.acceleration_x, cloned_event.acceleration_x);
    assert_eq!(original_event.acceleration_y, cloned_event.acceleration_y);
    assert_eq!(original_event.acceleration_z, cloned_event.acceleration_z);
    assert_eq!(original_event.rssi, cloned_event.rssi);
}

#[tokio::test]
async fn test_config_field_access() {
    let url = "postgresql://fieldtest@localhost/db".to_string();
    let config = Config::new(url.clone());

    // Test direct field access
    assert_eq!(config.database_url, url);

    // Test that we can create new config with different URL
    let new_url = "postgresql://newtest@localhost/newdb".to_string();
    let new_config = Config::new(new_url.clone());
    assert_eq!(new_config.database_url, new_url);
    assert_ne!(config.database_url, new_config.database_url);
}
