#!/bin/bash
# Ruuvi Home Deployment Mode Test Script
# Tests both registry and local deployment modes

set -e

readonly SCRIPT_NAME="test-deployment-modes"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly SETUP_SCRIPT="$SCRIPT_DIR/setup-pi.sh"

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# Test configuration
readonly TEST_USER="${SUDO_USER:-pi}"
readonly TEST_PROJECT_DIR="/home/$TEST_USER/ruuvi-home-test"
readonly TEST_GITHUB_REPO="${GITHUB_REPO:-viljami/ruuvi-home}"

print_header() {
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}  Ruuvi Home Deployment Mode Test Suite    ${COLOR_NC}"
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo ""
}

print_test_info() {
    echo -e "${COLOR_YELLOW}Test Configuration:${COLOR_NC}"
    echo "  Test User: $TEST_USER"
    echo "  Test Directory: $TEST_PROJECT_DIR"
    echo "  GitHub Repository: $TEST_GITHUB_REPO"
    echo "  Setup Script: $SETUP_SCRIPT"
    echo ""
}

log_test() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "[${timestamp}] ${COLOR_BLUE}[INFO]${COLOR_NC} $message"
            ;;
        "SUCCESS")
            echo -e "[${timestamp}] ${COLOR_GREEN}[SUCCESS]${COLOR_NC} $message"
            ;;
        "ERROR")
            echo -e "[${timestamp}] ${COLOR_RED}[ERROR]${COLOR_NC} $message"
            ;;
        "WARN")
            echo -e "[${timestamp}] ${COLOR_YELLOW}[WARN]${COLOR_NC} $message"
            ;;
    esac
}

cleanup_test_environment() {
    log_test "INFO" "Cleaning up test environment"

    # Stop any running services
    if systemctl is-active --quiet ruuvi-home.service 2>/dev/null; then
        systemctl stop ruuvi-home.service || true
    fi

    if systemctl is-active --quiet ruuvi-webhook.service 2>/dev/null; then
        systemctl stop ruuvi-webhook.service || true
    fi

    # Remove test directory
    if [ -d "$TEST_PROJECT_DIR" ]; then
        rm -rf "$TEST_PROJECT_DIR"
    fi

    # Clean up any test containers
    if command -v docker &> /dev/null; then
        docker container prune -f || true
        docker image prune -f || true
    fi

    log_test "SUCCESS" "Test environment cleaned"
}

test_deployment_mode() {
    local mode="$1"
    local description="$2"

    echo ""
    echo -e "${COLOR_YELLOW}=== Testing $description ===${COLOR_NC}"

    log_test "INFO" "Starting test for deployment mode: $mode"

    # Set up environment for this test
    export RUUVI_USER="$TEST_USER"
    export PROJECT_DIR="$TEST_PROJECT_DIR"
    export DEPLOYMENT_MODE="$mode"

    if [ "$mode" = "registry" ]; then
        export GITHUB_REPO="$TEST_GITHUB_REPO"
        export DOCKER_COMPOSE_FILE="docker-compose.registry.yaml"
    else
        export DOCKER_COMPOSE_FILE="docker-compose.yaml"
    fi

    # Run the setup script with dry-run equivalent (validation only)
    log_test "INFO" "Testing deployment mode selection logic"

    # Test the choose_deployment_mode function by sourcing the script
    local temp_script=$(mktemp)
    cat > "$temp_script" << 'EOF'
#!/bin/bash
source "$1"
choose_deployment_mode
echo "Selected mode: $DEPLOYMENT_MODE"
echo "Compose file: $DOCKER_COMPOSE_FILE"
echo "GitHub repo: $GITHUB_REPO"
EOF

    chmod +x "$temp_script"

    if bash "$temp_script" "$SETUP_SCRIPT"; then
        log_test "SUCCESS" "Deployment mode selection test passed"
    else
        log_test "ERROR" "Deployment mode selection test failed"
        rm -f "$temp_script"
        return 1
    fi

    rm -f "$temp_script"

    # Test docker-compose file validation
    case "$mode" in
        "registry")
            log_test "INFO" "Validating registry compose file configuration"
            if [ -f "$PROJECT_ROOT/docker-compose.registry.yaml" ]; then
                log_test "SUCCESS" "Registry compose file exists"
            else
                log_test "ERROR" "Registry compose file missing"
                return 1
            fi
            ;;
        "local")
            log_test "INFO" "Validating local compose file configuration"
            if [ -f "$PROJECT_ROOT/docker-compose.yaml" ]; then
                log_test "SUCCESS" "Local compose file exists"
            else
                log_test "ERROR" "Local compose file missing"
                return 1
            fi
            ;;
    esac

    log_test "SUCCESS" "Deployment mode '$mode' test completed successfully"
    return 0
}

