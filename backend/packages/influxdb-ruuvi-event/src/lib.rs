use influxdb2::FromDataPoint;
use influxdb2_derive::WriteDataPoint;
use serde::{
    Deserialize,
    Serialize,
};

#[derive(Debug, Default, FromDataPoint, WriteDataPoint, Serialize, Deserialize)]
#[measurement = "sensor"]
pub struct Event {
    #[influxdb(tag)]
    pub sensor_mac: String,
    #[influxdb(tag)]
    pub gateway_mac: String,
    #[influxdb(field)]
    pub temperature: f64,
    #[influxdb(field)]
    pub humidity: f64,
    #[influxdb(field)]
    pub pressure: f64,
    #[influxdb(field)]
    pub battery: i64,
    #[influxdb(field)]
    pub tx_power: i64,
    #[influxdb(field)]
    pub movement_counter: i64,
    #[influxdb(field)]
    pub measurement_sequence_number: i64,
    #[influxdb(field)]
    pub acceleration: f64,
    #[influxdb(field)]
    pub acceleration_x: i64,
    #[influxdb(field)]
    pub acceleration_y: i64,
    #[influxdb(field)]
    pub acceleration_z: i64,
    #[influxdb(field)]
    pub rssi: i64,
    #[influxdb(timestamp)]
    pub timestamp: i64,
}
