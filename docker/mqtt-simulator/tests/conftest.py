import pytest
import os
import sys
from unittest.mock import MagicMock

# Add the parent directory to the path so we can import the simulator module
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# Set environment variables for testing
@pytest.fixture(autouse=True)
def env_setup():
    """Set up environment variables for testing"""
    os.environ["MQTT_BROKER"] = "test-broker"
    os.environ["MQTT_PORT"] = "1883"
    os.environ["MQTT_TOPIC"] = "test/ruuvi/data"
    os.environ["PUBLISH_INTERVAL"] = "0.1"
    os.environ["NUM_SENSORS"] = "2"
    yield
    # Clean up
    env_vars = [
        "MQTT_BROKER",
        "MQTT_PORT",
        "MQTT_TOPIC",
        "PUBLISH_INTERVAL",
        "NUM_SENSORS",
    ]
    for var in env_vars:
        if var in os.environ:
            del os.environ[var]


@pytest.fixture
def mock_mqtt_client():
    """Create a mock MQTT client"""
    client = MagicMock()
    client.connect.return_value = None
    client.publish.return_value = MagicMock()
    client.loop_start.return_value = None
    client.loop_stop.return_value = None
    client.disconnect.return_value = None
    return client


@pytest.fixture
def sample_ruuvi_data():
    """Return sample Ruuvi data for testing"""
    return {
        "temp": 21.5,
        "humidity": 50.0,
        "pressure": 101325,
        "accelerationX": 0.0,
        "accelerationY": 0.0,
        "accelerationZ": 1.0,
        "battery_voltage": 3.0,
    }


# Configure pytest
def pytest_configure(config):
    """Configure pytest"""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow " "(deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests that require " "external services"
    )
