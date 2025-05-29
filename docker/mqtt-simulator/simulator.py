#!/usr/bin/env python3

import json
import time
import random
import os
import logging

import paho.mqtt.client as mqtt
import struct

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("ruuvi-simulator")

# Configuration with environment variable fallbacks
MQTT_BROKER = os.environ.get("MQTT_BROKER", "mosquitto")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
MQTT_TOPIC = os.environ.get("MQTT_TOPIC", "ruuvi/gateway/data")
PUBLISH_INTERVAL = float(os.environ.get("PUBLISH_INTERVAL", 5.0))
NUM_SENSORS = int(os.environ.get("NUM_SENSORS", 3))

# Example Ruuvi Tag MAC addresses (fixed for simulation consistency)
SENSOR_MACS = [
    "C6:99:AB:11:22:33",
    "C6:99:AB:44:55:66", 
    "C6:99:AB:77:88:99",
    "C6:99:AB:AA:BB:CC",
    "C6:99:AB:DD:EE:FF"
][:NUM_SENSORS]  # Take only the number we need

# Gateway MAC address (bogus default for open source publication)
GATEWAY_MAC = os.environ.get("GATEWAY_MAC", "AA:BB:CC:DD:EE:FF")

# Global client for testing access
client = None

def create_ruuvi_data_hex(temp, humidity, pressure, accel_x, accel_y, accel_z, battery_voltage, sensor_mac):
    """
    Create hex-encoded Ruuvi Data Format 5 payload compatible with ruuvitag-sensor decoder
    
    Uses the exact format expected by ruuvitag-sensor: ">BhHHhhhHBH6B"

    Args:
        temp (float): Temperature in Celsius
        humidity (float): Relative humidity percentage  
        pressure (float): Pressure in Pascals
        accel_x (float): X-axis acceleration in G
        accel_y (float): Y-axis acceleration in G
        accel_z (float): Z-axis acceleration in G
        battery_voltage (float): Battery voltage in Volts
        sensor_mac (str): MAC address of the sensor

    Returns:
        str: Hex encoded 24-byte data payload string
    """
    # Data format identifier
    data_format = 5
    
    # Temperature (signed short, multiply by 200 for 0.005°C resolution)
    temp_raw = int(round(temp * 200))
    temp_raw = max(-32767, min(32767, temp_raw))  # Clamp to valid range
    
    # Humidity (unsigned short, multiply by 400 for 0.0025% resolution)
    humidity_raw = int(round(humidity * 400))
    humidity_raw = max(0, min(65534, humidity_raw))  # Clamp to valid range, 65535 = invalid
    
    # Pressure (unsigned short, subtract 50000 Pa offset)
    pressure_raw = int(round(pressure)) - 50000
    pressure_raw = max(0, min(65534, pressure_raw))  # Clamp to valid range, 65535 = invalid
    
    # Acceleration X, Y, Z (signed shorts, convert G to mG)
    accel_x_raw = int(round(accel_x * 1000))
    accel_y_raw = int(round(accel_y * 1000))
    accel_z_raw = int(round(accel_z * 1000))
    
    # Clamp acceleration values
    accel_x_raw = max(-32767, min(32767, accel_x_raw))
    accel_y_raw = max(-32767, min(32767, accel_y_raw))
    accel_z_raw = max(-32767, min(32767, accel_z_raw))
    
    # Power info (unsigned short): battery voltage (11 bits) + TX power (5 bits)
    tx_power = 4  # 4 dBm
    tx_power_raw = (tx_power + 40) // 2  # Convert to raw value (offset -40dBm, 2dBm steps)
    battery_mv = int(round(battery_voltage * 1000))
    battery_raw = battery_mv - 1600  # Offset -1600mV
    battery_raw = max(0, min(2047, battery_raw))  # 11 bits max
    tx_power_raw = max(0, min(31, tx_power_raw))  # 5 bits max
    power_info = (battery_raw << 5) | tx_power_raw
    
    # Movement counter (unsigned byte)
    movement_counter = random.randint(0, 254)  # 255 = invalid
    
    # Measurement sequence number (unsigned short)
    sequence_number = random.randint(0, 65534)  # 65535 = invalid
    
    # MAC address (6 bytes)
    mac_bytes = bytes.fromhex(sensor_mac.replace(':', ''))
    
    # Pack data using the exact format expected by ruuvitag-sensor decoder
    # Format: ">BhHHhhhHBH6B" 
    data = struct.pack(">BhHHhhhHBH6s",
                      data_format,
                      temp_raw,
                      humidity_raw, 
                      pressure_raw,
                      accel_x_raw,
                      accel_y_raw,
                      accel_z_raw,
                      power_info,
                      movement_counter,
                      sequence_number,
                      mac_bytes)
    
    return data.hex().upper()

