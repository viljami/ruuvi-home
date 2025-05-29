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
}
