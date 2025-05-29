use crate::env::{
    from_env,
    try_from_env,
};
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
    pub fn new(
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