def generate_ruuvi_gateway_message(sensor_mac):
    """
    Generate a Ruuvi Gateway MQTT message in the actual format for a specific sensor

    Args:
        sensor_mac (str): MAC address of the sensor to simulate

    Returns:
        dict: Gateway message in the format from actual Ruuvi Gateway
    """
    # Generate current unix timestamp
    current_time = int(time.time())

    # Generate realistic but randomized sensor values with some sensor-specific variation
    # Use MAC address as seed for consistent but different readings per sensor
    sensor_seed = hash(sensor_mac) % 1000
    random.seed(sensor_seed + int(current_time / 10))  # Change seed every 10 seconds
    
    temperature = 21.0 + random.uniform(-5.0, 5.0)
    humidity = 50.0 + random.uniform(-10.0, 10.0)
    pressure = 101325 + random.uniform(-1000, 1000)
    accel_x = random.uniform(-0.1, 0.1)
    accel_y = random.uniform(-0.1, 0.1)
    accel_z = 1.0 + random.uniform(-0.1, 0.1)
    battery = 2.9 + random.uniform(0, 0.6)

    # Reset random seed to global state
    random.seed()

    # Create the manufacturer-specific data payload (24 bytes)
    payload_hex = create_ruuvi_data_hex(
        temperature, humidity, pressure, accel_x, accel_y, accel_z, battery, sensor_mac
    )
    
    # Wrap in BLE advertisement format for gateway message
    # Format expected by ruuvitag-sensor: length-prefixed chunks
    # Flags chunk: 02 01 06 (length=2, type=1, data=6)
    flags_chunk = "020106"
    
    # Manufacturer data chunk: length + FF + 9904 + payload
    # Length = 1 (for FF) + 2 (for 9904) + payload_length
    payload_bytes = len(payload_hex) // 2
    manufacturer_data_length = 1 + 2 + payload_bytes  # FF + 9904 + payload
    manufacturer_chunk = f"{manufacturer_data_length:02X}FF9904{payload_hex}"
    
    data_hex = flags_chunk + manufacturer_chunk

    # Create the gateway message
    gateway_message = {
        "gw_mac": GATEWAY_MAC,
        "rssi": -60 - random.randint(0, 30),  # RSSI between -60 and -90 dBm
        "aoa": [],
        "gwts": current_time,
        "ts": current_time,
        "data": data_hex,
        "coords": ""
    }

    return gateway_message

def on_connect(client, userdata, flags, rc):
    """
    Callback for when the client connects to the MQTT broker
    """
    if rc == 0:
        logger.info(f"Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
    else:
        logger.error(f"Failed to connect to MQTT broker, return code: {rc}")

def main():
    """
    Main function to run the simulator
    """
    global client

    logger.info("Starting Ruuvi Gateway MQTT Simulator")
    logger.info(f"MQTT Broker: {MQTT_BROKER}:{MQTT_PORT}")
    logger.info(f"MQTT Topic: {MQTT_TOPIC}")
    logger.info(f"Publishing interval: {PUBLISH_INTERVAL} seconds")
    logger.info(f"Number of sensors: {NUM_SENSORS}")
    logger.info(f"Gateway MAC: {GATEWAY_MAC}")
    logger.info(f"Sensor MACs: {', '.join(SENSOR_MACS)}")

    # Set up MQTT client
    client = mqtt.Client()
    client.on_connect = on_connect

    # Connect to broker
    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
        client.loop_start()

        # Main loop - publish one message for each sensor with consistent MACs
        while True:
            for sensor_mac in SENSOR_MACS:
                # Generate and publish data for this specific sensor
                gateway_message = generate_ruuvi_gateway_message(sensor_mac)
                message = json.dumps(gateway_message)
                result = client.publish(MQTT_TOPIC, message)

                if result.rc != 0:
                    logger.error(f"Failed to publish message, return code: {result.rc}")
                else:
                    logger.info(f"Published to {MQTT_TOPIC} for sensor {sensor_mac}: RSSI: {gateway_message['rssi']}, Data: {gateway_message['data'][:20]}...")

                # Small delay between sensors to avoid flooding
                time.sleep(0.5)

            # Wait for next publish interval
            time.sleep(PUBLISH_INTERVAL)

    except KeyboardInterrupt:
        logger.info("Simulator stopped by user")
    except Exception as e:
        logger.error(f"Error: {e}")
    finally:
        # Clean up
        if client:
            client.loop_stop()
            client.disconnect()
            logger.info("Disconnected from MQTT broker")

if __name__ == "__main__":
    main()
