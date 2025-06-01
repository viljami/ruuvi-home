# Ruuvi MQTT Simulator

A development tool that simulates Ruuvi Gateway MQTT messages for local testing of the Ruuvi Home system.

## Overview

This simulator generates realistic Ruuvi Gateway MQTT messages that match the actual format used by Ruuvi Gateway devices. It's designed to help developers test the Ruuvi Home application without requiring physical hardware.

## Actual Message Format

The simulator produces messages in the exact format used by real Ruuvi Gateways:

```json
{
  "gw_mac": "AA:BB:CC:DD:EE:FF",
  "rssi": -62,
  "aoa": [],
  "gwts": 1728719836,
  "ts": 1728719836,
  "data": "0201061BFF9904050F18FFFFFFFFFFF0FFEC0414AA96A8DE8EF797E36ED811",
  "coords": ""
}
```

### Field Descriptions

- `gw_mac`: MAC address of the gateway
- `rssi`: Signal strength in dBm (typically -60 to -90)
- `aoa`: Array for angle of arrival data (usually empty)
- `gwts`: Gateway timestamp (Unix time in seconds)
- `ts`: Measurement timestamp (Unix time in seconds)
- `data`: Hex-encoded BLE advertisement data containing the sensor measurements
- `coords`: GPS coordinates (if available, usually empty)

### Data Format

The `data` field contains hex-encoded BLE advertisement data with the following structure:

1. `0201061BFF9904`: BLE advertisement header and Ruuvi manufacturer ID
2. `05`: Data format (Format 5)
3. Followed by the actual sensor data:
   - Temperature (2 bytes, signed integer, 0.005°C resolution)
   - Humidity (2 bytes, unsigned integer, 0.0025% resolution)
   - Pressure (2 bytes, unsigned integer, +50000 Pa offset)
   - Acceleration X/Y/Z (2 bytes each, signed integer, millig resolution)
   - Battery voltage and TX power (2 bytes)
   - Movement counter (1 byte)
   - Sequence number (1 byte)

## Configuration

The simulator can be configured using environment variables. This is the recommended approach for security and portability:

| Variable | Description | Default |
|----------|-------------|---------|
| `MQTT_BROKER` | MQTT broker hostname | `mosquitto` |
| `MQTT_PORT` | MQTT broker port | `1883` |
| `MQTT_TOPIC` | Topic to publish data to | `ruuvi/gateway/data` |
| `PUBLISH_INTERVAL` | Seconds between updates | `5.0` |
| `NUM_SENSORS` | Number of sensor messages to simulate | `3` |
| `GATEWAY_MAC` | Gateway MAC address to use | `AA:BB:CC:DD:EE:FF` |

### Security Note

Always use environment variables for any sensitive or configuration-specific values. The default values provided are intentionally bogus or generic and should be overridden in your environment with appropriate values.

## Usage with Docker Compose

The simulator is automatically started as part of the docker-compose configuration. To use it:

1. Start the entire stack with `docker-compose up`
2. The simulator will connect to the Mosquitto broker and start publishing data
3. Monitor the messages using the included `mqtt-listener.py` script:
   ```
   cd scripts
   ./mqtt-listener.py
   ```

## Standalone Usage

To run the simulator directly:

```bash
# Install dependencies
pip install -r requirements.txt

# Run the simulator with default values
python simulator.py

# Run with custom environment variables
MQTT_BROKER=localhost MQTT_PORT=1883 GATEWAY_MAC=AA:BB:CC:DD:EE:FF python simulator.py
```

## Testing

The simulator includes comprehensive tests to ensure the generated messages match the expected format:

```bash
# Run tests
python -m pytest tests/ -v

# Run tests with coverage
python -m pytest tests/ -v --cov=simulator --cov-report=term
```

The tests use bogus MAC addresses and other placeholder values to avoid exposing any sensitive information.

You can also use the Docker test setup:

```bash
# From the project root
docker-compose -f docker-compose-test.yaml up mqtt-simulator-tests
```

## Python Virtual Environment

We recommend using a virtual environment for development:

```bash
# Set up the virtual environment
./setup-venv.sh

# Activate the environment
source ./activate-venv.sh
```
