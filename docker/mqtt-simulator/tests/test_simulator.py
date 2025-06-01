#!/usr/bin/env python3

import json
import os
import sys
import time
from unittest.mock import MagicMock, patch

# Add the parent directory to the path so we can import the simulator module
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import struct  # noqa: E402

import pytest  # noqa: E402
import simulator  # noqa: E402
from ruuvitag_sensor.decoder import get_decoder  # noqa: E402


@pytest.fixture
def mqtt_client_mock():
    """Mock MQTT client for testing"""
    with patch("simulator.mqtt.Client") as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        yield mock_client


class TestRuuviDataFormat:
    """Tests for Ruuvi data format creation"""

    def test_data_hex_structure(self):
        """Test that the hex data has the correct structure"""
        test_mac = "C6:99:AB:11:22:33"
        data_hex = simulator.create_ruuvi_data_hex(
            temp=21.5,
            humidity=50.0,
            pressure=101325,
            accel_x=0.0,
            accel_y=0.0,
            accel_z=1.0,
            battery_voltage=3.0,
            sensor_mac=test_mac,
        )

        # Check that the result is a hex string
        assert isinstance(data_hex, str)
        assert all(c in "0123456789ABCDEF" for c in data_hex)

        # Check that it's exactly 24 bytes (48 hex characters)
        assert len(data_hex) == 48, f"Expected 48 chars, got {len(data_hex)}"

        # Convert hex to bytes for inspection
        data_bytes = bytes.fromhex(data_hex)

        # Check data format (5)
        assert data_bytes[0] == 0x05, "Data format identifier incorrect"

        # Decode temperature (bytes 1-2, signed 16-bit integer, 0.005°C)
        temp_raw = struct.unpack(">h", data_bytes[1:3])[0]
        temp = temp_raw * 0.005
        assert abs(temp - 21.5) < 0.01, "Temperature decoding failed"

        # Decode humidity (bytes 3-4, unsigned 16-bit integer, 0.0025%)
        humidity_raw = struct.unpack(">H", data_bytes[3:5])[0]
        humidity = humidity_raw * 0.0025
        assert abs(humidity - 50.0) < 0.01, "Humidity decoding failed"

        # Decode pressure (bytes 5-6, unsigned 16-bit integer, +50000 Pa)
        pressure_raw = struct.unpack(">H", data_bytes[5:7])[0]
        pressure = pressure_raw + 50000
        assert abs(pressure - 101325) < 10, "Pressure decoding failed"

    def test_temperature_range(self):
        """Test temperature encoding within the valid range"""
        test_mac = "C6:99:AB:11:22:33"
        for temp in [-30.0, -10.0, 0.0, 10.0, 20.0, 50.0, 80.0]:
            data_hex = simulator.create_ruuvi_data_hex(
                temp=temp,
                humidity=50.0,
                pressure=101325,
                accel_x=0.0,
                accel_y=0.0,
                accel_z=1.0,
                battery_voltage=3.0,
                sensor_mac=test_mac,
            )

            # Decode data
            data_bytes = bytes.fromhex(data_hex)
            temp_raw = struct.unpack(">h", data_bytes[1:3])[0]
            decoded_temp = temp_raw * 0.005

            msg = f"Temperature {temp}°C not encoded/decoded correctly"
            assert abs(decoded_temp - temp) < 0.01, msg

    def test_ruuvitag_sensor_compatibility(self):
        """Test that our encoded data is compatible with ruuvitag-sensor"""
        test_mac = "C6:99:AB:11:22:33"

        # Generate test data
        data_hex = simulator.create_ruuvi_data_hex(
            temp=23.45,
            humidity=65.25,
            pressure=101325,
            accel_x=0.1,
            accel_y=-0.05,
            accel_z=0.98,
            battery_voltage=2.95,
            sensor_mac=test_mac,
        )

        # Test with ruuvitag-sensor decoder
        decoder = get_decoder(5)
        sensor_data = decoder.decode_data(data_hex)

        # Verify decoding was successful
        assert sensor_data is not None, "Decoder returned None"
        assert sensor_data["data_format"] == 5, "Wrong data format"

        # Verify values are close to expected
        temp_msg = "Temperature mismatch"
        assert abs(sensor_data["temperature"] - 23.45) < 0.1, temp_msg
        humidity_msg = "Humidity mismatch"
        assert abs(sensor_data["humidity"] - 65.25) < 0.1, humidity_msg
        pressure_msg = "Pressure mismatch"
        assert abs(sensor_data["pressure"] - 1013.25) < 1, pressure_msg

        # Verify MAC address
        expected_mac = test_mac.replace(":", "").lower()
        mac_msg = f"MAC mismatch: {sensor_data['mac']} != {expected_mac}"
        assert sensor_data["mac"] == expected_mac, mac_msg

        # Verify acceleration values
        accel_x_msg = "Acceleration X mismatch"
        assert abs(sensor_data["acceleration_x"] - 100) < 5, accel_x_msg
        accel_y_msg = "Acceleration Y mismatch"
        assert abs(sensor_data["acceleration_y"] - (-50)) < 5, accel_y_msg
        accel_z_msg = "Acceleration Z mismatch"
        assert abs(sensor_data["acceleration_z"] - 980) < 10, accel_z_msg