test_environment_variables() {
    echo ""
    echo -e "${COLOR_YELLOW}=== Testing Environment Variables ===${COLOR_NC}"

    log_test "INFO" "Testing environment variable handling"

    # Test different ways to specify registry mode
    local test_values=("1" "registry" "REGISTRY" "github" "GITHUB")

    for value in "${test_values[@]}"; do
        export DEPLOYMENT_MODE="$value"
        export GITHUB_REPO="test/repo"

        log_test "INFO" "Testing DEPLOYMENT_MODE='$value'"

        # Test normalization logic
        if bash -c 'source '"$SETUP_SCRIPT"'; choose_deployment_mode &>/dev/null'; then
            if [ "$DEPLOYMENT_MODE" = "registry" ]; then
                log_test "SUCCESS" "Value '$value' correctly normalized to 'registry'"
            else
                log_test "ERROR" "Value '$value' not normalized correctly (got: $DEPLOYMENT_MODE)"
                return 1
            fi
        else
            log_test "ERROR" "Failed to process DEPLOYMENT_MODE='$value'"
            return 1
        fi
    done

    # Test local mode values
    local local_values=("2" "local" "LOCAL" "build" "BUILD")

    for value in "${local_values[@]}"; do
        export DEPLOYMENT_MODE="$value"
        unset GITHUB_REPO

        log_test "INFO" "Testing DEPLOYMENT_MODE='$value'"

        if bash -c 'source '"$SETUP_SCRIPT"'; choose_deployment_mode &>/dev/null'; then
            if [ "$DEPLOYMENT_MODE" = "local" ]; then
                log_test "SUCCESS" "Value '$value' correctly normalized to 'local'"
            else
                log_test "ERROR" "Value '$value' not normalized correctly (got: $DEPLOYMENT_MODE)"
                return 1
            fi
        else
            log_test "ERROR" "Failed to process DEPLOYMENT_MODE='$value'"
            return 1
        fi
    done

    log_test "SUCCESS" "Environment variable tests completed"
    return 0
}

test_validation_errors() {
    echo ""
    echo -e "${COLOR_YELLOW}=== Testing Validation Errors ===${COLOR_NC}"

    log_test "INFO" "Testing error conditions"

    # Test invalid deployment mode
    export DEPLOYMENT_MODE="invalid"
    export GITHUB_REPO="test/repo"

    if bash -c 'source '"$SETUP_SCRIPT"'; choose_deployment_mode &>/dev/null'; then
        log_test "ERROR" "Should have failed with invalid deployment mode"
        return 1
    else
        log_test "SUCCESS" "Correctly rejected invalid deployment mode"
    fi

    # Test registry mode without GITHUB_REPO
    export DEPLOYMENT_MODE="registry"
    unset GITHUB_REPO

    if bash -c 'source '"$SETUP_SCRIPT"'; choose_deployment_mode &>/dev/null'; then
        log_test "ERROR" "Should have failed with missing GITHUB_REPO"
        return 1
    else
        log_test "SUCCESS" "Correctly required GITHUB_REPO for registry mode"
    fi

    log_test "SUCCESS" "Validation error tests completed"
    return 0
}

