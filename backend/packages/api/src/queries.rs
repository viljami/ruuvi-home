//! Query parameter structures for API endpoints

use serde::Deserialize;

#[derive(Debug, Deserialize, PartialEq)]
pub struct HistoricalQuery {
    pub start: Option<String>,
    pub end: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize, PartialEq)]
pub struct TimeBucketQuery {
    pub start: Option<String>,
    pub end: Option<String>,
    pub interval: Option<String>,
}

#[derive(Debug, Deserialize, PartialEq)]
pub struct StorageEstimateQuery {
    pub sensor_count: Option<i32>,
    pub interval_seconds: Option<i32>,
    pub retention_years: Option<i32>,
}

impl HistoricalQuery {
    pub const fn new() -> Self {
        Self {
            start: None,
            end: None,
            limit: None,
        }
    }

    #[must_use]
    pub fn with_start(mut self, start: String) -> Self {
        self.start = Some(start);
        self
    }

    #[must_use]
    pub fn with_end(mut self, end: String) -> Self {
        self.end = Some(end);
        self
    }

    #[must_use]
    pub const fn with_limit(mut self, limit: i64) -> Self {
        self.limit = Some(limit);
        self
    }
}

impl Default for HistoricalQuery {
    fn default() -> Self {
        Self::new()
    }
}

impl TimeBucketQuery {
    pub const fn new() -> Self {
        Self {
            start: None,
            end: None,
            interval: None,
        }
    }

    #[must_use]
    pub fn with_start(mut self, start: String) -> Self {
        self.start = Some(start);
        self
    }

    #[must_use]
    pub fn with_end(mut self, end: String) -> Self {
        self.end = Some(end);
        self
    }

    #[must_use]
    pub fn with_interval(mut self, interval: String) -> Self {
        self.interval = Some(interval);
        self
    }
}

impl Default for TimeBucketQuery {
    fn default() -> Self {
        Self::new()
    }
}

impl StorageEstimateQuery {
    pub const fn new() -> Self {
        Self {
            sensor_count: None,
            interval_seconds: None,
            retention_years: None,
        }
    }

    #[must_use]
    pub const fn with_sensor_count(mut self, count: i32) -> Self {
        self.sensor_count = Some(count);
        self
    }

    #[must_use]
    pub const fn with_interval_seconds(mut self, seconds: i32) -> Self {
        self.interval_seconds = Some(seconds);
        self
    }

    #[must_use]
    pub const fn with_retention_years(mut self, years: i32) -> Self {
        self.retention_years = Some(years);
        self
    }
}

impl Default for StorageEstimateQuery {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_historical_query_builder() {
        let query = HistoricalQuery::new()
            .with_start("2024-01-01T00:00:00Z".to_string())
            .with_end("2024-01-02T00:00:00Z".to_string())
            .with_limit(100);

        assert_eq!(query.start, Some("2024-01-01T00:00:00Z".to_string()));
        assert_eq!(query.end, Some("2024-01-02T00:00:00Z".to_string()));
        assert_eq!(query.limit, Some(100));
    }

    #[test]
    fn test_historical_query_partial() {
        let query = HistoricalQuery::new().with_limit(50);

        assert_eq!(query.start, None);
        assert_eq!(query.end, None);
        assert_eq!(query.limit, Some(50));
    }

    #[test]
    fn test_time_bucket_query_builder() {
        let query = TimeBucketQuery::new()
            .with_start("2024-01-01T00:00:00Z".to_string())
            .with_end("2024-01-02T00:00:00Z".to_string())
            .with_interval("1h".to_string());

        assert_eq!(query.start, Some("2024-01-01T00:00:00Z".to_string()));
        assert_eq!(query.end, Some("2024-01-02T00:00:00Z".to_string()));
        assert_eq!(query.interval, Some("1h".to_string()));
    }

    #[test]
    fn test_time_bucket_query_interval_only() {
        let query = TimeBucketQuery::new().with_interval("15m".to_string());

        assert_eq!(query.start, None);
        assert_eq!(query.end, None);
        assert_eq!(query.interval, Some("15m".to_string()));
    }

    #[test]
    fn test_storage_estimate_query_builder() {
        let query = StorageEstimateQuery::new()
            .with_sensor_count(20)
            .with_interval_seconds(30)
            .with_retention_years(3);

        assert_eq!(query.sensor_count, Some(20));
        assert_eq!(query.interval_seconds, Some(30));
        assert_eq!(query.retention_years, Some(3));
    }

    #[test]
    fn test_storage_estimate_query_partial() {
        let query = StorageEstimateQuery::new().with_sensor_count(5);

        assert_eq!(query.sensor_count, Some(5));
        assert_eq!(query.interval_seconds, None);
        assert_eq!(query.retention_years, None);
    }

    #[test]
    fn test_query_defaults() {
        let historical = HistoricalQuery::default();
        assert_eq!(historical.start, None);
        assert_eq!(historical.end, None);
        assert_eq!(historical.limit, None);

        let time_bucket = TimeBucketQuery::default();
        assert_eq!(time_bucket.start, None);
        assert_eq!(time_bucket.end, None);
        assert_eq!(time_bucket.interval, None);

        let storage = StorageEstimateQuery::default();
        assert_eq!(storage.sensor_count, None);
        assert_eq!(storage.interval_seconds, None);
        assert_eq!(storage.retention_years, None);
    }

    #[test]
    fn test_query_equality() {
        let query1 = HistoricalQuery::new().with_limit(100);
        let query2 = HistoricalQuery::new().with_limit(100);
        let query3 = HistoricalQuery::new().with_limit(200);

        assert_eq!(query1, query2);
        assert_ne!(query1, query3);
    }

    #[test]
    fn test_debug_output() {
        let query = HistoricalQuery::new()
            .with_start("2024-01-01T00:00:00Z".to_string())
            .with_limit(100);

        let debug_str = format!("{query:?}");
        assert!(debug_str.contains("2024-01-01T00:00:00Z"));
        assert!(debug_str.contains("100"));
    }

    #[test]
    fn test_serde_deserialization() {
        // Test that serde can deserialize our query structs
        let json = r#"{"start": "2024-01-01T00:00:00Z", "limit": 100}"#;
        #[allow(clippy::expect_used)]
        let query: HistoricalQuery = serde_json::from_str(json).expect("json");

        assert_eq!(query.start, Some("2024-01-01T00:00:00Z".to_string()));
        assert_eq!(query.limit, Some(100));
        assert_eq!(query.end, None);
    }

    #[test]
    fn test_edge_cases() {
        // Test negative values
        let storage_query = StorageEstimateQuery::new().with_sensor_count(-1);
        assert_eq!(storage_query.sensor_count, Some(-1));

        // Test zero values
        let historical_query = HistoricalQuery::new().with_limit(0);
        assert_eq!(historical_query.limit, Some(0));

        // Test empty strings
        let time_bucket_query = TimeBucketQuery::new().with_interval(String::new());
        assert_eq!(time_bucket_query.interval, Some(String::new()));
    }
}
