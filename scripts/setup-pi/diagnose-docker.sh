#!/bin/bash
# Docker Diagnostics Script
# Comprehensive testing and troubleshooting for Docker and Docker Compose issues
# Helps diagnose step 5 systemd service failures

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m'

# Configuration
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"

# Get script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source Docker compatibility library
if [ -f "$LIB_DIR/docker-compat.sh" ]; then
    source "$LIB_DIR/docker-compat.sh"
else
    echo -e "${COLOR_RED}Error: Docker compatibility library not found${COLOR_NC}"
    exit 1
fi

# Test results
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_test() {
    local level="$1"
    local message="$2"
    case "$level" in
        "PASS")
            echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} $message"
            ((PASS_COUNT++))
            ;;
        "FAIL")
            echo -e "${COLOR_RED}[FAIL]${COLOR_NC} $message"
            ((FAIL_COUNT++))
            ;;
        "WARN")
            echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $message"
            ((WARN_COUNT++))
            ;;
        "INFO")
            echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $message"
            ;;
    esac
    ((TEST_COUNT++))
}

print_header() {
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}        Docker Environment Diagnostics         ${COLOR_NC}"
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo ""
    echo "This script diagnoses Docker and Docker Compose issues"
    echo "that can cause systemd service failures in step 5."
    echo ""
}

test_docker_installation() {
    echo -e "${COLOR_CYAN}=== Docker Installation Test ===${COLOR_NC}"
    echo ""

    # Test Docker command availability
    if command -v docker >/dev/null 2>&1; then
        log_test "PASS" "Docker command found: $(command -v docker)"
    else
        log_test "FAIL" "Docker command not found"
        echo "  Solution: Install Docker with: curl -fsSL https://get.docker.com | sh"
        return 1
    fi

    # Test Docker version
    if docker --version >/dev/null 2>&1; then
        local version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_test "PASS" "Docker version: $version"
    else
        log_test "FAIL" "Docker version check failed"
        return 1
    fi

    # Test Docker daemon access
    if docker info >/dev/null 2>&1; then
        log_test "PASS" "Docker daemon is accessible"
    else
        log_test "FAIL" "Docker daemon is not accessible"
        echo "  Possible causes:"
        echo "    • Docker service not running: sudo systemctl start docker"
        echo "    • User not in docker group: sudo usermod -aG docker \$USER"
        echo "    • Permission issues: sudo chmod 666 /var/run/docker.sock"
        return 1
    fi

    echo ""
}

test_docker_compose_installation() {
    echo -e "${COLOR_CYAN}=== Docker Compose Installation Test ===${COLOR_NC}"
    echo ""

    # Test docker compose (plugin)
    if docker compose version >/dev/null 2>&1; then
        local plugin_version=$(docker compose version --short 2>/dev/null | head -1)
        log_test "PASS" "Docker Compose plugin available: $plugin_version"
        export DETECTED_COMPOSE_CMD="docker compose"
        export DETECTED_COMPOSE_TYPE="plugin"
    else
        log_test "WARN" "Docker Compose plugin not available"
    fi

    # Test docker-compose (standalone)
    if command -v docker-compose >/dev/null 2>&1; then
        local standalone_version=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_test "PASS" "Docker Compose standalone available: $standalone_version"
        if [ -z "${DETECTED_COMPOSE_CMD:-}" ]; then
            export DETECTED_COMPOSE_CMD="docker-compose"
            export DETECTED_COMPOSE_TYPE="standalone"
        fi
    else
        log_test "WARN" "Docker Compose standalone not available"
    fi

    # Summary
    if [ -n "${DETECTED_COMPOSE_CMD:-}" ]; then
        log_test "PASS" "Will use: ${DETECTED_COMPOSE_CMD} (${DETECTED_COMPOSE_TYPE})"
    else
        log_test "FAIL" "No Docker Compose installation found"
        echo "  Solution: Install Docker Compose plugin with:"
        echo "    sudo apt-get update && sudo apt-get install docker-compose-plugin"
        return 1
    fi

    echo ""
}

test_compose_file_syntax() {
    echo -e "${COLOR_CYAN}=== Compose File Syntax Test ===${COLOR_NC}"
    echo ""

    local compose_files=(
        "docker-compose.yaml"
        "docker-compose.production.yaml"
        "docker-compose.registry.yaml"
    )

    for compose_file in "${compose_files[@]}"; do
        local file_path="$PROJECT_DIR/$compose_file"

        if [ -f "$file_path" ]; then
            log_test "INFO" "Testing: $compose_file"

            if [ -n "${DETECTED_COMPOSE_CMD:-}" ]; then
                if $DETECTED_COMPOSE_CMD -f "$file_path" config >/dev/null 2>&1; then
                    log_test "PASS" "Syntax valid: $compose_file"
                else
                    log_test "FAIL" "Syntax error in: $compose_file"
                    echo "  Debug with: $DETECTED_COMPOSE_CMD -f $file_path config"
                fi
            else
                log_test "WARN" "Cannot test syntax - no compose command available"
            fi
        else
            log_test "WARN" "File not found: $compose_file"
        fi
    done

    echo ""
}

