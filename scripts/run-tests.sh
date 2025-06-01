#!/bin/bash
# Ruuvi Home Test Runner
# Runs tests for different components of the Ruuvi Home project

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Directory containing this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Default options
COMPONENT="all"
TEST_TYPE="unit"
CLEANUP=true

# Display usage information
usage() {
    echo -e "${GREEN}Ruuvi Home Test Runner${NC}"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --component COMPONENT  Component to test (mqtt-simulator, mqtt-reader, api, all)"
    echo "  -t, --type TYPE            Test type (unit, integration, all)"
    echo "  --no-cleanup               Don't remove containers after testing"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                         # Run all unit tests"
    echo "  $0 -c mqtt-simulator       # Run only MQTT simulator tests"
    echo "  $0 -t integration          # Run integration tests"
    echo "  $0 -c api -t all           # Run all tests for the API component"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--component)
            COMPONENT="$2"
            shift 2
            ;;
        -t|--type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Validate component
if [[ ! "$COMPONENT" =~ ^(mqtt-simulator|mqtt-reader|api|all)$ ]]; then
    echo -e "${RED}Error: Invalid component. Must be one of: mqtt-simulator, mqtt-reader, api, all${NC}"
    exit 1
fi

# Validate test type
if [[ ! "$TEST_TYPE" =~ ^(unit|integration|all)$ ]]; then
    echo -e "${RED}Error: Invalid test type. Must be one of: unit, integration, all${NC}"
    exit 1
fi

# Function to run MQTT simulator tests
run_mqtt_simulator_tests() {
    local test_type=$1
    echo -e "${YELLOW}Running MQTT simulator $test_type tests...${NC}"

    # Build the test command based on test type
    local test_command="python -m pytest tests/"
    if [[ "$test_type" == "unit" ]]; then
        test_command="$test_command -m \"not integration\" -v"
    elif [[ "$test_type" == "integration" ]]; then
        test_command="$test_command -m integration -v"
    else
        test_command="$test_command -v"
    fi

    # Add coverage reporting
    test_command="$test_command --cov=simulator --cov-report=term"

    # Run the tests in Docker
    cd "$PROJECT_ROOT"
    docker-compose -f docker-compose-test.yaml run --rm mqtt-simulator-tests $test_command

    # Run linting checks
    echo -e "\n${YELLOW}Running MQTT simulator linting checks...${NC}"
    docker-compose -f docker-compose-test.yaml run --rm mqtt-simulator-lint

    # Cleanup if requested
    if [[ "$CLEANUP" == true ]]; then
        echo -e "\n${YELLOW}Cleaning up test containers...${NC}"
        docker-compose -f docker-compose-test.yaml down
    fi
}

# Function to run API tests
run_api_tests() {
    local test_type=$1
    echo -e "${YELLOW}Running API $test_type tests...${NC}"
    # TODO: Implement API tests when available
    echo -e "${YELLOW}API tests not yet implemented${NC}"
}

# Function to run MQTT reader tests
run_mqtt_reader_tests() {
    local test_type=$1
    echo -e "${YELLOW}Running MQTT reader $test_type tests...${NC}"
    # TODO: Implement MQTT reader tests when available
    echo -e "${YELLOW}MQTT reader tests not yet implemented${NC}"
}

# Main test runner
echo -e "${GREEN}Starting Ruuvi Home tests${NC}"
echo -e "Component: $COMPONENT"
echo -e "Test type: $TEST_TYPE"
echo ""

# Run tests based on component and type
if [[ "$COMPONENT" == "all" || "$COMPONENT" == "mqtt-simulator" ]]; then
    if [[ "$TEST_TYPE" == "all" ]]; then
        run_mqtt_simulator_tests "unit"
        run_mqtt_simulator_tests "integration"
    else
        run_mqtt_simulator_tests "$TEST_TYPE"
    fi
fi

if [[ "$COMPONENT" == "all" || "$COMPONENT" == "mqtt-reader" ]]; then
    if [[ "$TEST_TYPE" == "all" ]]; then
        run_mqtt_reader_tests "unit"
        run_mqtt_reader_tests "integration"
    else
        run_mqtt_reader_tests "$TEST_TYPE"
    fi
fi

if [[ "$COMPONENT" == "all" || "$COMPONENT" == "api" ]]; then
    if [[ "$TEST_TYPE" == "all" ]]; then
        run_api_tests "unit"
        run_api_tests "integration"
    else
        run_api_tests "$TEST_TYPE"
    fi
fi

echo -e "\n${GREEN}All tests completed!${NC}"
