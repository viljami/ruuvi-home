use futures::Stream;
use postgres_store::Event;
use chrono::{DateTime, Utc};
use rumqttc::Incoming;
use ruuvi_decoder::{
    Decoder,
    SensorData,
};
use tracing::error;

use super::ruuvi_gateway_message::RuuviGatewayMessage;

#[derive(Debug)]
pub struct DecodedMessage {
    pub message: RuuviGatewayMessage,
    pub sensor_data: ruuvi_decoder::SensorData5,
}

impl Into<Event> for DecodedMessage {
    fn into(self) -> Event {
        let timestamp = DateTime::from_timestamp(i64::from(self.message.ts), 0)
            .unwrap_or_else(Utc::now);
            
        Event {
            sensor_mac: self.sensor_data.mac,
            gateway_mac: self.message.gw_mac,
            temperature: f64::from(self.sensor_data.temperature),
            humidity: f64::from(self.sensor_data.humidity.unwrap_or(0.0)),
            pressure: f64::from(self.sensor_data.pressure.unwrap_or(0.0)),
            battery: i64::from(self.sensor_data.battery.unwrap_or(0)),
            tx_power: i64::from(self.sensor_data.tx_power.unwrap_or(0)),
            movement_counter: i64::from(self.sensor_data.movement_counter),
            measurement_sequence_number: i64::from(self.sensor_data.measurement_sequence_number),
            acceleration: f64::from(self.sensor_data.acceleration),
            acceleration_x: i64::from(self.sensor_data.acceleration_x),
            acceleration_y: i64::from(self.sensor_data.acceleration_y),
            acceleration_z: i64::from(self.sensor_data.acceleration_z),
            rssi: i64::from(self.sensor_data.rssi.unwrap_or(0)),
            timestamp,
        }
    }
}

pub fn to_stream(
    mut eventloop: rumqttc::EventLoop,
    decoder: ruuvi_decoder::Df5Decoder,
) -> impl Stream<Item = DecodedMessage> {
    async_stream::stream! {
        while let Ok(notification) = eventloop.poll().await {
            if let rumqttc::Event::Incoming(Incoming::Publish(packet)) = notification {
                match RuuviGatewayMessage::try_from(packet.payload.as_ref()) {
                    Ok(message) => {
                        let sensor_data = match decoder.decode_data(&message.data) {
                            Ok(SensorData::Df5(measure)) => measure,
                            Err(error) => {
                                error!("Error decoding data attr: {error}");
                                continue;
                            }
                        };

                        let decoded_message = DecodedMessage {
                            message,
                            sensor_data,
                        };

                        yield decoded_message;
                    }
                    Err(error) => error!("Error parsing message: {error}"),
                }
            }
        }
    }
}
