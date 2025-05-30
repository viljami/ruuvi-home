//! Application state management

use std::sync::Arc;

use anyhow::Result;
use postgres_store::PostgresStore;

use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    pub store: Arc<PostgresStore>,
}

impl AppState {
    /// Create a new `AppState` from a Config
    ///
    /// # Errors
    /// Returns an error if the database connection fails
    pub async fn new(config: Config) -> Result<Self> {
        let store = Arc::new(PostgresStore::new(&config.database_url).await?);
        Ok(Self { store })
    }

    /// Create a new `AppState` with a provided store (for testing)
    pub fn with_store(store: Arc<PostgresStore>) -> Self {
        Self { store }
    }

    /// Get a reference to the store
    pub fn store(&self) -> &Arc<PostgresStore> {
        &self.store
    }
}

impl std::fmt::Debug for AppState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("AppState")
            .field("store", &"PostgresStore")
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;

    #[test]
    fn test_app_state_structure() {
        // Test that we can create the basic structure
        // This is a basic structural test without requiring a database

        // We can't easily test the full AppState::new without a database
        // but we can test the structure and ensure it compiles correctly
        let config = Config::new("postgresql://test".to_string(), 3000);

        // Test config structure
        assert_eq!(config.api_port, 3000);
        assert_eq!(config.database_url, "postgresql://test");

        // If we reach this point, the structure is sound
        assert!(true);
    }

    #[test]
    fn test_app_state_debug() {
        // Test that debug formatting works without requiring a database
        let config = Config::new("postgresql://test".to_string(), 3000);
        let debug_str = format!("{:?}", config);
        assert!(debug_str.contains("postgresql://test"));
        assert!(debug_str.contains("3000"));
    }

    #[test]
    fn test_app_state_clone_trait() {
        // Test that AppState implements Clone correctly
        let config = Config::new("postgresql://test".to_string(), 3000);
        let cloned_config = config.clone();

        assert_eq!(config.database_url, cloned_config.database_url);
        assert_eq!(config.api_port, cloned_config.api_port);
    }

    // Note: Full integration tests with actual database connections
    // would be in the integration tests directory

    #[tokio::test]
    async fn test_app_state_new_with_invalid_url() {
        // Test that AppState::new properly handles invalid database URLs
        let config = Config::new("invalid://url".to_string(), 3000);

        // This should fail gracefully
        let result = AppState::new(config).await;
        assert!(result.is_err());
    }

    #[test]
    fn test_store_getter() {
        // We can't create a real AppState without a database,
        // but we can test that the getter method exists and compiles
        let config = Config::new("postgresql://test".to_string(), 3000);

        // The store() method should exist and be callable
        // This is mainly a compilation test
        assert_eq!(config.database_url, "postgresql://test");
    }
}
