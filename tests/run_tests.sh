#!/bin/bash
# Ruuvi Home Test Runner
# Comprehensive test suite for API endpoints and system integration

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose-test.yaml"
MAIN_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yaml"
COMPOSE_FILE="${MAIN_COMPOSE_FILE}"

# Test configuration
API_URL="http://localhost:8080"
MAX_WAIT_TIME=120
HEALTH_CHECK_INTERVAL=2

# Flags
CLEANUP_ON_EXIT=true
VERBOSE=false
USE_TEST_COMPOSE=false
RUN_INTEGRATION_ONLY=false

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -t, --test              Use test docker-compose configuration
    -i, --integration-only  Run only integration tests (skip unit tests)
    -n, --no-cleanup        Don't cleanup services after tests

Examples:
    $0                      Run all tests with default configuration
    $0 -t                   Run tests using test compose file
    $0 -v -i                Run only integration tests with verbose output
    $0 --no-cleanup         Run tests and leave services running
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--test)
            USE_TEST_COMPOSE=true
            COMPOSE_FILE="${TEST_COMPOSE_FILE}"
            shift
            ;;
        -i|--integration-only)
            RUN_INTEGRATION_ONLY=true
            shift
            ;;
        -n|--no-cleanup)
            CLEANUP_ON_EXIT=false
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Cleanup function
cleanup() {
    if [ "$CLEANUP_ON_EXIT" = true ]; then
        log_info "Cleaning up test environment..."
        cd "$PROJECT_ROOT"
        if [ -f "$COMPOSE_FILE" ]; then
            docker-compose -f "$COMPOSE_FILE" down -v > /dev/null 2>&1 || true
        fi
        log_info "Cleanup completed"
    else
        log_info "Skipping cleanup (services left running)"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"

    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose is not installed or not in PATH"
        exit 1
    fi

    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed or not in PATH"
        exit 1
    fi

    # Check if pip is available
    if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
        log_error "pip is not installed or not in PATH"
        exit 1
    fi

    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed or not in PATH"
        exit 1
    fi

    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Docker compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    log_success "All prerequisites are available"
}

# Install Python test dependencies
install_test_dependencies() {
    log_section "Installing Test Dependencies"

    cd "$SCRIPT_DIR"

    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv venv
    fi

    # Activate virtual environment
    source venv/bin/activate

    # Install dependencies
    log_info "Installing Python test dependencies..."
    pip install -r requirements.txt

    log_success "Test dependencies installed"
}

# Wait for service to be healthy
wait_for_service() {
    local service_name="$1"
    local health_url="$2"
    local max_wait="$3"

    log_info "Waiting for $service_name to be ready..."

    local start_time=$(date +%s)
    local end_time=$((start_time + max_wait))

    while [ $(date +%s) -lt $end_time ]; do
        if curl -f -s "$health_url" > /dev/null 2>&1; then
            log_success "$service_name is ready"
            return 0
        fi

        if [ "$VERBOSE" = true ]; then
            log_info "Waiting for $service_name... ($(($end_time - $(date +%s)))s remaining)"
        fi

        sleep $HEALTH_CHECK_INTERVAL
    done

    log_error "$service_name failed to become ready within ${max_wait}s"
    return 1
}

# Start test environment
start_test_environment() {
    log_section "Starting Test Environment"

    cd "$PROJECT_ROOT"

    # Stop any existing containers
    log_info "Stopping any existing containers..."
    docker-compose -f "$COMPOSE_FILE" down -v > /dev/null 2>&1 || true

    # Start services
    log_info "Starting services with compose file: $COMPOSE_FILE"
    if [ "$VERBOSE" = true ]; then
        docker-compose -f "$COMPOSE_FILE" up -d
    else
        docker-compose -f "$COMPOSE_FILE" up -d > /dev/null 2>&1
    fi

    # Wait for services to be ready
    log_info "Waiting for services to become ready..."


    # Wait for API server
    if ! wait_for_service "API Server" "$API_URL/health" $MAX_WAIT_TIME; then
        log_error "API Server failed to start"
        return 1
    fi

    # Give MQTT simulator some time to generate data
    log_info "Waiting for MQTT simulator to generate test data..."
    sleep 10

    log_success "Test environment is ready"
}

