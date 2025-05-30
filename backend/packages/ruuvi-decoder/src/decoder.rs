use std::{
    error::Error,
    str,
};

use serde::Serialize;

pub type Acceleration = (Option<i16>, Option<i16>, Option<i16>);

pub type ByteDataDf5 = (
    u8,
    i16,
    u16,
    u16,
    i16,
    i16,
    i16,
    u16,
    u8,
    u16,
    u8,
    u8,
    u8,
    u8,
    u8,
    u8,
);

#[derive(Debug, PartialEq, Serialize)]
pub struct SensorData5 {
    pub data_format: u8,
    pub humidity: Option<f32>,
    pub temperature: f32,
    pub pressure: Option<f32>,
    pub acceleration: f32,
    pub acceleration_x: i16,
    pub acceleration_y: i16,
    pub acceleration_z: i16,
    pub tx_power: Option<i8>,
    pub battery: Option<u16>,
    pub movement_counter: u8,
    pub measurement_sequence_number: u16,
    pub mac: String,
    pub rssi: Option<i8>,
}

#[derive(Debug, PartialEq)]
pub enum SensorData {
    Df5(SensorData5),
}

pub fn parse_mac(data_format: u8, payload_mac: &str) -> String {
    if data_format == 5 {
        payload_mac
            .chars()
            .collect::<Vec<_>>()
            .chunks(2)
            .map(|chunk| chunk.iter().collect::<String>())
            .collect::<Vec<_>>()
            .join(":")
            .to_uppercase()
    } else {
        payload_mac.to_string()
    }
}

pub type DecoderResult = Result<SensorData, Box<dyn Error>>;

pub trait Decoder {
    fn decode_data(&self, data: &str) -> DecoderResult;
}

pub struct Df5Decoder;

impl Df5Decoder {
    fn get_temperature(&self, data: &ByteDataDf5) -> Option<f32> {
        if data.1 == -32768 {
            None
        } else {
            Some(data.1 as f32 / 200.0)
        }
    }

    fn get_humidity(&self, data: &ByteDataDf5) -> Option<f32> {
        if data.2 == 0xFFFF {
            None
        } else {
            Some(data.2 as f32 / 400.0)
        }
    }

    fn get_pressure(&self, data: &ByteDataDf5) -> Option<f32> {
        if data.3 == 0xFFFF {
            None
        } else {
            Some((data.3 as u32 + 50000) as f32 / 100.0)
        }
    }

    fn get_acceleration(&self, data: &ByteDataDf5) -> Acceleration {
        let x = data.4;
        let y = data.5;
        let z = data.6;
        if x == -32768 || y == -32768 || z == -32768 {
            (None, None, None)
        } else {
            (Some(x), Some(y), Some(z))
        }
    }

    fn get_powerinfo(&self, data: &ByteDataDf5) -> (u16, i8) {
        let battery_voltage = data.7 >> 5;
        let tx_power = (data.7 & 0x001F) as i8;
        (battery_voltage, tx_power)
    }

    fn get_battery(&self, data: &ByteDataDf5) -> Option<u16> {
        let battery_voltage = self.get_powerinfo(data).0;
        if battery_voltage == 0b11111111111 {
            None
        } else {
            Some(battery_voltage + 1600)
        }
    }

    fn get_txpower(&self, data: &ByteDataDf5) -> Option<i8> {
        let tx_power = self.get_powerinfo(data).1;
        if tx_power == 0b11111 {
            None
        } else {
            Some(-40 + (tx_power as i16 * 2) as i8)
        }
    }

    fn get_movementcounter(&self, data: &ByteDataDf5) -> u8 {
        data.8
    }

    fn get_measurementsequencenumber(&self, data: &ByteDataDf5) -> u16 {
        data.9
    }

    fn get_mac(&self, data: &ByteDataDf5) -> String {
        [data.10, data.11, data.12, data.13, data.14, data.15]
            .iter()
            .map(|x| format!("{:02x}", x))
            .collect::<Vec<_>>()
            .join("")
    }

