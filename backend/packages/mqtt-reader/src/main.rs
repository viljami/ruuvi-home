// Enforce strict error handling in application code, but allow expect/unwrap in
// tests
#![cfg_attr(not(test), deny(clippy::expect_used, clippy::unwrap_used))]
#![cfg_attr(not(test), deny(clippy::panic))]

use std::pin::pin;

use futures::StreamExt;
use mqtt_reader::{
    read::{
        self,
    },
    write::{
        self,
    },
};
use tracing::{
    error,
    info,
};

type AppResult = Result<(), Box<dyn std::error::Error>>;

#[tokio::main]
async fn main() -> AppResult {
    tracing_subscriber::fmt::init();

    let read_config = read::config::Config::from_env();

    info!(
        "Connecting to MQTT broker at {}:{} with topic: {}",
        read_config.mqtt_host, read_config.mqtt_port, read_config.mqtt_topic
    );

    let write_config = write::config::Config::from_env();

    info!(
        "PostgreSQL configuration - Database URL: {}",
        write_config.database_url
    );

    let stream = read::create(read_config).await?;
    let mut stream = pin!(stream);

    info!("Successfully connected to MQTT broker. Waiting for messages...");

    let postgres_writer = write::create(write_config).await?;

    while let Some(decoded_message) = stream.next().await {
        if let Err(err) = postgres_writer
            .write_sensor_data(vec![decoded_message.into()])
            .await
        {
            error!("Failed to write to PostgreSQL: {err}");
        }
    }

    Ok(())
}
