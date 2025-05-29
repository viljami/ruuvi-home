use std::time::Duration;

use config::Config;
use futures::Stream;
use mqtt_stream::{
    to_stream,
    DecodedMessage,
};
use rumqttc::{
    AsyncClient,
    MqttOptions,
    QoS,
};

pub mod config;
pub mod mqtt_stream;
pub mod ruuvi_gateway_message;

/// # Errors
/// This function can fail if the MQTT client fails to connect or subscribe to
/// the topic, or if `InfluxDB` connection fails.
pub async fn create(
    config: Config,
) -> Result<impl Stream<Item = DecodedMessage>, Box<dyn std::error::Error>> {
    let mut mqttoptions = MqttOptions::new("rumqtt-async", config.mqtt_host, config.mqtt_port);
    mqttoptions.set_keep_alive(Duration::from_secs(60));

    // Set credentials only if both username and password are provided
    if let (Some(username), Some(password)) = (config.mqtt_username, config.mqtt_password) {
        mqttoptions.set_credentials(username, password);
    }

    let (client, eventloop) = AsyncClient::new(mqttoptions, 10);
    client.subscribe(config.mqtt_topic, QoS::AtMostOnce).await?;

    let decoder = ruuvi_decoder::Df5Decoder;

    Ok(to_stream(eventloop, decoder))
}
