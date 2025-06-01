#!/bin/bash
# User Detection Test Script
# Tests the robust user detection logic implemented in shared configuration library

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# Test framework
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

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
        "INFO")
            echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $message"
            ;;
        "WARN")
            echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $message"
            ;;
    esac
    ((TEST_COUNT++))
}

# Get script directory and source config library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

# Test utilities
backup_env_vars() {
    export ORIGINAL_RUUVI_USER="${RUUVI_USER:-}"
    export ORIGINAL_SUDO_USER="${SUDO_USER:-}"
    export ORIGINAL_USER="${USER:-}"
}

restore_env_vars() {
    export RUUVI_USER="${ORIGINAL_RUUVI_USER}"
    export SUDO_USER="${ORIGINAL_SUDO_USER}"
    export USER="${ORIGINAL_USER}"
}

clear_user_vars() {
    unset RUUVI_USER
    unset SUDO_USER
    unset USER
}

test_user_exists() {
    local test_user="$1"
    id "$test_user" &>/dev/null
}

# Test functions
test_explicit_ruuvi_user() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 1: Explicit RUUVI_USER Setting ===${COLOR_NC}"

    backup_env_vars
    clear_user_vars

    # Test with valid user
    local current_user=$(whoami)
    export RUUVI_USER="$current_user"

    if detect_target_user && [ "$RUUVI_USER" = "$current_user" ]; then
        log_test "PASS" "Explicit RUUVI_USER correctly detected: $RUUVI_USER"
    else
        log_test "FAIL" "Explicit RUUVI_USER not detected correctly"
    fi

    # Test with invalid user
    export RUUVI_USER="nonexistent_user_12345"
    clear_user_vars
    export SUDO_USER="$current_user"

    if detect_target_user && [ "$RUUVI_USER" = "$current_user" ]; then
        log_test "PASS" "Invalid RUUVI_USER correctly fell back to SUDO_USER"
    else
        log_test "FAIL" "Invalid RUUVI_USER fallback failed"
    fi

    restore_env_vars
}

test_sudo_user_detection() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 2: SUDO_USER Detection ===${COLOR_NC}"

    backup_env_vars
    clear_user_vars

    local current_user=$(whoami)
    export SUDO_USER="$current_user"

    if detect_target_user && [ "$RUUVI_USER" = "$current_user" ]; then
        log_test "PASS" "SUDO_USER correctly detected: $RUUVI_USER"
    else
        log_test "FAIL" "SUDO_USER detection failed"
    fi

    restore_env_vars
}

test_user_variable_detection() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 3: USER Variable Detection ===${COLOR_NC}"

    backup_env_vars
    clear_user_vars

    local current_user=$(whoami)
    export USER="$current_user"

    if detect_target_user && [ "$RUUVI_USER" = "$current_user" ]; then
        log_test "PASS" "USER variable correctly detected: $RUUVI_USER"
    else
        log_test "FAIL" "USER variable detection failed"
    fi

    restore_env_vars
}

test_whoami_fallback() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 4: whoami Fallback ===${COLOR_NC}"

    backup_env_vars
    clear_user_vars

    local current_user=$(whoami)

    if detect_target_user && [ "$RUUVI_USER" = "$current_user" ]; then
        log_test "PASS" "whoami fallback correctly detected: $RUUVI_USER"
    else
        log_test "FAIL" "whoami fallback failed"
    fi

    restore_env_vars
}

test_common_user_fallback() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 5: Common User Fallback ===${COLOR_NC}"

    backup_env_vars
    clear_user_vars

    # Mock whoami to fail
    whoami() { return 1; }

    # Check if any common users exist
    local found_user=""
    for test_user in pi ubuntu debian admin; do
        if test_user_exists "$test_user"; then
            found_user="$test_user"
            break
        fi
    done

    if [ -n "$found_user" ]; then
        if detect_target_user && [ "$RUUVI_USER" = "$found_user" ]; then
            log_test "PASS" "Common user fallback detected: $RUUVI_USER"
        else
            log_test "FAIL" "Common user fallback failed"
        fi
    else
        log_test "INFO" "No common fallback users available for testing"
    fi

    # Restore whoami
    unset -f whoami
    restore_env_vars
}

