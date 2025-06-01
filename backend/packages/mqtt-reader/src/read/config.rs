use crate::env::{
    from_env,
    try_from_env,
};

#[derive(Clone)]
#[allow(missing_debug_implementations)]
pub struct Config {
    pub mqtt_username: Option<String>,
    pub mqtt_password: Option<String>,
    pub mqtt_host: String,
    pub mqtt_port: u16,
    pub mqtt_topic: String,
    pub log_filepath: String,
}

impl Config {
    #[must_use]
    #[allow(clippy::too_many_arguments)] // Establish Config
    pub const fn new(
        mqtt_username: Option<String>,
        mqtt_password: Option<String>,
        mqtt_host: String,
        mqtt_port: u16,
        mqtt_topic: String,
        log_filepath: String,
    ) -> Self {
        Self {
            mqtt_username,
            mqtt_password,
            mqtt_host,
            mqtt_port,
            mqtt_topic,
            log_filepath,
        }
    }

    /// # Panics
    #[must_use]
    pub fn from_env() -> Self {
        Self {
            mqtt_username: try_from_env("MQTT_USERNAME"),
            mqtt_password: try_from_env("MQTT_PASSWORD"),
            mqtt_host: from_env("MQTT_HOST"),
            #[allow(clippy::expect_used)] // Break early if env var is not set
            mqtt_port: from_env("MQTT_PORT")
                .parse()
                .expect("Port must be a number"),
            mqtt_topic: from_env("MQTT_TOPIC"),
            log_filepath: try_from_env("LOG_FILEPATH").unwrap_or_else(|| "/tmp/mqtt-reader.log".to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_new() {
        let config = Config::new(
            Some("user".to_string()),
            Some("pass".to_string()),
            "localhost".to_string(),
            1883,
            "test/topic".to_string(),
            "/tmp/test.log".to_string(),
        );

        assert_eq!(config.mqtt_username, Some("user".to_string()));
        assert_eq!(config.mqtt_password, Some("pass".to_string()));
        assert_eq!(config.mqtt_host, "localhost");
        assert_eq!(config.mqtt_port, 1883);
        assert_eq!(config.mqtt_topic, "test/topic");
        assert_eq!(config.log_filepath, "/tmp/test.log");
    }

    #[test]
    fn test_config_new_no_auth() {
        let config = Config::new(
            None,
            None,
            "broker.example.com".to_string(),
            8883,
            "sensors/data".to_string(),
            "/var/log/mqtt.log".to_string(),
        );

        assert_eq!(config.mqtt_username, None);
        assert_eq!(config.mqtt_password, None);
        assert_eq!(config.mqtt_host, "broker.example.com");
        assert_eq!(config.mqtt_port, 8883);
        assert_eq!(config.mqtt_topic, "sensors/data");
        assert_eq!(config.log_filepath, "/var/log/mqtt.log");
    }

    #[test]
    fn test_config_from_env_with_auth() {
        // Set all environment variables
        std::env::set_var("MQTT_USERNAME", "testuser");
        std::env::set_var("MQTT_PASSWORD", "testpass");
        std::env::set_var("MQTT_HOST", "auth-host");
        std::env::set_var("MQTT_PORT", "8883");
        std::env::set_var("MQTT_TOPIC", "secure/topic");
        std::env::set_var("LOG_FILEPATH", "/custom/log/path.log");

        let config = Config::from_env();

        assert_eq!(config.mqtt_username, Some("testuser".to_string()));
        assert_eq!(config.mqtt_password, Some("testpass".to_string()));
        assert_eq!(config.mqtt_host, "auth-host");
        assert_eq!(config.mqtt_port, 8883);
        assert_eq!(config.mqtt_topic, "secure/topic");
        assert_eq!(config.log_filepath, "/custom/log/path.log");

        // Clean up
        std::env::remove_var("MQTT_USERNAME");
        std::env::remove_var("MQTT_PASSWORD");
        std::env::remove_var("MQTT_HOST");
        std::env::remove_var("MQTT_PORT");
        std::env::remove_var("MQTT_TOPIC");
        std::env::remove_var("LOG_FILEPATH");
    }

    #[test]
    fn test_config_edge_cases() {
        // Test empty strings
        let config = Config::new(
            Some(String::new()),
            Some(String::new()),
            String::new(),
            0,
            String::new(),
            String::new(),
        );

        assert_eq!(config.mqtt_username, Some(String::new()));
        assert_eq!(config.mqtt_password, Some(String::new()));
        assert_eq!(config.mqtt_host, "");
        assert_eq!(config.mqtt_port, 0);
        assert_eq!(config.mqtt_topic, "");
        assert_eq!(config.log_filepath, "");
    }

    #[test]
    fn test_config_port_ranges() {
        // Test minimum port
        let config = Config::new(
            None,
            None,
            "localhost".to_string(),
            1,
            "topic".to_string(),
            "/tmp/test.log".to_string(),
        );
        assert_eq!(config.mqtt_port, 1);

        // Test maximum port
        let config = Config::new(
            None,
            None,
            "localhost".to_string(),
            65535,
            "topic".to_string(),
            "/tmp/test.log".to_string(),
        );
        assert_eq!(config.mqtt_port, 65535);
    }

    #[test]
    fn test_config_clone() {
        let config = Config::new(
            Some("user".to_string()),
            Some("pass".to_string()),
            "localhost".to_string(),
            1883,
            "test/topic".to_string(),
            "/tmp/test.log".to_string(),
        );

        let cloned = config.clone();

        assert_eq!(config.mqtt_username, cloned.mqtt_username);
        assert_eq!(config.mqtt_password, cloned.mqtt_password);
        assert_eq!(config.mqtt_host, cloned.mqtt_host);
        assert_eq!(config.mqtt_port, cloned.mqtt_port);
        assert_eq!(config.mqtt_topic, cloned.mqtt_topic);
        assert_eq!(config.log_filepath, cloned.log_filepath);
    }

    #[test]
    fn test_config_partial_auth() {
        // Test with only username, no password
        let config = Config::new(
            Some("user".to_string()),
            None,
            "localhost".to_string(),
            1883,
            "test/topic".to_string(),
            "/tmp/test.log".to_string(),
        );

        assert_eq!(config.mqtt_username, Some("user".to_string()));
        assert_eq!(config.mqtt_password, None);

        // Test with only password, no username
        let config = Config::new(
            None,
            Some("pass".to_string()),
            "localhost".to_string(),
            1883,
            "test/topic".to_string(),
            "/tmp/test.log".to_string(),
        );

        assert_eq!(config.mqtt_username, None);
        assert_eq!(config.mqtt_password, Some("pass".to_string()));
    }
}