run_integration_test() {
    local mode="$1"

    echo ""
    echo -e "${COLOR_YELLOW}=== Integration Test: $mode Mode ===${COLOR_NC}"

    log_test "INFO" "Running integration test for $mode mode"
    log_test "WARN" "This would run the full setup script (disabled in test mode)"
    log_test "INFO" "To run full integration test manually:"

    if [ "$mode" = "registry" ]; then
        echo "  export DEPLOYMENT_MODE=registry"
        echo "  export GITHUB_REPO=$TEST_GITHUB_REPO"
        echo "  sudo $SETUP_SCRIPT"
    else
        echo "  export DEPLOYMENT_MODE=local"
        echo "  sudo $SETUP_SCRIPT"
    fi

    log_test "SUCCESS" "Integration test preparation completed"
}

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --mode MODE     Test specific mode only (registry|local)"
    echo "  --integration   Run full integration tests (requires sudo)"
    echo "  --cleanup-only  Only clean up test environment"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                      # Run all tests"
    echo "  $0 --mode registry      # Test registry mode only"
    echo "  $0 --integration        # Run integration tests"
    echo "  $0 --cleanup-only       # Clean up only"
}

main() {
    local test_mode=""
    local run_integration=false
    local cleanup_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                test_mode="$2"
                shift 2
                ;;
            --integration)
                run_integration=true
                shift
                ;;
            --cleanup-only)
                cleanup_only=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Check if running as root (required for some tests)
    if [ "$EUID" -ne 0 ]; then
        log_test "WARN" "Some tests require root privileges"
        log_test "INFO" "Run with sudo for complete testing"
    fi

    print_header
    print_test_info

    # Cleanup only mode
    if [ "$cleanup_only" = true ]; then
        cleanup_test_environment
        exit 0
    fi

    # Setup test environment
    cleanup_test_environment

    local failed_tests=()

    # Run unit tests
    if ! test_environment_variables; then
        failed_tests+=("Environment Variables")
    fi

    if ! test_validation_errors; then
        failed_tests+=("Validation Errors")
    fi

    # Run deployment mode tests
    if [ -n "$test_mode" ]; then
        case "$test_mode" in
            "registry")
                if ! test_deployment_mode "registry" "GitHub Registry Mode"; then
                    failed_tests+=("Registry Mode")
                fi
                ;;
            "local")
                if ! test_deployment_mode "local" "Local Build Mode"; then
                    failed_tests+=("Local Mode")
                fi
                ;;
            *)
                log_test "ERROR" "Invalid test mode: $test_mode"
                exit 1
                ;;
        esac
    else
        if ! test_deployment_mode "registry" "GitHub Registry Mode"; then
            failed_tests+=("Registry Mode")
        fi

        if ! test_deployment_mode "local" "Local Build Mode"; then
            failed_tests+=("Local Mode")
        fi
    fi

    # Run integration tests if requested
    if [ "$run_integration" = true ]; then
        if [ -n "$test_mode" ]; then
            run_integration_test "$test_mode"
        else
            run_integration_test "registry"
            run_integration_test "local"
        fi
    fi

    # Final cleanup
    cleanup_test_environment

    # Print results
    echo ""
    echo -e "${COLOR_BLUE}=== Test Results ===${COLOR_NC}"

    if [ ${#failed_tests[@]} -eq 0 ]; then
        log_test "SUCCESS" "All tests passed!"
        echo ""
        echo -e "${COLOR_GREEN}✓ Deployment mode selection working correctly${COLOR_NC}"
        echo -e "${COLOR_GREEN}✓ Environment variable handling working${COLOR_NC}"
        echo -e "${COLOR_GREEN}✓ Error validation working${COLOR_NC}"
        echo -e "${COLOR_GREEN}✓ Ready for production deployment${COLOR_NC}"
        exit 0
    else
        log_test "ERROR" "Some tests failed: ${failed_tests[*]}"
        echo ""
        echo -e "${COLOR_RED}✗ Fix the above issues before proceeding${COLOR_NC}"
        exit 1
    fi
}

# Export functions for testing
export -f test_deployment_mode test_environment_variables test_validation_errors

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
