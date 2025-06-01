// Enforce strict error handling in application code, but allow expect/unwrap in
// tests
#![cfg_attr(not(test), deny(clippy::expect_used, clippy::unwrap_used))]
#![cfg_attr(not(test), deny(clippy::panic))]

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

impl Event {
    /// Create a new Event with all fields specified
    #[allow(clippy::too_many_arguments)]
    pub const fn new(
        sensor_mac: String,
        gateway_mac: String,
        temperature: f64,
        humidity: f64,
        pressure: f64,
        battery: i64,
        tx_power: i64,
        movement_counter: i64,
        measurement_sequence_number: i64,
        acceleration: f64,
        acceleration_x: i64,
        acceleration_y: i64,
        acceleration_z: i64,
        rssi: i64,
        timestamp: i64,
    ) -> Self {
        Self {
            sensor_mac,
            gateway_mac,
            temperature,
            humidity,
            pressure,
            battery,
            tx_power,
            movement_counter,
            measurement_sequence_number,
            acceleration,
            acceleration_x,
            acceleration_y,
            acceleration_z,
            rssi,
            timestamp,
        }
    }

    /// Create a new Event with current timestamp
    #[allow(clippy::too_many_arguments)]
    pub fn new_with_current_timestamp(
        sensor_mac: String,
        gateway_mac: String,
        temperature: f64,
        humidity: f64,
        pressure: f64,
        battery: i64,
        tx_power: i64,
        movement_counter: i64,
        measurement_sequence_number: i64,
        acceleration: f64,
        acceleration_x: i64,
        acceleration_y: i64,
        acceleration_z: i64,
        rssi: i64,
    ) -> Self {
        use std::time::{
            SystemTime,
            UNIX_EPOCH,
        };

        #[allow(clippy::cast_possible_wrap)]
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        Self::new(
            sensor_mac,
            gateway_mac,
            temperature,
            humidity,
            pressure,
            battery,
            tx_power,
            movement_counter,
            measurement_sequence_number,
            acceleration,
            acceleration_x,
            acceleration_y,
            acceleration_z,
            rssi,
            timestamp,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const EPSILON: f64 = 1e-10;

    #[allow(clippy::many_single_char_names)]
    fn assert_float_eq(actual: f64, expected: f64) {
        assert!(
            (actual - expected).abs() < EPSILON,
            "Expected {actual} to equal {expected}"
        );
    }

    fn create_test_event() -> Event {
        Event::new(
            "AA:BB:CC:DD:EE:01".to_string(),
            "FF:FF:FF:FF:FF:01".to_string(),
            22.5,
            65.0,
            1013.25,
            3000,
            4,
            10,
            1,
            1.0,
            -16,
            -20,
            1044,
            -40,
            1_640_995_200,
        )
    }

    #[test]
    fn test_event_new() {
        let event = create_test_event();

        assert_eq!(event.sensor_mac, "AA:BB:CC:DD:EE:01");
        assert_eq!(event.gateway_mac, "FF:FF:FF:FF:FF:01");
        assert_float_eq(event.temperature, 22.5);
        assert_float_eq(event.humidity, 65.0);
        assert_float_eq(event.pressure, 1013.25);
        assert_eq!(event.battery, 3000);
        assert_eq!(event.tx_power, 4);
        assert_eq!(event.movement_counter, 10);
        assert_eq!(event.measurement_sequence_number, 1);
        assert_float_eq(event.acceleration, 1.0);
        assert_eq!(event.acceleration_x, -16);
        assert_eq!(event.acceleration_y, -20);
        assert_eq!(event.acceleration_z, 1044);
        assert_eq!(event.rssi, -40);
        assert_eq!(event.timestamp, 1_640_995_200);
    }

    #[test]
    fn test_event_default() {
        let event = Event::default();

        assert_eq!(event.sensor_mac, "");
        assert_eq!(event.gateway_mac, "");
        assert_float_eq(event.temperature, 0.0);
        assert_float_eq(event.humidity, 0.0);
        assert_float_eq(event.pressure, 0.0);
        assert_eq!(event.battery, 0);
        assert_eq!(event.tx_power, 0);
        assert_eq!(event.movement_counter, 0);
        assert_eq!(event.measurement_sequence_number, 0);
        assert_float_eq(event.acceleration, 0.0);
        assert_eq!(event.acceleration_x, 0);
        assert_eq!(event.acceleration_y, 0);
        assert_eq!(event.acceleration_z, 0);
        assert_eq!(event.rssi, 0);
        assert_eq!(event.timestamp, 0);
    }

    #[test]
    fn test_event_new_with_current_timestamp() {
        #[allow(clippy::cast_possible_wrap)]
        let before = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        let event = Event::new_with_current_timestamp(
            "AA:BB:CC:DD:EE:01".to_string(),
            "FF:FF:FF:FF:FF:01".to_string(),
            22.5,
            65.0,
            1013.25,
            3000,
            4,
            10,
            1,
            1.0,
            -16,
            -20,
            1044,
            -40,
        );

        #[allow(clippy::cast_possible_wrap)]
        let after = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        assert!(event.timestamp >= before);
        assert!(event.timestamp <= after);
        assert_eq!(event.sensor_mac, "AA:BB:CC:DD:EE:01");
        assert_float_eq(event.temperature, 22.5);
    }

    #[test]
    fn test_event_serialization() {
        let event = create_test_event();

        // Test JSON serialization
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("AA:BB:CC:DD:EE:01"));
        assert!(json.contains("22.5"));
        assert!(json.contains("1640995200"));

        // Test JSON deserialization
        let deserialized: Event = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.sensor_mac, event.sensor_mac);
        assert_float_eq(deserialized.temperature, event.temperature);
        assert_eq!(deserialized.timestamp, event.timestamp);
    }