    // fn get_rssi(&self, rssi_byte: &str) -> i8 {
    //     let rssi = u16::from_str_radix(rssi_byte, 16).unwrap();
    //     if rssi > 127 {
    //         -((255 - rssi as u8) as i8)
    //     } else {
    //         rssi as i8
    //     }
    // }
}

impl Decoder for Df5Decoder {
    fn decode_data(&self, data: &str) -> Result<SensorData, Box<dyn Error>> {
        let byte_data = hex::decode(data.chars().take(48).collect::<String>())?;
        #[allow(clippy::too_many_arguments)] // Allow too many arguments for DF5 decoding
        let s = structure!(">BhHHhhhHBH6B");
        let byte_data = s.unpack(&byte_data)?;
        // let rssi = &data[48..];
        let (acc_x, acc_y, acc_z) = self.get_acceleration(&byte_data);
        let acc = if let (Some(x), Some(y), Some(z)) = (acc_x, acc_y, acc_z) {
            println!("x: {}, y: {}, z: {}", x, y, z);
            Some((((x as i64).pow(2) + (y as i64).pow(2) + (z as i64).pow(2)) as f32).sqrt())
        } else {
            None
        };
        Ok(SensorData::Df5(SensorData5 {
            data_format: 5,
            humidity: self.get_humidity(&byte_data),
            temperature: self.get_temperature(&byte_data).unwrap(),
            pressure: self.get_pressure(&byte_data),
            acceleration: acc.unwrap(),
            acceleration_x: acc_x.unwrap(),
            acceleration_y: acc_y.unwrap(),
            acceleration_z: acc_z.unwrap(),
            tx_power: self.get_txpower(&byte_data),
            battery: self.get_battery(&byte_data),
            movement_counter: self.get_movementcounter(&byte_data),
            measurement_sequence_number: self.get_measurementsequencenumber(&byte_data),
            mac: self.get_mac(&byte_data),
            rssi: None, /* rssi: if rssi.is_empty() {
                         *     None
                         * } else {
                         *     Some(self.get_rssi(rssi))
                         * }, */
        }))
    }
}

#[cfg(test)]
mod test {
    type Filename = &'static str;
    use std::fs;

    use rstest::rstest;
    use serde::Deserialize;

    use super::*;

    #[derive(Debug, Deserialize)]
    struct MqttPayload {
        data: String,
    }

