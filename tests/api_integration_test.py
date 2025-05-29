#!/usr/bin/env python3
"""
Ruuvi Home API Integration Tests
Tests the REST API endpoints for Milestone 1.3 acceptance criteria.
"""

import json
import time
import requests
import pytest
from datetime import datetime, timedelta
from typing import Dict, List, Any

# Test configuration
API_BASE_URL = "http://localhost:8080"
INFLUXDB_URL = "http://localhost:8086"
MQTT_SIMULATOR_SENSORS = ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02", "AA:BB:CC:DD:EE:03"]
GATEWAY_MAC = "AA:BB:CC:DD:EE:FF"

class TestAPIHealth:
    """Test health check endpoint"""
    
    def test_health_endpoint_returns_ok(self):
        """Health endpoint should return 200 OK"""
        response = requests.get(f"{API_BASE_URL}/health")
        assert response.status_code == 200
        assert response.text == "OK"
        assert response.headers.get("content-type") == "text/plain; charset=utf-8"

    def test_health_endpoint_fast_response(self):
        """Health endpoint should respond quickly"""
        start_time = time.time()
        response = requests.get(f"{API_BASE_URL}/health")
        response_time = time.time() - start_time
        
        assert response.status_code == 200
        assert response_time < 1.0  # Should respond within 1 second

class TestSensorsEndpoint:
    """Test sensors list endpoint"""
    
    def test_get_sensors_returns_json_array(self):
        """GET /api/sensors should return JSON array"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        data = response.json()
        assert isinstance(data, list)
        assert response.headers.get("content-type") == "application/json"

    def test_sensors_have_required_fields(self):
        """Sensor objects should have required fields"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        if sensors:  # If we have sensors
            sensor = sensors[0]
            required_fields = [
                "sensor_mac", "gateway_mac", "temperature", "humidity", 
                "pressure", "battery", "tx_power", "movement_counter",
                "measurement_sequence_number", "acceleration", 
                "acceleration_x", "acceleration_y", "acceleration_z", 
                "rssi", "timestamp"
            ]
            
            for field in required_fields:
                assert field in sensor, f"Missing required field: {field}"

    def test_sensors_data_types(self):
        """Sensor data should have correct types"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        if sensors:
            sensor = sensors[0]
            
            # String fields
            assert isinstance(sensor["sensor_mac"], str)
            assert isinstance(sensor["gateway_mac"], str)
            
            # Numeric fields
            assert isinstance(sensor["temperature"], (int, float))
            assert isinstance(sensor["humidity"], (int, float))
            assert isinstance(sensor["pressure"], (int, float))
            assert isinstance(sensor["battery"], int)
            assert isinstance(sensor["tx_power"], int)
            assert isinstance(sensor["movement_counter"], int)
            assert isinstance(sensor["measurement_sequence_number"], int)
            assert isinstance(sensor["acceleration"], (int, float))
            assert isinstance(sensor["acceleration_x"], int)
            assert isinstance(sensor["acceleration_y"], int)
            assert isinstance(sensor["acceleration_z"], int)
            assert isinstance(sensor["rssi"], int)
            assert isinstance(sensor["timestamp"], int)

    def test_sensor_mac_format(self):
        """Sensor MAC addresses should be properly formatted"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        for sensor in sensors:
            mac = sensor["sensor_mac"]
            # MAC should be in format XX:XX:XX:XX:XX:XX
            assert len(mac) == 17
            assert mac.count(":") == 5
            parts = mac.split(":")
            assert len(parts) == 6
            for part in parts:
                assert len(part) == 2
                assert all(c in "0123456789ABCDEFabcdef" for c in part)

class TestSensorLatestEndpoint:
    """Test latest sensor reading endpoint"""
    
    def test_get_latest_reading_valid_sensor(self):
        """GET /api/sensors/{mac}/latest should return sensor data"""
        # First get available sensors
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/latest")
        
        assert response.status_code == 200
        data = response.json()
        assert data["sensor_mac"] == sensor_mac

    def test_get_latest_reading_nonexistent_sensor(self):
        """GET /api/sensors/{mac}/latest should return 404 for non-existent sensor"""
        fake_mac = "XX:XX:XX:XX:XX:XX"
        response = requests.get(f"{API_BASE_URL}/api/sensors/{fake_mac}/latest")
        assert response.status_code == 404

    def test_latest_reading_has_recent_timestamp(self):
        """Latest reading should have a recent timestamp"""
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/latest")
        
        assert response.status_code == 200
        data = response.json()
        
        # Timestamp should be within last 24 hours (as per our query)
        now = int(time.time())
        twenty_four_hours_ago = now - (24 * 60 * 60)
        
        assert data["timestamp"] >= twenty_four_hours_ago
        assert data["timestamp"] <= now

class TestSensorHistoryEndpoint:
    """Test sensor history endpoint"""
    
    def test_get_history_default_parameters(self):
        """GET /api/sensors/{mac}/history should work with default parameters"""
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/history")
        
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)

    def test_get_history_with_limit(self):
        """History endpoint should respect limit parameter"""
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        limit = 5
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/history?limit={limit}")
        
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)
        assert len(data) <= limit

    def test_get_history_with_time_range(self):
        """History endpoint should respect start and end parameters"""
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/history?start=-30m&end=-10m")
        
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)

    def test_get_history_sorted_by_time(self):
        """History should be sorted by time (newest first)"""
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/history?limit=10")
        
        assert response.status_code == 200
        data = response.json()
        
        if len(data) > 1:
            # Should be sorted by timestamp descending (newest first)
            for i in range(len(data) - 1):
                assert data[i]["timestamp"] >= data[i + 1]["timestamp"]

    def test_get_history_nonexistent_sensor(self):
        """History endpoint should return 404 for non-existent sensor"""
        fake_mac = "XX:XX:XX:XX:XX:XX"
        response = requests.get(f"{API_BASE_URL}/api/sensors/{fake_mac}/history")
        assert response.status_code == 404

