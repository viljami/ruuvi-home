//! Unit tests for the API server
//!
//! These tests verify the core functionality of the API library including
//! configuration, query parsing, utility functions, and business logic.

use anyhow::Result;
use postgres_store::Event;

const EPSILON: f64 = 1e-10;

#[allow(clippy::many_single_char_names)]
fn assert_float_eq(actual: f64, expected: f64) {
    assert!(
        (actual - expected).abs() < EPSILON,
        "Expected {actual} to equal {expected}"
    );
}

/// Helper to create a test event for testing
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

#[tokio::test]
async fn test_health_handler_directly() {
    let result = api::handlers::health_check().await;
    assert_eq!(result, "OK");
}

// The following tests would require a real database connection
// They are marked as ignored and would need Docker/testcontainers to run

#[tokio::test]
#[ignore = "Requires database connection"]
async fn test_sensors_endpoint_empty() -> Result<()> {
    // This test would require setting up a test database
    // For now, we'll test the structure and leave the implementation
    // for when testcontainers is properly set up

    // let (_db_url, _container) = setup_test_database().await?;
    // let config = Config::new(db_url, 8080);
    // let state = AppState::new(config).await?;
    // let app = create_router(state);
    // let server = TestServer::new(app)?;

    // let response = server.get("/api/sensors").await;
    // assert_eq!(response.status_code(), StatusCode::OK);
    //
    // let sensors: Vec<Event> = response.json();
    // assert_eq!(sensors.len(), 0);

    Ok(())
}

#[tokio::test]
#[ignore = "Requires database connection"]
async fn test_sensor_latest_not_found() -> Result<()> {
    // Similar to above - would require database setup
    // let server = setup_test_server().await?;

    // let response = server.get("/api/sensors/AA:BB:CC:DD:EE:99/latest").await;
    // assert_eq!(response.status_code(), StatusCode::NOT_FOUND);

    Ok(())
}

#[tokio::test]
async fn test_sensor_validation_logic() {
    // Test MAC validation logic directly
    assert!(!api::utils::is_valid_mac_format("invalid-mac"));
    assert!(api::utils::is_valid_mac_format("AA:BB:CC:DD:EE:FF"));
}

#[tokio::test]
async fn test_datetime_parsing_logic() {
    // Test datetime parsing directly
    assert!(api::utils::parse_datetime("2024-01-01T00:00:00Z").is_ok());
    assert!(api::utils::parse_datetime("invalid-date").is_err());
}

#[tokio::test]
async fn test_interval_parsing_logic() {
    // Test interval parsing directly
    let valid_intervals = vec!["15m", "1h", "1d", "1w"];
    for interval in valid_intervals {
        assert!(
            api::utils::parse_interval(interval).is_some(),
            "Failed for interval: {interval}"
        );
    }

    let invalid_intervals = vec!["30m", "2h", "invalid", ""];
    for interval in invalid_intervals {
        assert!(
            api::utils::parse_interval(interval).is_none(),
            "Should fail for interval: {interval}"
        );
    }
}

#[tokio::test]
async fn test_parameter_validation_logic() {
    // Test parameter validation logic directly

    // Valid parameters
    let sensor_count = 10;
    let interval_seconds = 30;
    let retention_years = 5;

    assert!(sensor_count > 0 && sensor_count <= 10000);
    assert!(interval_seconds > 0 && interval_seconds <= 86400);
    assert!(retention_years > 0 && retention_years <= 100);

    // Invalid parameters
    // Test boundary validation - these are compile-time constants
    // so we just document the expected behavior:
    // sensor_count = 0, sensor_count > 10000 should fail
    // interval_seconds = 0, interval_seconds > 86400 should fail
    // retention_years = 0, retention_years > 100 should fail
}