    #[test]
    fn test_event_debug() {
        let event = create_test_event();
        let debug_str = format!("{event:?}");

        assert!(debug_str.contains("Event"));
        assert!(debug_str.contains("sensor_mac"));
        assert!(debug_str.contains("AA:BB:CC:DD:EE:01"));
        assert!(debug_str.contains("temperature"));
        assert!(debug_str.contains("22.5"));
    }

    #[test]
    fn test_event_edge_cases() {
        // Test with extreme values
        let event = Event::new(
            String::new(), // Empty MAC
            "FF:FF:FF:FF:FF:FF".to_string(),
            -273.15,  // Absolute zero
            0.0,      // Zero humidity
            0.0,      // Zero pressure
            0,        // Zero battery
            i64::MIN, // Minimum tx_power
            i64::MAX, // Maximum movement_counter
            0,
            f64::INFINITY, // Infinite acceleration
            i64::MIN,
            i64::MAX,
            0,
            i64::MIN,
            0,
        );

        assert_eq!(event.sensor_mac, "");
        assert_float_eq(event.temperature, -273.15);
        assert!(event.acceleration.is_infinite() && event.acceleration.is_sign_positive());
        assert_eq!(event.tx_power, i64::MIN);
        assert_eq!(event.movement_counter, i64::MAX);
    }

    #[test]
    fn test_event_field_modification() {
        let mut event = Event {
            sensor_mac: "NEW:MAC:ADDRESS".to_string(),
            temperature: 25.0,
            timestamp: 1_234_567_890,
            ..Default::default()
        };

        assert_eq!(event.sensor_mac, "NEW:MAC:ADDRESS");
        assert_float_eq(event.temperature, 25.0);
        assert_eq!(event.timestamp, 1_234_567_890);

        // Test modification after creation
        event.humidity = 60.0;
        assert_float_eq(event.humidity, 60.0);
    }

    #[test]
    fn test_event_realistic_values() {
        // Test with realistic sensor values
        let event = Event::new(
            "D1:10:96:D8:08:F4".to_string(), // Real-looking MAC (but sanitized)
            "AA:BB:CC:DD:EE:FF".to_string(), // Gateway MAC
            23.4,                            // Room temperature
            45.2,                            // Moderate humidity
            1013.25,                         // Standard atmospheric pressure
            2800,                            // Battery level in mV
            4,                               // TX power
            5,                               // Movement counter
            100,                             // Measurement sequence
            0.98,                            // Acceleration
            10,                              // X acceleration
            -5,                              // Y acceleration
            1000,                            // Z acceleration (gravity)
            -45,                             // RSSI
            1_640_995_200,                   // Unix timestamp
        );

        // Verify all values are within expected ranges
        assert!(event.temperature > -50.0 && event.temperature < 100.0);
        assert!(event.humidity >= 0.0 && event.humidity <= 100.0);
        assert!(event.pressure > 800.0 && event.pressure < 1200.0);
        assert!(event.battery >= 0 && event.battery <= 5000);
        assert!(event.rssi >= -120 && event.rssi <= 0);
    }

    #[test]
    fn test_event_json_roundtrip() {
        let original = create_test_event();

        // Serialize to JSON
        let json = serde_json::to_string(&original).unwrap();

        // Deserialize from JSON
        let restored: Event = serde_json::from_str(&json).unwrap();

        // Verify all fields match
        assert_eq!(original.sensor_mac, restored.sensor_mac);
        assert_eq!(original.gateway_mac, restored.gateway_mac);
        assert_float_eq(original.temperature, restored.temperature);
        assert_float_eq(original.humidity, restored.humidity);
        assert_float_eq(original.pressure, restored.pressure);
        assert_eq!(original.battery, restored.battery);
        assert_eq!(original.tx_power, restored.tx_power);
        assert_eq!(original.movement_counter, restored.movement_counter);
        assert_eq!(
            original.measurement_sequence_number,
            restored.measurement_sequence_number
        );
        assert_float_eq(original.acceleration, restored.acceleration);
        assert_eq!(original.acceleration_x, restored.acceleration_x);
        assert_eq!(original.acceleration_y, restored.acceleration_y);
        assert_eq!(original.acceleration_z, restored.acceleration_z);
        assert_eq!(original.rssi, restored.rssi);
        assert_eq!(original.timestamp, restored.timestamp);
    }

    #[test]
    fn test_event_mac_address_formats() {
        let mac_formats = vec![
            "AA:BB:CC:DD:EE:FF",
            "aa:bb:cc:dd:ee:ff",
            "12:34:56:78:9A:BC",
            "FF:FF:FF:FF:FF:FF",
        ];

        for mac in mac_formats {
            let event = Event::new(
                mac.to_string(),
                "GW:GW:GW:GW:GW:GW".to_string(),
                20.0,
                50.0,
                1000.0,
                3000,
                4,
                0,
                0,
                1.0,
                0,
                0,
                1000,
                -50,
                1_640_995_200,
            );
            assert_eq!(event.sensor_mac, mac);
        }
    }
}