class TestErrorHandling:
    """Test API error handling"""
    
    def test_invalid_endpoint_returns_404(self):
        """Invalid endpoints should return 404"""
        response = requests.get(f"{API_BASE_URL}/api/invalid")
        assert response.status_code == 404

    def test_invalid_sensor_mac_format(self):
        """Invalid MAC format should be handled gracefully"""
        invalid_macs = ["invalid", "12:34", "XX:YY:ZZ:AA:BB:CC:DD"]
        
        for mac in invalid_macs:
            response = requests.get(f"{API_BASE_URL}/api/sensors/{mac}/latest")
            # Should return 404 or handle gracefully (not 500)
            assert response.status_code in [404, 400]

    def test_malformed_query_parameters(self):
        """Malformed query parameters should be handled gracefully"""
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        
        # Test invalid limit
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/history?limit=invalid")
        assert response.status_code in [200, 400]  # Should handle gracefully

class TestDataIntegrity:
    """Test data integrity and business logic"""
    
    def test_temperature_values_reasonable(self):
        """Temperature values should be in reasonable range"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        for sensor in sensors:
            temp = sensor["temperature"]
            # Reasonable temperature range: -40°C to +80°C
            assert -40 <= temp <= 80

    def test_humidity_values_valid(self):
        """Humidity values should be in valid range (0-100%)"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        for sensor in sensors:
            humidity = sensor["humidity"]
            assert 0 <= humidity <= 100

    def test_pressure_values_reasonable(self):
        """Pressure values should be in reasonable range"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        for sensor in sensors:
            pressure = sensor["pressure"]
            # Reasonable pressure range: 500-1200 hPa
            assert 500 <= pressure <= 1200

    def test_gateway_mac_consistent(self):
        """All sensors should report the same gateway MAC"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        if len(sensors) > 1:
            gateway_macs = set(sensor["gateway_mac"] for sensor in sensors)
            assert len(gateway_macs) == 1  # Should all be the same

class TestPerformance:
    """Test API performance characteristics"""
    
    def test_sensors_endpoint_performance(self):
        """Sensors endpoint should respond within reasonable time"""
        start_time = time.time()
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        response_time = time.time() - start_time
        
        assert response.status_code == 200
        assert response_time < 5.0  # Should respond within 5 seconds

    def test_latest_endpoint_performance(self):
        """Latest reading endpoint should respond quickly"""
        sensors_response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert sensors_response.status_code == 200
        
        sensors = sensors_response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        sensor_mac = sensors[0]["sensor_mac"]
        
        start_time = time.time()
        response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/latest")
        response_time = time.time() - start_time
        
        assert response.status_code == 200
        assert response_time < 3.0  # Should respond within 3 seconds

    def test_concurrent_requests(self):
        """API should handle multiple concurrent requests"""
        import concurrent.futures
        import threading
        
        def make_request():
            response = requests.get(f"{API_BASE_URL}/health")
            return response.status_code
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request) for _ in range(20)]
            results = [future.result() for future in futures]
        
        # All requests should succeed
        assert all(status == 200 for status in results)

class TestEndToEndDataFlow:
    """Test complete data flow from MQTT to API"""
    
    def test_mqtt_simulator_data_appears_in_api(self):
        """Data from MQTT simulator should appear in API"""
        # Wait a bit for data to flow through the system
        time.sleep(10)
        
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        assert len(sensors) > 0, "No sensors found - MQTT data may not be flowing"
        
        # Check if simulator sensor MACs appear
        sensor_macs = [sensor["sensor_mac"] for sensor in sensors]
        simulator_macs_found = any(mac in sensor_macs for mac in MQTT_SIMULATOR_SENSORS)
        assert simulator_macs_found, f"Simulator sensor MACs not found in API. Found: {sensor_macs}"

    def test_data_freshness(self):
        """Data should be fresh (recently received)"""
        response = requests.get(f"{API_BASE_URL}/api/sensors")
        assert response.status_code == 200
        
        sensors = response.json()
        if not sensors:
            pytest.skip("No sensors available for testing")
        
        # Data should be from within the last 10 minutes
        ten_minutes_ago = int(time.time()) - (10 * 60)
        
        fresh_sensors = [s for s in sensors if s["timestamp"] > ten_minutes_ago]
        assert len(fresh_sensors) > 0, "No fresh sensor data found"

def run_basic_api_validation():
    """Quick validation function for manual testing"""
    print("🧪 Running basic API validation...")
    
    try:
        # Health check
        response = requests.get(f"{API_BASE_URL}/health", timeout=5)
        print(f"✅ Health check: {response.status_code} - {response.text}")
        
        # Sensors list
        response = requests.get(f"{API_BASE_URL}/api/sensors", timeout=10)
        sensors = response.json()
        print(f"✅ Sensors endpoint: {response.status_code} - Found {len(sensors)} sensors")
        
        if sensors:
            # Latest reading
            sensor_mac = sensors[0]["sensor_mac"]
            response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/latest", timeout=10)
            print(f"✅ Latest reading: {response.status_code} - Sensor: {sensor_mac}")
            
            # History
            response = requests.get(f"{API_BASE_URL}/api/sensors/{sensor_mac}/history?limit=5", timeout=10)
            history = response.json()
            print(f"✅ History endpoint: {response.status_code} - {len(history)} records")
        
        print("🎉 Basic API validation passed!")
        return True
        
    except Exception as e:
        print(f"❌ API validation failed: {e}")
        return False

if __name__ == "__main__":
    # Run basic validation when script is executed directly
    run_basic_api_validation()