# Run MQTT simulator tests
run_mqtt_simulator_tests() {
    log_section "Running MQTT Simulator Tests"

    cd "$PROJECT_ROOT"

    # Run the MQTT simulator tests using docker-compose
    if docker-compose -f "$COMPOSE_FILE" run --rm mqtt-simulator-tests; then
        log_success "MQTT Simulator tests passed"
        return 0
    else
        log_error "MQTT Simulator tests failed"
        return 1
    fi
}

# Run API integration tests
run_api_integration_tests() {
    log_section "Running API Integration Tests"

    cd "$SCRIPT_DIR"
    source venv/bin/activate

    # Set test environment variables
    export API_BASE_URL="$API_URL"

    # Run the tests with pytest
    local pytest_args=("-v" "--tb=short" "--color=yes")

    if [ "$VERBOSE" = true ]; then
        pytest_args+=("-s" "--capture=no")
    fi

    # Add coverage if available
    if pip show pytest-cov > /dev/null 2>&1; then
        pytest_args+=("--cov=." "--cov-report=term-missing")
    fi

    log_info "Running API integration tests..."
    if pytest "${pytest_args[@]}" api_integration_test.py; then
        log_success "API integration tests passed"
        return 0
    else
        log_error "API integration tests failed"
        return 1
    fi
}

# Run basic API validation
run_basic_api_validation() {
    log_section "Running Basic API Validation"

    cd "$SCRIPT_DIR"
    source venv/bin/activate

    if python3 api_integration_test.py; then
        log_success "Basic API validation passed"
        return 0
    else
        log_error "Basic API validation failed"
        return 1
    fi
}

# Show service status
show_service_status() {
    log_section "Service Status"

    cd "$PROJECT_ROOT"

    echo "Docker containers:"
    docker-compose -f "$COMPOSE_FILE" ps

    echo ""
    echo "Service health checks:"

    # Check API
    if curl -f -s "$API_URL/health" > /dev/null 2>&1; then
        echo -e "API Server: ${GREEN}✅ Healthy${NC}"
    else
        echo -e "API Server: ${RED}❌ Unhealthy${NC}"
    fi

    # Check for sensor data
    sensor_count=$(curl -s "$API_URL/api/sensors" | jq length 2>/dev/null || echo "0")
    echo -e "Sensors found: ${BLUE}$sensor_count${NC}"
}

# Main test execution
main() {
    log_section "Ruuvi Home Test Suite"
    log_info "Starting comprehensive test run..."

    local test_results=()
    local overall_result=0

    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi

    # Install test dependencies
    if ! install_test_dependencies; then
        exit 1
    fi

    # Start test environment
    if ! start_test_environment; then
        exit 1
    fi

    # Show service status
    show_service_status

    # Run basic API validation first
    if run_basic_api_validation; then
        test_results+=("Basic API Validation: PASSED")
    else
        test_results+=("Basic API Validation: FAILED")
        overall_result=1
    fi

    # Run MQTT simulator tests (unless integration-only mode)
    if [ "$RUN_INTEGRATION_ONLY" != true ]; then
        if run_mqtt_simulator_tests; then
            test_results+=("MQTT Simulator Tests: PASSED")
        else
            test_results+=("MQTT Simulator Tests: FAILED")
            overall_result=1
        fi
    fi

    # Run API integration tests
    if run_api_integration_tests; then
        test_results+=("API Integration Tests: PASSED")
    else
        test_results+=("API Integration Tests: FAILED")
        overall_result=1
    fi

    # Print final results
    log_section "Test Results Summary"

    for result in "${test_results[@]}"; do
        if [[ $result == *"PASSED"* ]]; then
            echo -e "${GREEN}✅ $result${NC}"
        else
            echo -e "${RED}❌ $result${NC}"
        fi
    done

    echo ""
    if [ $overall_result -eq 0 ]; then
        log_success "🎉 All tests passed! Milestone 1.3 API requirements are met."
        echo ""
        echo "✅ API endpoints accessible via HTTP"
        echo "✅ Returns correctly formatted JSON"
        echo "✅ Can retrieve sensor list and latest readings"
        echo "✅ Basic error cases handled appropriately"
    else
        log_error "❌ Some tests failed. Please review the results above."
    fi

    return $overall_result
}

# Run main function
main "$@"