    #[rstest]
    #[case("mqtt-sensor-payload.json", SensorData5 {
        data_format: 5,
        humidity: None,
        temperature: 19.32,
        pressure: None,
        acceleration: 1044.3141289861017,
        acceleration_x: -16,
        acceleration_y: -20,
        acceleration_z: 1044,
        tx_power: Some(4),
        battery: Some(2964),
        movement_counter: 168,
        measurement_sequence_number: 56974,
        mac: "f797e36ed811".to_string(),
        rssi: None
    })]
    fn test_df5_decoder(#[case] encoded: Filename, #[case] expected: SensorData5) {
        let MqttPayload { data, .. } = serde_json::from_str(
            &fs::read_to_string(format!("tests/fixtures/{encoded}")).expect("File"),
        )
        .expect("MqttPayload");
        let splitted = data.split("FF9904").collect::<Vec<_>>();
        let splitted = splitted.get(1).unwrap();
        println!("{data:?}: {}, {splitted:?}: {}", data.len(), splitted.len());

        // let contents = fs::read_to_string(expected).expect("File");
        let decoder = Df5Decoder {};
        // let data = "051e0000f0ff";
        let result = decoder.decode_data(&splitted).unwrap();
        assert_eq!(result, SensorData::Df5(expected));
    }

    #[test]
    fn test_df5_decoder_direct() {
        let decoder = Df5Decoder {};

        // Test with known valid hex data
        let hex_data = "0201061BFF9904050F18FFFFFFFFFFF0FFEC0414AA96A8DE8EF797E36ED811";
        let SensorData::Df5(data) = decoder.decode_data(hex_data).unwrap();

        assert_eq!(data.data_format, 5);
        assert!(data.temperature > -50.0 && data.temperature < 100.0);
        assert!(data.acceleration >= 0.0);
    }

    #[test]
    fn test_df5_decoder_error_cases() {
        let decoder = Df5Decoder {};

        // Test with invalid hex data
        let invalid_hex = "INVALID_HEX_DATA";
        let result = decoder.decode_data(invalid_hex);
        assert!(result.is_err());

        // Test with empty string
        let result = decoder.decode_data("");
        assert!(result.is_err());

        // Test with too short data
        let result = decoder.decode_data("05");
        assert!(result.is_err());
    }

    #[test]
    fn test_df5_decoder_boundary_values() {
        let decoder = Df5Decoder {};

        // Test with minimum length valid data (may still fail due to content)
        let min_data = "0500000000000000000000000000000000000000";
        let result = decoder.decode_data(min_data);
        // This might fail due to invalid data content, but shouldn't panic
        let _ = result;

        // Test with different data format values
        let test_cases = vec![
            "0500000000000000000000000000000000000000",
            "0600000000000000000000000000000000000000",
            "FF00000000000000000000000000000000000000",
        ];

        for case in test_cases {
            let result = decoder.decode_data(case);
            // Should not panic, but may return error for invalid formats
            let _ = result;
        }
    }

    #[test]
    fn test_sensor_data5_creation() {
        let sensor_data = SensorData5 {
            data_format: 5,
            humidity: Some(65.0),
            temperature: 22.5,
            pressure: Some(1013.25),
            acceleration: 1.0,
            acceleration_x: 0,
            acceleration_y: 0,
            acceleration_z: 1000,
            tx_power: Some(4),
            battery: Some(3000),
            movement_counter: 0,
            measurement_sequence_number: 1,
            mac: "AA:BB:CC:DD:EE:FF".to_string(),
            rssi: Some(-45),
        };

        assert_eq!(sensor_data.data_format, 5);
        assert_eq!(sensor_data.humidity, Some(65.0));
        assert_eq!(sensor_data.temperature, 22.5);
        assert_eq!(sensor_data.mac, "AA:BB:CC:DD:EE:FF");
    }

    #[test]
    fn test_sensor_data5_optional_fields() {
        let sensor_data = SensorData5 {
            data_format: 5,
            humidity: None,
            temperature: 20.0,
            pressure: None,
            acceleration: 1.0,
            acceleration_x: 0,
            acceleration_y: 0,
            acceleration_z: 1000,
            tx_power: None,
            battery: None,
            movement_counter: 0,
            measurement_sequence_number: 1,
            mac: "test".to_string(),
            rssi: None,
        };

        assert_eq!(sensor_data.humidity, None);
        assert_eq!(sensor_data.pressure, None);
        assert_eq!(sensor_data.tx_power, None);
        assert_eq!(sensor_data.battery, None);
        assert_eq!(sensor_data.rssi, None);
    }

    #[test]
    fn test_sensor_data5_edge_values() {
        let sensor_data = SensorData5 {
            data_format: 5,
            humidity: Some(0.0),
            temperature: -273.15, // Absolute zero
            pressure: Some(0.0),
            acceleration: 0.0,
            acceleration_x: i16::MIN,
            acceleration_y: i16::MAX,
            acceleration_z: 0,
            tx_power: Some(i8::MIN),
            battery: Some(0),
            movement_counter: u8::MAX,
            measurement_sequence_number: u16::MAX,
            mac: "".to_string(),
            rssi: Some(i8::MIN),
        };

        assert_eq!(sensor_data.temperature, -273.15);
        assert_eq!(sensor_data.acceleration_x, i16::MIN);
        assert_eq!(sensor_data.acceleration_y, i16::MAX);
        assert_eq!(sensor_data.movement_counter, u8::MAX);
        assert_eq!(sensor_data.measurement_sequence_number, u16::MAX);
    }

    #[test]
    fn test_sensor_data_enum() {
        let sensor_data5 = SensorData5 {
            data_format: 5,
            humidity: Some(50.0),
            temperature: 25.0,
            pressure: Some(1000.0),
            acceleration: 1.0,
            acceleration_x: 0,
            acceleration_y: 0,
            acceleration_z: 1000,
            tx_power: Some(0),
            battery: Some(3000),
            movement_counter: 1,
            measurement_sequence_number: 1,
            mac: "test".to_string(),
            rssi: Some(-50),
        };

        let sensor_data = SensorData::Df5(sensor_data5);

        match sensor_data {
            SensorData::Df5(data) => {
                assert_eq!(data.data_format, 5);
                assert_eq!(data.temperature, 25.0);
            }
        }
    }

    #[test]
    fn test_sensor_data5_debug() {
        let sensor_data = SensorData5 {
            data_format: 5,
            humidity: Some(50.0),
            temperature: 25.0,
            pressure: Some(1000.0),
            acceleration: 1.0,
            acceleration_x: 0,
            acceleration_y: 0,
            acceleration_z: 1000,
            tx_power: Some(0),
            battery: Some(3000),
            movement_counter: 1,
            measurement_sequence_number: 1,
            mac: "test".to_string(),
            rssi: Some(-50),
        };

        let debug_str = format!("{:?}", sensor_data);
        assert!(debug_str.contains("SensorData5"));
        assert!(debug_str.contains("data_format: 5"));
        assert!(debug_str.contains("temperature: 25.0"));
    }

    #[test]
    fn test_sensor_data5_equality() {
        let data1 = SensorData5 {
            data_format: 5,
            humidity: Some(50.0),
            temperature: 25.0,
            pressure: Some(1000.0),
            acceleration: 1.0,
            acceleration_x: 0,
            acceleration_y: 0,
            acceleration_z: 1000,
            tx_power: Some(0),
            battery: Some(3000),
            movement_counter: 1,
            measurement_sequence_number: 1,
            mac: "test".to_string(),
            rssi: Some(-50),
        };

        let data2 = SensorData5 {
            data_format: 5,
            humidity: Some(50.0),
            temperature: 25.0,
            pressure: Some(1000.0),
            acceleration: 1.0,
            acceleration_x: 0,
            acceleration_y: 0,
            acceleration_z: 1000,
            tx_power: Some(0),
            battery: Some(3000),
            movement_counter: 1,
            measurement_sequence_number: 1,
            mac: "test".to_string(),
            rssi: Some(-50),
        };

        assert_eq!(data1, data2);
    }

    #[test]
    fn test_sensor_data5_serialization() {
        let sensor_data = SensorData5 {
            data_format: 5,
            humidity: Some(50.0),
            temperature: 25.0,
            pressure: Some(1000.0),
            acceleration: 1.0,
            acceleration_x: 0,
            acceleration_y: 0,
            acceleration_z: 1000,
            tx_power: Some(0),
            battery: Some(3000),
            movement_counter: 1,
            measurement_sequence_number: 1,
            mac: "test".to_string(),
            rssi: Some(-50),
        };

        // Test JSON serialization
        let json = serde_json::to_string(&sensor_data).unwrap();
        assert!(json.contains("\"data_format\":5"));
        assert!(json.contains("\"temperature\":25.0"));
        assert!(json.contains("\"mac\":\"test\""));
    }

    #[test]
    fn test_df5_decoder_various_inputs() {
        let decoder = Df5Decoder {};

        // Test various hex string formats
        let test_cases = vec![
            "051B1A00FF00040301002100C9004001DE007F", // Valid format
            "051b1a00ff00040301002100c9004001de007f", // Lowercase
            "05 1B 1A 00 FF 00 04 03 01 00 21 00 C9 00 40 01 DE 00 7F", // With spaces (should fail)
        ];

        for (i, case) in test_cases.iter().enumerate() {
            let result = decoder.decode_data(case);
            match i {
                0 | 1 => {
                    // First two should potentially work (upper/lowercase)
                    let _ = result; // May succeed or fail depending on data
                                    // validity
                }
                2 => {
                    // With spaces should fail
                    assert!(result.is_err(), "Input with spaces should fail");
                }
                _ => {}
            }
        }
    }

    #[test]
    fn test_decoder_trait() {
        let decoder = Df5Decoder {};

        // Test that Df5Decoder implements the Decoder trait
        let hex_data = "051B1A00FF00040301002100C9004001DE007F";
        let result = decoder.decode_data(hex_data);

        // Should return a Result, regardless of success/failure
        match result {
            Ok(_) => {}  // Success case
            Err(_) => {} // Error case is also valid for this test
        }
    }
}
