use serde::{
    Deserialize,
    Serialize,
};

#[derive(Debug, Deserialize, Serialize)]
pub struct RuuviGatewayMessage {
    pub gw_mac: String, // gateway mac
    pub rssi: i16,      // signal strength
    // pub aoa: Vec<i16>,
    pub gwts: u32,      // gateway timestamp
    pub ts: u32,        // timestamp
    pub data: String,   // sensor data
    pub coords: String, // coordinates
}

impl TryFrom<&[u8]> for RuuviGatewayMessage {
    type Error = serde_json::Error;

    fn try_from(value: &[u8]) -> Result<Self, Self::Error> {
        serde_json::from_slice(value)
    }
}
