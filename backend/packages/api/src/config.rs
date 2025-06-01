//! Configuration management for the API server

use anyhow::Result;

#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub api_port: u16,
}

impl Config {
    /// Create a new Config from environment variables
    ///
    /// # Errors
    /// Returns an error if the `API_PORT` environment variable cannot be parsed
    /// as a valid u16
    pub fn from_env() -> Result<Self> {
        Self::from_env_vars(
            std::env::var("DATABASE_URL").ok(),
            std::env::var("API_PORT").ok(),
        )
    }

    /// Create a new Config with explicit values (mainly for testing)
    pub const fn new(database_url: String, api_port: u16) -> Self {
        Self {
            database_url,
            api_port,
        }
    }

    /// Create a Config from optional environment variable values (for testing)
    fn from_env_vars(database_url: Option<String>, api_port: Option<String>) -> Result<Self> {
        Ok(Self {
            database_url: database_url.unwrap_or_else(|| {
                "postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home".to_string()
            }),
            api_port: api_port.unwrap_or_else(|| "8080".to_string()).parse()?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_new() {
        let config = Config::new("postgres://test".to_string(), 3000);
        assert_eq!(config.database_url, "postgres://test");
        assert_eq!(config.api_port, 3000);
    }

    #[test]
    fn test_config_from_env_defaults() {
        // Clear environment variables to test defaults
        std::env::remove_var("DATABASE_URL");
        std::env::remove_var("API_PORT");

        #[allow(clippy::expect_used)]
        let config = Config::from_env().expect("Should create config from env");
        assert!(config
            .database_url
            .contains("postgresql://ruuvi:ruuvi_secret"));
        assert_eq!(config.api_port, 8080);
    }

    #[test]
    fn test_config_invalid_port() {
        // Test invalid port using the internal function (no global env interference)
        let result = Config::from_env_vars(None, Some("invalid".to_string()));
        assert!(result.is_err());
    }

    #[test]
    fn test_config_edge_cases() {
        // Test empty string for port
        let result = Config::from_env_vars(None, Some(String::new()));
        assert!(result.is_err());

        // Test port too high (u16::MAX is 65535)
        let result = Config::from_env_vars(None, Some("70000".to_string()));
        assert!(
            result.is_err(),
            "Port 70000 should fail (u16::MAX is 65535)"
        );

        // Test negative port
        let result = Config::from_env_vars(None, Some("-1".to_string()));
        assert!(result.is_err());
    }

    #[test]
    fn test_config_debug_output() {
        let config = Config::new("test://db".to_string(), 1234);
        let debug_str = format!("{config:?}");
        assert!(debug_str.contains("test://db"));
        assert!(debug_str.contains("1234"));
    }
}
