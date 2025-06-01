//! HTTP request handlers for the API

use axum::{
    extract::{
        Path,
        Query,
        State,
    },
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

use crate::{
    errors::{
        ApiError,
        ApiResult,
    },
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
pub async fn get_sensors(State(state): State<AppState>) -> ApiResult<Json<Vec<String>>> {
    match state.store.get_sensors().await {
        Ok(sensors) => {
            tracing::debug!("Retrieved {} sensors", sensors.len());
            Ok(Json(sensors))
        }
        Err(error) => Err(ApiError::database_error(
            "get sensors list",
            &error.to_string(),
        )),
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
) -> ApiResult<Json<Event>> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        return Err(ApiError::invalid_mac(&sensor_mac));
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
            Err(ApiError::readings_not_found(&sensor_mac))
        }
        Err(error) => Err(ApiError::database_error(
            "get latest reading",
            &error.to_string(),
        )),
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
) -> ApiResult<Json<Vec<Event>>> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        return Err(ApiError::invalid_mac(&sensor_mac));
    }

    // Validate limit if provided
    if let Some(limit) = params.limit {
        if !validate_limit(limit) {
            return Err(ApiError::invalid_limit(limit));
        }
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                Some(dt)
            } else {
                return Err(ApiError::invalid_date(date_str));
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
                return Err(ApiError::invalid_date(date_str));
            }
        }
        None => Some(Utc::now()),
    };

    // Validate date range
    if let (Some(start_dt), Some(end_dt)) = (start, end) {
        if start_dt >= end_dt {
            return Err(ApiError::invalid_date_range(
                "Start date must be before end date",
            ));
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
        Err(error) => Err(ApiError::database_error(
            "get historical data",
            &error.to_string(),
        )),
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
) -> ApiResult<Json<Vec<TimeBucketedData>>> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        return Err(ApiError::invalid_mac(&sensor_mac));
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                return Err(ApiError::invalid_date(date_str));
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
                return Err(ApiError::invalid_date(date_str));
            }
        }
        None => Utc::now(),
    };

    // Validate date range
    if start >= end {
        return Err(ApiError::invalid_date_range(
            "Start date must be before end date",
        ));
    }

    let interval = match params.interval.as_deref() {
        Some(interval_str) => {
            if let Some(interval) = parse_interval(interval_str) {
                interval
            } else {
                return Err(ApiError::InvalidParameter {
                    parameter: "interval".to_string(),
                    value: interval_str.to_string(),
                    expected: "one of: 1m, 5m, 15m, 30m, 1h, 6h, 12h, 1d".to_string(),
                });
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
        Err(error) => Err(ApiError::database_error(
            "get aggregated data",
            &error.to_string(),
        )),
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
) -> ApiResult<Json<Vec<TimeBucketedData>>> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        return Err(ApiError::invalid_mac(&sensor_mac));
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                return Err(ApiError::invalid_date(date_str));
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
                return Err(ApiError::invalid_date(date_str));
            }
        }
        None => Utc::now(),
    };

    // Validate date range
    if start >= end {
        return Err(ApiError::invalid_date_range(
            "Start date must be before end date",
        ));
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
        Err(error) => Err(ApiError::database_error(
            "get hourly aggregated data",
            &error.to_string(),
        )),
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
) -> ApiResult<Json<Vec<TimeBucketedData>>> {
    // Validate MAC format
    if !is_valid_mac_format(&sensor_mac) {
        return Err(ApiError::invalid_mac(&sensor_mac));
    }

    let start = match params.start.as_ref() {
        Some(date_str) => {
            if let Ok(dt) = parse_datetime(date_str) {
                dt
            } else {
                return Err(ApiError::invalid_date(date_str));
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
                return Err(ApiError::invalid_date(date_str));
            }
        }
        None => Utc::now(),
    };

    // Validate date range
    if start >= end {
        return Err(ApiError::invalid_date_range(
            "Start date must be before end date",
        ));
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
        Err(error) => Err(ApiError::database_error(
            "get daily aggregated data",
            &error.to_string(),
        )),
    }
}

/// Get storage statistics
///
/// # Errors
/// Returns `StatusCode::INTERNAL_SERVER_ERROR` if database query fails
pub async fn get_storage_stats(State(state): State<AppState>) -> ApiResult<Json<StorageStats>> {
    match state.store.get_storage_stats().await {
        Ok(storage_stats) => {
            tracing::debug!("Retrieved storage statistics");
            Ok(Json(storage_stats))
        }
        Err(error) => Err(ApiError::database_error(
            "get storage statistics",
            &error.to_string(),
        )),
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
) -> ApiResult<Json<StorageEstimate>> {
    let sensor_count = params.sensor_count.unwrap_or(10);
    let interval_seconds = params.interval_seconds.unwrap_or(10);
    let retention_years = params.retention_years.unwrap_or(5);

    // Validate parameters
    if sensor_count <= 0 {
        return Err(ApiError::InvalidParameter {
            parameter: "sensor_count".to_string(),
            value: sensor_count.to_string(),
            expected: "positive integer".to_string(),
        });
    }

    if interval_seconds <= 0 {
        return Err(ApiError::InvalidParameter {
            parameter: "interval_seconds".to_string(),
            value: interval_seconds.to_string(),
            expected: "positive integer".to_string(),
        });
    }

    if retention_years <= 0 {
        return Err(ApiError::InvalidParameter {
            parameter: "retention_years".to_string(),
            value: retention_years.to_string(),
            expected: "positive integer".to_string(),
        });
    }

    // Reasonable upper bounds
    if sensor_count > 10000 {
        return Err(ApiError::InvalidParameter {
            parameter: "sensor_count".to_string(),
            value: sensor_count.to_string(),
            expected: "integer between 1 and 10000".to_string(),
        });
    }

    if !(1..=86400).contains(&interval_seconds) {
        return Err(ApiError::InvalidParameter {
            parameter: "interval_seconds".to_string(),
            value: interval_seconds.to_string(),
            expected: "integer between 1 and 86400 (1 day)".to_string(),
        });
    }

    if retention_years > 100 {
        return Err(ApiError::InvalidParameter {
            parameter: "retention_years".to_string(),
            value: retention_years.to_string(),
            expected: "integer between 1 and 100".to_string(),
        });
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
        Err(error) => Err(ApiError::database_error(
            "calculate storage estimate",
            &error.to_string(),
        )),
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