class TestGatewayMessageGeneration:
    """Tests for the gateway message generation"""

    def test_gateway_message_structure(self):
        """Test that the generated gateway message has correct structure"""
        test_mac = "C6:99:AB:11:22:33"
        # Set fixed gateway MAC for deterministic testing
        with patch.object(simulator, "GATEWAY_MAC", "AA:BB:CC:DD:EE:FF"):
            gateway_message = simulator.generate_ruuvi_gateway_message(test_mac)

            # Check message structure
            assert "gw_mac" in gateway_message
            assert "rssi" in gateway_message
            assert "aoa" in gateway_message
            assert "gwts" in gateway_message
            assert "ts" in gateway_message
            assert "data" in gateway_message
            assert "coords" in gateway_message

            # Check specific values
            assert gateway_message["gw_mac"] == "AA:BB:CC:DD:EE:FF"
            assert isinstance(gateway_message["rssi"], int)
            assert isinstance(gateway_message["aoa"], list)
            assert isinstance(gateway_message["gwts"], int)
            assert isinstance(gateway_message["ts"], int)
            assert isinstance(gateway_message["data"], str)
            data_chars = gateway_message["data"]
            assert all(c in "0123456789ABCDEF" for c in data_chars)

            # Check BLE advertisement structure
            data_hex = gateway_message["data"]
            assert data_hex.startswith("020106"), "Should start with flags"
            assert "FF9904" in data_hex, "Should contain Ruuvi manufacturer ID"

            # Make sure timestamp is reasonable (within a day of now)
            now = int(time.time())
            assert abs(gateway_message["ts"] - now) < 86400

    def test_rssi_values_are_realistic(self):
        """Test that the generated RSSI values are within realistic ranges"""
        test_mac = "C6:99:AB:11:22:33"
        # Generate data 10 times to check ranges
        rssi_values = []

        for _ in range(10):
            gateway_message = simulator.generate_ruuvi_gateway_message(test_mac)
            rssi_values.append(gateway_message["rssi"])

        # Check ranges
        range_msg = "RSSI outside realistic range"
        assert all(-90 <= rssi <= -60 for rssi in rssi_values), range_msg

    def test_matches_example_format(self):
        """Test that the message matches the example format"""
        test_mac = "C6:99:AB:11:22:33"
        example = {
            "gw_mac": "AA:BB:CC:DD:EE:FF",
            "rssi": -62,
            "aoa": [],
            "gwts": 1728719836,
            "ts": 1728719836,
            "data": (
                "0201061BFF9904050F18FFFFFFFFFFF0FFEC0414AA96A8DE8EF7" "97E36ED811"
            ),
            "coords": "",
        }

        gateway_message = simulator.generate_ruuvi_gateway_message(test_mac)

        # Check that all fields in the example exist in our message
        for key in example:
            assert key in gateway_message, f"Missing field: {key}"
            expected_type = type(example[key])
            actual_type = type(gateway_message[key])
            msg = f"Type mismatch for field: {key}"
            assert actual_type is expected_type, msg

    def test_sensor_mac_consistency(self):
        """Test that the same sensor MAC produces consistent identifiers"""
        test_macs = ["C6:99:AB:11:22:33", "C6:99:AB:44:55:66", "C6:99:AB:77:88:99"]

        for test_mac in test_macs:
            # Generate multiple messages for the same sensor
            messages = [
                simulator.generate_ruuvi_gateway_message(test_mac) for _ in range(3)
            ]

            for msg in messages:
                data_hex = msg["data"]
                # Extract sensor payload (skip BLE headers)
                # Skip: 020106 (6) + 1BFF990405 (8) = 14 chars
                payload_start = 14
                sensor_payload = data_hex[payload_start:]

                # Decode to verify MAC is included correctly
                decoder = get_decoder(5)
                sensor_data = decoder.decode_data(sensor_payload)

                expected_mac = test_mac.replace(":", "").lower()
                mac_msg = f"MAC mismatch for {test_mac}: " f"got {sensor_data['mac']}"
                assert sensor_data["mac"] == expected_mac, mac_msg


class TestMQTTIntegration:
    """Tests for MQTT integration"""

    def test_mqtt_client_connection(self, mqtt_client_mock):
        """Test that the MQTT client connects correctly"""
        # Mock sys.argv to avoid actual command line args in test
        with patch("sys.argv", ["simulator.py"]):
            # Run the main function with the mocked client, but stop before
            # the infinite loop
            with patch("simulator.time.sleep", side_effect=KeyboardInterrupt):
                try:
                    simulator.main()
                except KeyboardInterrupt:
                    pass

                # Check that connect was called with the right parameters
                mqtt_client_mock.connect.assert_called_once()
                mqtt_client_mock.loop_start.assert_called_once()

    def test_mqtt_publish(self, mqtt_client_mock):
        """Test that MQTT messages are published correctly"""
        # Setup the mock to capture the published message
        published_topic = None
        published_message = None

        def mock_publish(topic, message):
            nonlocal published_topic, published_message
            published_topic = topic
            published_message = message
            return MagicMock()

        mqtt_client_mock.publish.side_effect = mock_publish

        # Generate one message cycle
        with patch("simulator.client", mqtt_client_mock):
            with patch("simulator.time.sleep", side_effect=KeyboardInterrupt):
                try:
                    simulator.main()
                except KeyboardInterrupt:
                    pass

        # Check that publish was called
        mqtt_client_mock.publish.assert_called()

        # Check topic is correct
        assert published_topic == simulator.MQTT_TOPIC

        # Check message is valid JSON
        assert published_message is not None
        try:
            data = json.loads(published_message)
            assert "gw_mac" in data
            assert "data" in data
        except json.JSONDecodeError:
            pytest.fail("Published message is not valid JSON")


if __name__ == "__main__":
    pytest.main(["-v"])
