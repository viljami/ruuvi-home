use crate::env::from_env;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
}

impl Config {
    #[must_use]
    pub fn new(database_url: String) -> Self {
        Self { database_url }
    }

    /// # Panics
    #[must_use]
    pub fn from_env() -> Self {
        Self {
            database_url: from_env("DATABASE_URL"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_new() {
        let db_url = "postgresql://user:pass@localhost:5432/test_db".to_string();
        let config = Config::new(db_url.clone());

        assert_eq!(config.database_url, db_url);
    }

    #[test]
    fn test_config_new_with_different_urls() {
        let test_cases = vec![
            "postgresql://localhost/db",
            "postgresql://user@localhost/db",
            "postgresql://user:pass@localhost:5432/db",
            "postgresql://user:pass@127.0.0.1:5432/db?sslmode=require",
            "sqlite:///path/to/db.sqlite",
            "mysql://user:pass@localhost/db",
        ];

        for db_url in test_cases {
            let config = Config::new(db_url.to_string());
            assert_eq!(config.database_url, db_url);
        }
    }

    #[test]
    fn test_config_from_env() {
        // Save original value
        let original_db_url = std::env::var("DATABASE_URL").ok();

        // Set test value
        let test_url = "postgresql://test:test@localhost:5432/test_db";
        std::env::set_var("DATABASE_URL", test_url);

        let config = Config::from_env();
        assert_eq!(config.database_url, test_url);

        // Restore original value or remove if it wasn't set
        match original_db_url {
            Some(url) => std::env::set_var("DATABASE_URL", url),
            None => std::env::remove_var("DATABASE_URL"),
        }
    }

    #[test]
    fn test_config_clone() {
        let db_url = "postgresql://user:pass@localhost:5432/test_db".to_string();
        let config = Config::new(db_url.clone());
        let cloned = config.clone();

        assert_eq!(config.database_url, cloned.database_url);

        // Ensure they are separate instances
        assert_eq!(config.database_url, db_url);
        assert_eq!(cloned.database_url, db_url);
    }

    #[test]
    fn test_config_edge_cases() {
        // Test empty string
        let config = Config::new(String::new());
        assert_eq!(config.database_url, "");

        // Test string with special characters
        let special_url = "postgresql://user%40domain:p%40ss@host:5432/db%2Dname";
        let config = Config::new(special_url.to_string());
        assert_eq!(config.database_url, special_url);

        // Test very long URL
        let long_url = format!("postgresql://user:pass@{}/db", "a".repeat(100));
        let config = Config::new(long_url.clone());
        assert_eq!(config.database_url, long_url);
    }

    #[test]
    fn test_config_url_formats() {
        let test_urls = vec![
            // PostgreSQL variants
            "postgresql://localhost/db",
            "postgres://localhost/db",
            "postgresql://localhost:5432/db",
            "postgresql://user@localhost/db",
            "postgresql://user:pass@localhost/db",
            "postgresql://user:pass@localhost:5432/db",
            "postgresql://user:pass@localhost:5432/db?sslmode=require",
            // Other database types
            "sqlite:///absolute/path/to/db.sqlite",
            "sqlite://./relative/path/to/db.sqlite",
            "mysql://user:pass@localhost:3306/db",
            // URLs with special characters
            "postgresql://user%40domain:p%40ss@host:5432/db-name",
        ];

        for url in test_urls {
            let config = Config::new(url.to_string());
            assert_eq!(config.database_url, url);
        }
    }

    #[test]
    fn test_config_equality() {
        let url = "postgresql://user:pass@localhost:5432/db".to_string();
        let config1 = Config::new(url.clone());
        let config2 = Config::new(url.clone());

        // Manual equality check since we didn't derive PartialEq
        assert_eq!(config1.database_url, config2.database_url);
    }

    #[test]
    fn test_config_field_access() {
        let url = "postgresql://test@localhost/db".to_string();
        let config = Config::new(url.clone());

        // Test direct field access
        assert_eq!(config.database_url, url);

        // Test that we can modify through mut reference
        let mut mutable_config = Config::new("initial".to_string());
        mutable_config.database_url = url.clone();
        assert_eq!(mutable_config.database_url, url);
    }
}