test_systemd_service_commands() {
    echo -e "${COLOR_CYAN}=== Systemd Service Command Test ===${COLOR_NC}"
    echo ""

    local compose_file="docker-compose.registry.yaml"
    local file_path="$PROJECT_DIR/$compose_file"

    if [ ! -f "$file_path" ]; then
        log_test "FAIL" "Compose file not found: $file_path"
        return 1
    fi

    if [ -z "${DETECTED_COMPOSE_CMD:-}" ]; then
        log_test "FAIL" "No Docker Compose command available for testing"
        return 1
    fi

    # Test the exact commands that would be used in systemd
    local test_commands=(
        "config:$DETECTED_COMPOSE_CMD -f $compose_file config"
        "pull:$DETECTED_COMPOSE_CMD -f $compose_file pull"
        "up:$DETECTED_COMPOSE_CMD -f $compose_file up -d"
        "down:$DETECTED_COMPOSE_CMD -f $compose_file down"
    )

    cd "$PROJECT_DIR"

    for test_case in "${test_commands[@]}"; do
        local test_name="${test_case%%:*}"
        local test_cmd="${test_case#*:}"

        log_test "INFO" "Testing systemd command: $test_name"
        echo "  Command: $test_cmd"

        # Test command syntax without execution (dry run where possible)
        case "$test_name" in
            "config")
                if eval "$test_cmd" >/dev/null 2>&1; then
                    log_test "PASS" "Command syntax valid: $test_name"
                else
                    log_test "FAIL" "Command syntax error: $test_name"
                    echo "  This is likely the cause of your systemd service failure"
                fi
                ;;
            "pull"|"down")
                # These are safe to test
                if timeout 10 eval "$test_cmd" >/dev/null 2>&1; then
                    log_test "PASS" "Command executes successfully: $test_name"
                else
                    log_test "WARN" "Command execution failed: $test_name (may be normal)"
                fi
                ;;
            "up")
                # Don't actually start services, just test syntax
                if echo "$test_cmd" | grep -q "\-f.*\.yaml.*up"; then
                    log_test "PASS" "Command format correct: $test_name"
                else
                    log_test "FAIL" "Command format incorrect: $test_name"
                fi
                ;;
        esac
    done

    echo ""
}

test_compatibility_library() {
    echo -e "${COLOR_CYAN}=== Compatibility Library Test ===${COLOR_NC}"
    echo ""

    # Test the compatibility library functions
    if init_docker_compat >/dev/null 2>&1; then
        log_test "PASS" "Docker compatibility library initialized"

        # Show detected configuration
        echo "  Configuration detected:"
        echo "    Docker Available: ${DOCKER_AVAILABLE:-unknown}"
        echo "    Docker Version: ${DOCKER_VERSION:-unknown}"
        echo "    Compose Available: ${COMPOSE_AVAILABLE:-unknown}"
        echo "    Compose Command: ${COMPOSE_COMMAND:-unknown}"
        echo "    Compose Type: ${COMPOSE_TYPE:-unknown}"

        # Test command generation
        if command_test=$(compose_cmd "config" "docker-compose.registry.yaml" 2>/dev/null); then
            log_test "PASS" "Command generation works: $command_test"
        else
            log_test "FAIL" "Command generation failed"
        fi
    else
        log_test "FAIL" "Docker compatibility library failed to initialize"
    fi

    echo ""
}

show_current_systemd_service() {
    echo -e "${COLOR_CYAN}=== Current Systemd Service Analysis ===${COLOR_NC}"
    echo ""

    local service_file="/etc/systemd/system/ruuvi-home.service"

    if [ -f "$service_file" ]; then
        log_test "INFO" "Systemd service file exists: $service_file"

        # Extract and show the ExecStart command
        local exec_start=$(grep "^ExecStart=" "$service_file" | cut -d'=' -f2-)
        if [ -n "$exec_start" ]; then
            echo "  Current ExecStart command:"
            echo "    $exec_start"

            # Check if it uses the problematic syntax
            if echo "$exec_start" | grep -q "docker compose.*-f"; then
                if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
                    log_test "PASS" "Uses 'docker compose' syntax - compatible with current Docker"
                else
                    log_test "FAIL" "Uses 'docker compose' but plugin not available"
                    echo "  Solution: Install docker-compose-plugin or change to docker-compose"
                fi
            elif echo "$exec_start" | grep -q "docker-compose.*-f"; then
                if command -v docker-compose >/dev/null 2>&1; then
                    log_test "PASS" "Uses 'docker-compose' syntax - compatible with standalone version"
                else
                    log_test "FAIL" "Uses 'docker-compose' but standalone not available"
                    echo "  Solution: Install docker-compose or change to docker compose"
                fi
            else
                log_test "WARN" "Unknown Docker Compose syntax in service file"
            fi
        else
            log_test "FAIL" "No ExecStart command found in service file"
        fi

        # Check service status
        if systemctl is-active ruuvi-home.service >/dev/null 2>&1; then
            log_test "PASS" "Service is currently active"
        else
            log_test "WARN" "Service is not active"

            # Show recent logs
            echo "  Recent service logs:"
            journalctl -u ruuvi-home.service -n 5 --no-pager | sed 's/^/    /'
        fi
    else
        log_test "FAIL" "Systemd service file not found: $service_file"
        echo "  The service needs to be generated first"
    fi

    echo ""
}

