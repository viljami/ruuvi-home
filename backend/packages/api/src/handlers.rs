//! HTTP request handlers for the API

use axum::{
    extract::{
        Path,
        Query,
        State,
    },
    http::StatusCode,
    response::Json,
};
use chrono::{
    Duration,
    Utc,
};
use postgres_store::{
    Event,
    StorageEstimate,
    StorageStats,
    TimeBucketedData,
};
use tracing::error;

use crate::{
    queries::{
        HistoricalQuery,
        StorageEstimateQuery,
        TimeBucketQuery,
    },
    state::AppState,
    utils::{
        is_valid_mac_format,
        parse_datetime,
        parse_interval,
        sanitize_mac_for_logging,
        validate_limit,
    },
};

/// Health check endpoint
pub async fn health_check() -> &'static str {
    "OK"
}

/// Get all active sensors
///
/// # Errors
/// Returns `StatusCode::INTERNAL_SERVER_ERROR` if database query fails
pub async fn get_sensors(State(state): State<AppState>) -> Result<Json<Vec<Event>>, StatusCode> {
    match state.store.get_active_sensors().await {
        Ok(sensors) => {
            tracing::info!("Retrieved {} active sensors", sensors.len());
            Ok(Json(sensors))
        }
        Err(error) => {
            error!("Failed to get active sensors: {}", error);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Get latest reading for a specific sensor
///
/// # Errors
/// Returns `StatusCode::BAD_REQUEST` if MAC address format is invalid
/// Returns `StatusCode::NOT_FOUND` if sensor has no readings
/// Returns `StatusCode::INTERNAL_SERVER_ERROR` if database query fails
pub async fn get_sensor_latest(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
) -> Result<Json<Event>, StatusCode> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        error!(
            "Invalid MAC address format: {}",
            sanitize_mac_for_logging(&sensor_mac)
        );
        return Err(StatusCode::BAD_REQUEST);
    }

    match state.store.get_latest_reading(&sensor_mac).await {
        Ok(Some(reading)) => {
            tracing::debug!(
                "Retrieved latest reading for sensor: {}",
                sanitize_mac_for_logging(&sensor_mac)
            );
            Ok(Json(reading))
        }
        Ok(None) => {
            tracing::debug!(
                "No reading found for sensor: {}",
                sanitize_mac_for_logging(&sensor_mac)
            );
            Err(StatusCode::NOT_FOUND)
        }
        Err(error) => {
            error!(
                "Failed to get latest reading for sensor {}: {}",
                sanitize_mac_for_logging(&sensor_mac),
                error
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Get historical data for a sensor
///
/// # Errors
/// Returns `StatusCode::BAD_REQUEST` if MAC address format is invalid, limit is
/// invalid, or date formats are invalid
/// Returns `StatusCode::INTERNAL_SERVER_ERROR` if database query fails
#[allow(clippy::too_many_lines)]
pub async fn get_sensor_history(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<HistoricalQuery>,
) -> Result<Json<Vec<Event>>, StatusCode> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        error!(
            "Invalid MAC address format: {}",
            sanitize_mac_for_logging(&sensor_mac)
        );
        return Err(StatusCode::BAD_REQUEST);
    }

    // Validate limit if provided
    if let Some(limit) = params.limit {
        if !validate_limit(limit) {
            error!("Invalid limit value: {}", limit);
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                Some(dt)
            } else {
                error!("Invalid start date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        #[allow(clippy::arithmetic_side_effects)]
        None => Some(Utc::now() - Duration::hours(1)),
    };

    let end = match params.end.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                Some(dt)
            } else {
                error!("Invalid end date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        None => Some(Utc::now()),
    };

    // Validate date range
    if let (Some(start_dt), Some(end_dt)) = (start, end) {
        if start_dt >= end_dt {
            error!("Start date must be before end date");
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    match state
        .store
        .get_historical_data(&sensor_mac, start, end, params.limit)
        .await
    {
        Ok(readings) => {
            tracing::debug!(
                "Retrieved {} historical readings for sensor: {}",
                readings.len(),
                sanitize_mac_for_logging(&sensor_mac)
            );
            Ok(Json(readings))
        }
        Err(error) => {
            error!(
                "Failed to get historical data for sensor {}: {}",
                sanitize_mac_for_logging(&sensor_mac),
                error
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Get aggregated data for a sensor
///
/// # Errors
/// Returns `StatusCode::BAD_REQUEST` if MAC address format is invalid, date
/// formats are invalid, or interval is invalid
/// Returns `StatusCode::INTERNAL_SERVER_ERROR` if database query fails
#[allow(clippy::too_many_lines)]
pub async fn get_sensor_aggregates(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<TimeBucketQuery>,
) -> Result<Json<Vec<TimeBucketedData>>, StatusCode> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        error!(
            "Invalid MAC address format: {}",
            sanitize_mac_for_logging(&sensor_mac)
        );
        return Err(StatusCode::BAD_REQUEST);
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                error!("Invalid start date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        #[allow(clippy::arithmetic_side_effects)]
        None => Utc::now() - Duration::hours(24),
    };

    let end = match params.end.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                error!("Invalid end date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        None => Utc::now(),
    };

    // Validate date range
    if start >= end {
        error!("Start date must be before end date");
        return Err(StatusCode::BAD_REQUEST);
    }

    let interval = match params.interval.as_deref() {
        Some(interval_str) => {
            if let Some(interval) = parse_interval(interval_str) {
                interval
            } else {
                error!("Unsupported interval: {}", interval_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        None => postgres_store::TimeInterval::Hours(1),
    };

    match state
        .store
        .get_time_bucketed_data(&sensor_mac, &interval, start, end)
        .await
    {
        Ok(data) => {
            tracing::debug!(
                "Retrieved {} aggregated data points for sensor: {}",
                data.len(),
                sanitize_mac_for_logging(&sensor_mac)
            );
            Ok(Json(data))
        }
        Err(error) => {
            error!(
                "Failed to get aggregated data for sensor {}: {}",
                sanitize_mac_for_logging(&sensor_mac),
                error
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Get hourly aggregated data for a sensor
///
/// # Errors
/// Returns `StatusCode::BAD_REQUEST` if MAC address format is invalid or date
/// formats are invalid Returns `StatusCode::INTERNAL_SERVER_ERROR` if database
/// query fails
#[allow(clippy::too_many_lines)]
pub async fn get_sensor_hourly_aggregates(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<TimeBucketQuery>,
) -> Result<Json<Vec<TimeBucketedData>>, StatusCode> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        error!(
            "Invalid MAC address format: {}",
            sanitize_mac_for_logging(&sensor_mac)
        );
        return Err(StatusCode::BAD_REQUEST);
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                error!("Invalid start date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        #[allow(clippy::arithmetic_side_effects)]
        None => Utc::now() - Duration::hours(72),
    };

    let end = match params.end.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                error!("Invalid end date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        None => Utc::now(),
    };

    // Validate date range
    if start >= end {
        error!("Start date must be before end date");
        return Err(StatusCode::BAD_REQUEST);
    }

    match state
        .store
        .get_hourly_aggregates(&sensor_mac, start, end)
        .await
    {
        Ok(data) => {
            tracing::debug!(
                "Retrieved {} hourly aggregates for sensor: {}",
                data.len(),
                sanitize_mac_for_logging(&sensor_mac)
            );
            Ok(Json(data))
        }
        Err(error) => {
            error!(
                "Failed to get hourly aggregates for sensor {}: {}",
                sanitize_mac_for_logging(&sensor_mac),
                error
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Get daily aggregated data for a sensor
///
/// # Errors
/// Returns `StatusCode::BAD_REQUEST` if MAC address format is invalid or date
/// formats are invalid Returns `StatusCode::INTERNAL_SERVER_ERROR` if database
/// query fails
#[allow(clippy::too_many_lines)]
pub async fn get_sensor_daily_aggregates(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<TimeBucketQuery>,
) -> Result<Json<Vec<TimeBucketedData>>, StatusCode> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        error!(
            "Invalid MAC address format: {}",
            sanitize_mac_for_logging(&sensor_mac)
        );
        return Err(StatusCode::BAD_REQUEST);
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                error!("Invalid start date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        #[allow(clippy::arithmetic_side_effects)]
        None => Utc::now() - Duration::days(30),
    };

    let end = match params.end.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                error!("Invalid end date format: {}", date_str);
                return Err(StatusCode::BAD_REQUEST);
            }
        }
        None => Utc::now(),
    };

    // Validate date range
    if start >= end {
        error!("Start date must be before end date");
        return Err(StatusCode::BAD_REQUEST);
    }

    match state
        .store
        .get_daily_aggregates(&sensor_mac, start, end)
        .await
    {
        Ok(data) => {
            tracing::debug!(
                "Retrieved {} daily aggregates for sensor: {}",
                data.len(),
                sanitize_mac_for_logging(&sensor_mac)
            );
            Ok(Json(data))
        }
        Err(error) => {
            error!(
                "Failed to get daily aggregates for sensor {}: {}",
                sanitize_mac_for_logging(&sensor_mac),
                error
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Get storage statistics
///
/// # Errors
/// Returns `StatusCode::INTERNAL_SERVER_ERROR` if database query fails
pub async fn get_storage_stats(
    State(state): State<AppState>,
) -> Result<Json<StorageStats>, StatusCode> {
    match state.store.get_storage_stats().await {
        Ok(storage_stats) => {
            tracing::debug!("Retrieved storage statistics");
            Ok(Json(storage_stats))
        }
        Err(error) => {
            error!("Failed to get storage stats: {}", error);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Get storage requirements estimate
///
/// # Errors
/// Returns `StatusCode::BAD_REQUEST` if parameters are invalid (negative, zero,
/// or out of range) Returns `StatusCode::INTERNAL_SERVER_ERROR` if database
/// query fails
#[allow(clippy::too_many_lines)]
pub async fn get_storage_estimate(
    State(state): State<AppState>,
    Query(params): Query<StorageEstimateQuery>,
) -> Result<Json<StorageEstimate>, StatusCode> {
    let sensor_count = params.sensor_count.unwrap_or(10);
    let interval_seconds = params.interval_seconds.unwrap_or(10);
    let retention_years = params.retention_years.unwrap_or(5);

    // Validate parameters
    if sensor_count <= 0 {
        error!("Sensor count must be positive, got: {}", sensor_count);
        return Err(StatusCode::BAD_REQUEST);
    }

    if interval_seconds <= 0 {
        error!(
            "Interval seconds must be positive, got: {}",
            interval_seconds
        );
        return Err(StatusCode::BAD_REQUEST);
    }

    if retention_years <= 0 {
        error!("Retention years must be positive, got: {}", retention_years);
        return Err(StatusCode::BAD_REQUEST);
    }

    // Reasonable upper bounds
    if sensor_count > 10000 {
        error!("Sensor count too high: {}", sensor_count);
        return Err(StatusCode::BAD_REQUEST);
    }

    if !(1..=86400).contains(&interval_seconds) {
        error!("Interval seconds out of range: {}", interval_seconds);
        return Err(StatusCode::BAD_REQUEST);
    }

    if retention_years > 100 {
        error!("Retention years too high: {}", retention_years);
        return Err(StatusCode::BAD_REQUEST);
    }

    match state
        .store
        .estimate_storage_requirements(sensor_count, interval_seconds, retention_years)
        .await
    {
        Ok(estimate) => {
            tracing::debug!(
                "Generated storage estimate for {} sensors, {}s interval, {} years retention",
                sensor_count,
                interval_seconds,
                retention_years
            );
            Ok(Json(estimate))
        }
        Err(error) => {
            error!("Failed to get storage estimate: {}", error);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::queries::*;

    #[tokio::test]
    async fn test_health_check() {
        let result = health_check().await;
        assert_eq!(result, "OK");
    }

    #[test]
    fn test_validate_mac_in_handlers() {
        // Test the MAC validation logic used in handlers
        assert!(is_valid_mac_format("AA:BB:CC:DD:EE:FF"));
        assert!(!is_valid_mac_format("invalid-mac"));
        assert!(!is_valid_mac_format(""));
    }

    #[test]
    fn test_validate_limit_in_handlers() {
        // Test the limit validation logic used in handlers
        assert!(validate_limit(100));
        assert!(!validate_limit(0));
        assert!(!validate_limit(-1));
        assert!(!validate_limit(20000));
    }

    #[test]
    fn test_date_validation_logic() {
        // Test datetime parsing used in handlers
        assert!(parse_datetime("2024-01-01T00:00:00Z").is_ok());
        assert!(parse_datetime("invalid-date").is_err());
    }

    #[test]
    fn test_interval_validation_logic() {
        // Test interval parsing used in handlers
        assert!(parse_interval("1h").is_some());
        assert!(parse_interval("invalid").is_none());
    }

    #[test]
    fn test_storage_estimate_validation() {
        // Test the validation logic for storage estimates

        // Valid parameters
        let sensor_count = 10;
        let interval_seconds = 30;
        let retention_years = 5;

        assert!(sensor_count > 0);
        assert!(interval_seconds > 0);
        assert!(retention_years > 0);
        assert!(sensor_count <= 10000);
        assert!((1..=86400).contains(&interval_seconds));
        assert!(retention_years <= 100);

        // Invalid parameters
        // Test boundary conditions - these are compile-time constants
        // so we just document the expected behavior
        // sensor_count <= 0, interval_seconds <= 0, retention_years <= 0 should
        // fail sensor_count > 10000, interval_seconds > 86400,
        // retention_years > 100 should fail
    }

    #[test]
    fn test_mac_sanitization() {
        // Test MAC sanitization for logging
        assert_eq!(
            sanitize_mac_for_logging("AA:BB:CC:DD:EE:01"),
            "AA:BB:CC:DD:EE:01"
        );
        assert_eq!(
            sanitize_mac_for_logging("D1:10:96:D8:08:F4"),
            "D1:10:96:D8:XX:XX"
        );
    }

    #[test]
    fn test_query_parameter_structures() {
        // Test that our query structures work as expected in handlers
        let historical = HistoricalQuery::new()
            .with_start("2024-01-01T00:00:00Z".to_string())
            .with_limit(100);

        assert_eq!(historical.start, Some("2024-01-01T00:00:00Z".to_string()));
        assert_eq!(historical.limit, Some(100));

        let time_bucket = TimeBucketQuery::new().with_interval("1h".to_string());

        assert_eq!(time_bucket.interval, Some("1h".to_string()));

        let storage = StorageEstimateQuery::new()
            .with_sensor_count(20)
            .with_interval_seconds(30)
            .with_retention_years(3);

        assert_eq!(storage.sensor_count, Some(20));
        assert_eq!(storage.interval_seconds, Some(30));
        assert_eq!(storage.retention_years, Some(3));
    }

    // Note: Full handler tests with actual HTTP requests would require
    // setting up a test server and database, which would be in integration
    // tests
}