test_priority_order() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 6: Priority Order Validation ===${COLOR_NC}"

    backup_env_vars

    local current_user=$(whoami)
    local fallback_user="nobody"

    # Test that RUUVI_USER takes priority over SUDO_USER
    export RUUVI_USER="$current_user"
    export SUDO_USER="$fallback_user"
    export USER="$fallback_user"

    if detect_target_user && [ "$RUUVI_USER" = "$current_user" ]; then
        log_test "PASS" "RUUVI_USER has highest priority"
    else
        log_test "FAIL" "RUUVI_USER priority failed"
    fi

    # Test that SUDO_USER takes priority over USER
    unset RUUVI_USER
    export SUDO_USER="$current_user"
    export USER="$fallback_user"

    if detect_target_user && [ "$RUUVI_USER" = "$current_user" ]; then
        log_test "PASS" "SUDO_USER has priority over USER"
    else
        log_test "FAIL" "SUDO_USER priority failed"
    fi

    restore_env_vars
}

test_user_environment_validation() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 7: User Environment Validation ===${COLOR_NC}"

    backup_env_vars

    local current_user=$(whoami)
    export RUUVI_USER="$current_user"

    if detect_target_user && validate_user_environment; then
        log_test "PASS" "User environment validation succeeded"

        # Check if required variables are set
        if [ -n "$RUUVI_HOME" ] && [ -n "$PROJECT_DIR" ]; then
            log_test "PASS" "Required variables set: RUUVI_HOME=$RUUVI_HOME, PROJECT_DIR=$PROJECT_DIR"
        else
            log_test "FAIL" "Required variables not set properly"
        fi
    else
        log_test "FAIL" "User environment validation failed"
    fi

    restore_env_vars
}

test_edge_cases() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 8: Edge Cases ===${COLOR_NC}"

    backup_env_vars
    clear_user_vars

    # Test empty environment
    if ! detect_target_user 2>/dev/null; then
        log_test "FAIL" "Empty environment should still detect current user"
    else
        log_test "PASS" "Empty environment handled gracefully"
    fi

    # Test nonexistent users in all variables
    export RUUVI_USER="nonexistent1"
    export SUDO_USER="nonexistent2"
    export USER="nonexistent3"

    # Mock whoami to return nonexistent user
    whoami() { echo "nonexistent4"; }

    if detect_target_user 2>/dev/null; then
        log_test "PASS" "Nonexistent users handled with fallback"
    else
        log_test "INFO" "No fallback users available (expected on some systems)"
    fi

    # Restore whoami
    unset -f whoami
    restore_env_vars
}

test_permissions() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 9: Permission Checks ===${COLOR_NC}"

    backup_env_vars

    local current_user=$(whoami)
    export RUUVI_USER="$current_user"

    if detect_target_user; then
        if can_write_to_user_home; then
            log_test "PASS" "Can write to user home directory"
        else
            log_test "WARN" "Cannot write to user home (may need sudo)"
        fi

        local user_group=$(get_user_group)
        if [ -n "$user_group" ]; then
            log_test "PASS" "User group detected: $user_group"
        else
            log_test "FAIL" "Failed to detect user group"
        fi
    else
        log_test "FAIL" "User detection failed for permission tests"
    fi

    restore_env_vars
}

# Main test runner
main() {
    echo -e "${COLOR_BLUE}======================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}    Ruuvi Home User Detection Tests   ${COLOR_NC}"
    echo -e "${COLOR_BLUE}======================================${COLOR_NC}"
    echo ""
    echo "Current execution context:"
    echo "  Current user: $(whoami)"
    echo "  EUID: $EUID"
    echo "  SUDO_USER: ${SUDO_USER:-[not set]}"
    echo "  USER: ${USER:-[not set]}"
    echo "  Available common users: $(getent passwd | cut -d: -f1 | grep -E "^(pi|ubuntu|debian|admin)" | tr '\n' ' ' || echo "none")"

    # Run all tests
    test_explicit_ruuvi_user
    test_sudo_user_detection
    test_user_variable_detection
    test_whoami_fallback
    test_common_user_fallback
    test_priority_order
    test_user_environment_validation
    test_edge_cases
    test_permissions

    # Summary
    echo ""
    echo -e "${COLOR_BLUE}=== Test Summary ===${COLOR_NC}"
    echo "Total tests: $TEST_COUNT"
    echo -e "Passed: ${COLOR_GREEN}$PASS_COUNT${COLOR_NC}"
    echo -e "Failed: ${COLOR_RED}$FAIL_COUNT${COLOR_NC}"

    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "${COLOR_GREEN}🎉 All tests passed!${COLOR_NC}"
        exit 0
    else
        echo -e "${COLOR_RED}❌ Some tests failed${COLOR_NC}"
        exit 1
    fi
}

# Run tests
main "$@"
