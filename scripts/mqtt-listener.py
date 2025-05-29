#!/usr/bin/env python3

import paho.mqtt.client as mqtt
import json
import argparse
import signal
import sys
import os
from datetime import datetime

# Default configuration from environment variables with fallbacks
DEFAULT_BROKER = os.environ.get("MQTT_BROKER", "localhost")
DEFAULT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
DEFAULT_TOPIC = os.environ.get("MQTT_TOPIC", "ruuvi/gateway/data")
DEFAULT_QOS = int(os.environ.get("MQTT_QOS", "0"))

# ANSI color codes for prettier output
COLORS = {
    "reset": "\033[0m",
    "red": "\033[31m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "blue": "\033[34m",
    "magenta": "\033[35m",
    "cyan": "\033[36m",
    "white": "\033[37m",
    "bold": "\033[1m"
}

# Message counter for statistics
message_count = 0
sensor_data = {}
start_time = datetime.now()

def on_connect(client, userdata, flags, rc):
    """Called when connected to MQTT broker"""
    if rc == 0:
        print(f"{COLORS['green']}Connected to MQTT broker at {args.broker}:{args.port}{COLORS['reset']}")
        print(f"Subscribing to topic: {COLORS['cyan']}{args.topic}{COLORS['reset']}")
        client.subscribe(args.topic, qos=args.qos)
    else:
        print(f"{COLORS['red']}Failed to connect to MQTT broker, return code: {rc}{COLORS['reset']}")

def on_message(client, userdata, msg):
    """Called when a message is received"""
    global message_count, sensor_data

    message_count += 1
    current_time = datetime.now()
    elapsed = (current_time - start_time).total_seconds()

    try:
        # Parse JSON message
        payload = json.loads(msg.payload.decode('utf-8'))

        # Print topic and timestamp
        print(f"\n{COLORS['bold']}{COLORS['blue']}[{current_time.strftime('%Y-%m-%d %H:%M:%S')}] Message #{message_count}{COLORS['reset']}")
        print(f"{COLORS['yellow']}Topic: {msg.topic}{COLORS['reset']}")

        # Extract and print gateway info
        if 'data' in payload and 'gw_mac' in payload['data']:
            gw_mac = payload['data']['gw_mac']
            timestamp = payload['data']['timestamp']
            print(f"{COLORS['magenta']}Gateway: {gw_mac} @ {timestamp}{COLORS['reset']}")

            # Process tags (sensor data)
            if 'tags' in payload['data']:
                tags = payload['data']['tags']
                print(f"{COLORS['green']}Found {len(tags)} sensors:{COLORS['reset']}")

                for mac, data in tags.items():
                    # Keep track of seen sensors
                    if mac not in sensor_data:
                        sensor_data[mac] = 0
                    sensor_data[mac] += 1

                    # Print sensor data
                    name = data.get('name', 'unnamed')
                    rssi = data.get('rssi', 'N/A')
                    data_format = data.get('dataFormat', 'unknown')
                    raw_data = data.get('data', '')

                    print(f"  {COLORS['cyan']}{mac}{COLORS['reset']} ({name}):")
                    print(f"    RSSI: {rssi} dBm, Format: {data_format}")
                    print(f"    Data: {raw_data}")
        else:
            # Print the whole message for non-standard formats
            print(f"{COLORS['yellow']}Payload:{COLORS['reset']}")
            print(json.dumps(payload, indent=2))

        # Print stats periodically
        if message_count % 10 == 0:
            print(f"\n{COLORS['bold']}Statistics after {elapsed:.1f} seconds:{COLORS['reset']}")
            print(f"  Messages received: {message_count} ({message_count/elapsed:.2f} msgs/sec)")
            print(f"  Unique sensors: {len(sensor_data)}")
            for mac, count in sensor_data.items():
                print(f"    {mac}: {count} readings")

    except json.JSONDecodeError:
        print(f"{COLORS['red']}Error: Invalid JSON payload{COLORS['reset']}")
        print(f"Raw payload: {msg.payload}")
    except Exception as e:
        print(f"{COLORS['red']}Error processing message: {str(e)}{COLORS['reset']}")

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    print(f"\n{COLORS['yellow']}Disconnecting...{COLORS['reset']}")
    client.disconnect()
    sys.exit(0)

if __name__ == "__main__":
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='MQTT listener for Ruuvi Gateway data')
    parser.add_argument('-b', '--broker', default=DEFAULT_BROKER, help=f'MQTT broker address (default: {DEFAULT_BROKER})')
    parser.add_argument('-p', '--port', type=int, default=DEFAULT_PORT, help=f'MQTT broker port (default: {DEFAULT_PORT})')
    parser.add_argument('-t', '--topic', default=DEFAULT_TOPIC, help=f'MQTT topic to subscribe to (default: {DEFAULT_TOPIC})')
    parser.add_argument('-q', '--qos', type=int, choices=[0, 1, 2], default=DEFAULT_QOS, help=f'QoS level (default: {DEFAULT_QOS})')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    args = parser.parse_args()

    # Set up MQTT client
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message

    # Set up signal handler for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)

    try:
        # Connect to broker
        print(f"Connecting to MQTT broker at {args.broker}:{args.port}...")
        client.connect(args.broker, args.port, 60)

        # Start the MQTT loop
        print("Waiting for messages. Press Ctrl+C to exit.")
        client.loop_forever()

    except ConnectionRefusedError:
        print(f"{COLORS['red']}Error: Connection refused. Check if the broker is running.{COLORS['reset']}")
    except Exception as e:
        print(f"{COLORS['red']}Error: {str(e)}{COLORS['reset']}")