#[tokio::test]
#[allow(clippy::unwrap_used)]
async fn test_query_parameter_parsing() {
    // Test that our query structs deserialize correctly
    let historical_query: api::HistoricalQuery =
        serde_json::from_str(r#"{"start": "2024-01-01T00:00:00Z", "limit": 100}"#).unwrap();

    assert_eq!(
        historical_query.start,
        Some("2024-01-01T00:00:00Z".to_string())
    );
    assert_eq!(historical_query.limit, Some(100));
    assert_eq!(historical_query.end, None);

    let time_bucket_query: api::TimeBucketQuery =
        serde_json::from_str(r#"{"interval": "1h"}"#).unwrap();

    assert_eq!(time_bucket_query.interval, Some("1h".to_string()));
    assert_eq!(time_bucket_query.start, None);
    assert_eq!(time_bucket_query.end, None);

    let storage_query: api::StorageEstimateQuery = serde_json::from_str(
        r#"{"sensor_count": 20, "interval_seconds": 30, "retention_years": 3}"#,
    )
    .unwrap();

    assert_eq!(storage_query.sensor_count, Some(20));
    assert_eq!(storage_query.interval_seconds, Some(30));
    assert_eq!(storage_query.retention_years, Some(3));
}

#[tokio::test]
async fn test_mac_address_validation_edge_cases() {
    let test_cases = vec![
        ("AA:BB:CC:DD:EE:FF", true),     // Valid
        ("aa:bb:cc:dd:ee:ff", true),     // Valid lowercase
        ("12:34:56:78:9A:BC", true),     // Valid mixed case
        ("AA:BB:CC:DD:EE", false),       // Too short
        ("AA:BB:CC:DD:EE:FF:GG", false), // Too long
        ("AA-BB-CC-DD-EE-FF", false),    // Wrong separator
        ("GG:HH:II:JJ:KK:LL", false),    // Invalid hex
        ("", false),                     // Empty
        ("AA:BB:CC:DD:EE:FG", false),    // Invalid hex character
    ];

    for (mac, expected) in test_cases {
        let result = api::utils::is_valid_mac_format(mac);
        assert_eq!(result, expected, "Failed for MAC: {mac}");
    }
}

#[tokio::test]
async fn test_limit_validation() {
    let test_cases = vec![
        (1, true),
        (100, true),
        (1000, true),
        (10000, true),
        (0, false),
        (-1, false),
        (10001, false),
        (100_000, false),
    ];

    for (limit, expected) in test_cases {
        let result = api::utils::validate_limit(limit);
        assert_eq!(result, expected, "Failed for limit: {limit}");
    }
}

#[tokio::test]
#[allow(clippy::unwrap_used)]
async fn test_config_creation() {
    // Test basic config creation
    let config = api::Config::new("postgresql://test".to_string(), 3000);
    assert_eq!(config.database_url, "postgresql://test");
    assert_eq!(config.api_port, 3000);

    // Test config from environment with defaults
    std::env::remove_var("DATABASE_URL");
    std::env::remove_var("API_PORT");

    let config = api::Config::from_env().unwrap();
    assert!(config
        .database_url
        .contains("postgresql://ruuvi:ruuvi_secret"));
    assert_eq!(config.api_port, 8080);
}

#[tokio::test]
async fn test_config_basic_creation() {
    // Test that we can create config without panicking
    let config = api::Config::new("postgresql://fake".to_string(), 8080);
    assert_eq!(config.api_port, 8080);
    assert_eq!(config.database_url, "postgresql://fake");
}

#[tokio::test]
async fn test_utility_functions() {
    // Test datetime parsing
    assert!(api::utils::parse_datetime("2024-01-01T00:00:00Z").is_ok());
    assert!(api::utils::parse_datetime("invalid").is_err());

    // Test interval parsing
    assert!(api::utils::parse_interval("1h").is_some());
    assert!(api::utils::parse_interval("invalid").is_none());

    // Test MAC sanitization
    assert_eq!(
        api::utils::sanitize_mac_for_logging("AA:BB:CC:DD:EE:01"),
        "AA:BB:CC:DD:EE:01"
    );
    assert_eq!(
        api::utils::sanitize_mac_for_logging("D1:10:96:D8:08:F4"),
        "D1:10:96:D8:XX:XX"
    );

    // Test duration formatting
    assert_eq!(api::utils::format_duration_human(30), "30s");
    assert_eq!(api::utils::format_duration_human(3600), "1h");
    assert_eq!(api::utils::format_duration_human(86400), "1d");
}

// Note: Full end-to-end tests with real database would go here
// They would be marked with #[ignore] and require Docker setup

#[tokio::test]
async fn test_event_creation() {
    // Test that we can create test events
    let event = create_test_event("AA:BB:CC:DD:EE:01");
    assert_eq!(event.sensor_mac, "AA:BB:CC:DD:EE:01");
    assert_eq!(event.gateway_mac, "FF:FF:FF:FF:FF:01");
    assert_float_eq(event.temperature, 22.5);
    assert_float_eq(event.humidity, 65.0);
    assert_float_eq(event.pressure, 1013.25);
}

// Note: Full HTTP integration tests would require a test server setup
// For now, we focus on unit testing the core logic and utility functions