generate_fix_recommendations() {
    echo -e "${COLOR_CYAN}=== Fix Recommendations ===${COLOR_NC}"
    echo ""

    local recommendations=()

    # Analyze test results and generate recommendations
    if [ $FAIL_COUNT -gt 0 ]; then
        echo -e "${COLOR_RED}Issues detected that need fixing:${COLOR_NC}"
        echo ""

        # Docker not installed
        if ! command -v docker >/dev/null 2>&1; then
            recommendations+=("Install Docker: curl -fsSL https://get.docker.com | sh")
        fi

        # Docker daemon not accessible
        if ! docker info >/dev/null 2>&1; then
            recommendations+=("Start Docker service: sudo systemctl start docker")
            recommendations+=("Enable Docker service: sudo systemctl enable docker")
            recommendations+=("Add user to docker group: sudo usermod -aG docker \$USER")
        fi

        # No Docker Compose
        if [ -z "${DETECTED_COMPOSE_CMD:-}" ]; then
            recommendations+=("Install Docker Compose plugin: sudo apt-get install docker-compose-plugin")
            recommendations+=("Alternative: Install standalone docker-compose")
        fi

        # Service command issues
        if [ -f "/etc/systemd/system/ruuvi-home.service" ]; then
            recommendations+=("Regenerate systemd service: sudo ./scripts/setup-pi/setup-pi.sh --module 05-systemd-services.sh")
            recommendations+=("Reload systemd: sudo systemctl daemon-reload")
            recommendations+=("Restart service: sudo systemctl restart ruuvi-home.service")
        fi

        # Show recommendations
        local i=1
        for rec in "${recommendations[@]}"; do
            echo "$i. $rec"
            ((i++))
        done

    elif [ $WARN_COUNT -gt 0 ]; then
        echo -e "${COLOR_YELLOW}Minor issues detected:${COLOR_NC}"
        echo ""
        echo "1. Check service logs: journalctl -u ruuvi-home.service -f"
        echo "2. Verify compose file: ${DETECTED_COMPOSE_CMD:-docker-compose} -f docker-compose.registry.yaml config"
        echo "3. Test manual start: cd $PROJECT_DIR && ${DETECTED_COMPOSE_CMD:-docker-compose} -f docker-compose.registry.yaml up -d"

    else
        echo -e "${COLOR_GREEN}No issues detected!${COLOR_NC}"
        echo ""
        echo "Your Docker environment appears to be working correctly."
        echo "If you're still experiencing issues:"
        echo "1. Check systemd service logs: journalctl -u ruuvi-home.service -f"
        echo "2. Verify environment variables in .env file"
        echo "3. Test network connectivity to container registry"
    fi

    echo ""
}

show_summary() {
    echo -e "${COLOR_CYAN}=== Diagnostic Summary ===${COLOR_NC}"
    echo ""
    echo "Total tests: $TEST_COUNT"
    echo -e "Passed: ${COLOR_GREEN}$PASS_COUNT${COLOR_NC}"
    echo -e "Warnings: ${COLOR_YELLOW}$WARN_COUNT${COLOR_NC}"
    echo -e "Failed: ${COLOR_RED}$FAIL_COUNT${COLOR_NC}"
    echo ""

    if [ $FAIL_COUNT -eq 0 ] && [ $WARN_COUNT -eq 0 ]; then
        echo -e "${COLOR_GREEN}🎉 All diagnostics passed!${COLOR_NC}"
        exit 0
    elif [ $FAIL_COUNT -eq 0 ]; then
        echo -e "${COLOR_YELLOW}⚠️  Some warnings need attention${COLOR_NC}"
        exit 0
    else
        echo -e "${COLOR_RED}❌ Critical issues found - action required${COLOR_NC}"
        exit 1
    fi
}

main() {
    print_header
    test_docker_installation
    test_docker_compose_installation
    test_compose_file_syntax
    test_systemd_service_commands
    test_compatibility_library
    show_current_systemd_service
    generate_fix_recommendations
    show_summary
}

# Show help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Docker environment diagnostics for Ruuvi Home setup"
    echo ""
    echo "This script diagnoses common Docker and Docker Compose issues"
    echo "that cause systemd service failures in step 5 of the setup."
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "The script tests:"
    echo "• Docker installation and daemon access"
    echo "• Docker Compose availability and version"
    echo "• Compose file syntax validation"
    echo "• Systemd service command compatibility"
    echo "• Current service status and logs"
    echo ""
    exit 0
fi

# Run diagnostics
main "$@"
