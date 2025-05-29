#!/bin/bash
# Quick API Test Script for Ruuvi Home
# Tests basic API functionality for Milestone 1.3

set -e

# Configuration
API_URL="http://localhost:8080"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
PASS=0
FAIL=0

test_pass() {
    echo -e "${GREEN}✅ PASS:${NC} $1"
    ((PASS++))
}

test_fail() {
    echo -e "${RED}❌ FAIL:${NC} $1"
    ((FAIL++))
}

test_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Ruuvi Home API Quick Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test 1: Health Check
echo "🏥 Testing health endpoint..."
if curl -f -s "$API_URL/health" > /dev/null; then
    HEALTH_RESPONSE=$(curl -s "$API_URL/health")
    if [ "$HEALTH_RESPONSE" = "OK" ]; then
        test_pass "Health endpoint returns 'OK'"
    else
        test_fail "Health endpoint returned: '$HEALTH_RESPONSE'"
    fi
else
    test_fail "Health endpoint not accessible"
    echo "Is the API server running? Try: docker-compose up api-server"
    exit 1
fi

# Test 2: Sensors List
echo ""
echo "📡 Testing sensors list endpoint..."
if SENSORS_RESPONSE=$(curl -f -s "$API_URL/api/sensors"); then
    SENSOR_COUNT=$(echo "$SENSORS_RESPONSE" | jq length 2>/dev/null || echo "0")
    if [ "$SENSOR_COUNT" -gt 0 ]; then
        test_pass "Sensors endpoint returns $SENSOR_COUNT sensors"
        
        # Get first sensor MAC for further testing
        FIRST_SENSOR_MAC=$(echo "$SENSORS_RESPONSE" | jq -r '.[0].sensor_mac' 2>/dev/null)
        test_info "First sensor MAC: $FIRST_SENSOR_MAC"
        
        # Validate JSON structure
        if echo "$SENSORS_RESPONSE" | jq -e '.[0] | has("sensor_mac") and has("gateway_mac") and has("temperature")' > /dev/null 2>&1; then
            test_pass "Sensor data has required fields"
        else
            test_fail "Sensor data missing required fields"
        fi
    else
        test_fail "No sensors found - is MQTT simulator running?"
        FIRST_SENSOR_MAC=""
    fi
else
    test_fail "Sensors endpoint not accessible"
    FIRST_SENSOR_MAC=""
fi

# Test 3: Latest Reading (if we have sensors)
if [ -n "$FIRST_SENSOR_MAC" ] && [ "$FIRST_SENSOR_MAC" != "null" ]; then
    echo ""
    echo "🔄 Testing latest reading endpoint..."
    if LATEST_RESPONSE=$(curl -f -s "$API_URL/api/sensors/$FIRST_SENSOR_MAC/latest"); then
        test_pass "Latest reading endpoint accessible"
        
        # Check if MAC matches
        RETURNED_MAC=$(echo "$LATEST_RESPONSE" | jq -r '.sensor_mac' 2>/dev/null)
        if [ "$RETURNED_MAC" = "$FIRST_SENSOR_MAC" ]; then
            test_pass "Latest reading returns correct sensor MAC"
        else
            test_fail "MAC mismatch: expected $FIRST_SENSOR_MAC, got $RETURNED_MAC"
        fi
        
        # Check temperature value
        TEMP=$(echo "$LATEST_RESPONSE" | jq -r '.temperature' 2>/dev/null)
        if [[ "$TEMP" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            test_pass "Temperature is numeric: ${TEMP}°C"
        else
            test_fail "Invalid temperature value: $TEMP"
        fi
    else
        test_fail "Latest reading endpoint not accessible"
    fi

    # Test 4: Historical Data
    echo ""
    echo "📊 Testing history endpoint..."
    if HISTORY_RESPONSE=$(curl -f -s "$API_URL/api/sensors/$FIRST_SENSOR_MAC/history?limit=5"); then
        HISTORY_COUNT=$(echo "$HISTORY_RESPONSE" | jq length 2>/dev/null || echo "0")
        test_pass "History endpoint accessible, returned $HISTORY_COUNT records"
        
        if [ "$HISTORY_COUNT" -gt 0 ]; then
            # Check if data is sorted by timestamp (descending)
            FIRST_TS=$(echo "$HISTORY_RESPONSE" | jq -r '.[0].timestamp' 2>/dev/null)
            if [ "$HISTORY_COUNT" -gt 1 ]; then
                SECOND_TS=$(echo "$HISTORY_RESPONSE" | jq -r '.[1].timestamp' 2>/dev/null)
                if [ "$FIRST_TS" -ge "$SECOND_TS" ]; then
                    test_pass "History data is sorted by timestamp (newest first)"
                else
                    test_fail "History data not properly sorted"
                fi
            fi
        fi
    else
        test_fail "History endpoint not accessible"
    fi
else
    test_info "Skipping latest/history tests - no sensors available"
fi

# Test 5: Error Handling
echo ""
echo "🚫 Testing error handling..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/api/sensors/XX:XX:XX:XX:XX:XX/latest")
if [ "$HTTP_CODE" = "404" ]; then
    test_pass "Non-existent sensor returns 404"
else
    test_fail "Non-existent sensor returned HTTP $HTTP_CODE (expected 404)"
fi

# Test 6: JSON Content Type
echo ""
echo "📝 Testing content types..."
CONTENT_TYPE=$(curl -s -I "$API_URL/api/sensors" | grep -i content-type | cut -d' ' -f2- | tr -d '\r\n')
if [[ "$CONTENT_TYPE" == *"application/json"* ]]; then
    test_pass "Sensors endpoint returns JSON content type"
else
    test_fail "Unexpected content type: $CONTENT_TYPE"
fi

# Test 7: Response Times
echo ""
echo "⏱️  Testing response times..."
START_TIME=$(date +%s.%N)
curl -f -s "$API_URL/health" > /dev/null
END_TIME=$(date +%s.%N)
RESPONSE_TIME=$(echo "$END_TIME - $START_TIME" | bc -l 2>/dev/null || echo "unknown")

if command -v bc > /dev/null && [ "$RESPONSE_TIME" != "unknown" ]; then
    if (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
        test_pass "Health endpoint responds quickly (${RESPONSE_TIME}s)"
    else
        test_fail "Health endpoint slow response (${RESPONSE_TIME}s)"
    fi
else
    test_info "Response time measurement skipped (bc not available)"
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed! API is working correctly.${NC}"
    echo ""
    echo "✅ Milestone 1.3 Acceptance Criteria:"
    echo "  • API endpoints accessible via HTTP"
    echo "  • Returns correctly formatted JSON"
    echo "  • Can retrieve sensor list and latest readings"
    echo "  • Basic error cases handled appropriately"
    echo ""
    echo "You can now test manually with:"
    echo "  curl $API_URL/health"
    echo "  curl $API_URL/api/sensors"
    if [ -n "$FIRST_SENSOR_MAC" ] && [ "$FIRST_SENSOR_MAC" != "null" ]; then
        echo "  curl $API_URL/api/sensors/$FIRST_SENSOR_MAC/latest"
        echo "  curl '$API_URL/api/sensors/$FIRST_SENSOR_MAC/history?limit=10'"
    fi
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Check the API server logs:${NC}"
    echo "  docker-compose logs api-server"
    echo ""
    echo "Common issues:"
    echo "  • API server not running: docker-compose up api-server"
    echo "  • InfluxDB not ready: docker-compose logs influxdb"
    echo "  • No sensor data: check MQTT simulator"
    exit 1
fi