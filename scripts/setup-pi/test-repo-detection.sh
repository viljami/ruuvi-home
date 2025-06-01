#!/bin/bash
# Repository Detection Test Script
# Tests the automatic repository name detection functionality

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
    esac
    ((TEST_COUNT++))
}

# Get script directory and source config library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

print_header() {
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}    Repository Detection Test Suite            ${COLOR_NC}"
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo ""
}

test_current_repository() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 1: Current Repository Detection ===${COLOR_NC}"

    # Clear any existing GITHUB_REPO
    unset GITHUB_REPO

    if git rev-parse --git-dir >/dev/null 2>&1; then
        local current_remote=$(git remote get-url origin 2>/dev/null || echo "none")
        log_test "INFO" "Current Git remote: $current_remote"

        if detect_repository_name; then
            log_test "PASS" "Repository detected: $GITHUB_REPO"

            # Validate format
            if [[ "$GITHUB_REPO" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
                log_test "PASS" "Repository name format is valid"
            else
                log_test "FAIL" "Repository name format is invalid: $GITHUB_REPO"
            fi
        else
            log_test "FAIL" "Repository detection failed"
        fi
    else
        log_test "INFO" "Not in a Git repository - skipping current repo test"
    fi
}

test_url_parsing() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 2: URL Parsing ===${COLOR_NC}"

    # Test various URL formats
    local test_urls=(
        "https://github.com/owner/repo.git:owner/repo"
        "https://github.com/owner/repo:owner/repo"
        "git@github.com:owner/repo.git:owner/repo"
        "git@github.com:owner/repo:owner/repo"
        "https://github.com/test-user/my-awesome-repo.git:test-user/my-awesome-repo"
        "invalid-url:SHOULD_FAIL"
        "https://gitlab.com/owner/repo.git:SHOULD_FAIL"
    )

    for test_case in "${test_urls[@]}"; do
        local url="${test_case%:*}"
        local expected="${test_case##*:}"

        # Mock the git command for this test
        git() {
            if [[ "$1" == "remote" && "$2" == "get-url" && "$3" == "origin" ]]; then
                echo "$url"
                return 0
            elif [[ "$1" == "rev-parse" && "$2" == "--git-dir" ]]; then
                return 0
            else
                command git "$@"
            fi
        }

        unset GITHUB_REPO
        if detect_repository_name 2>/dev/null; then
            if [[ "$expected" == "SHOULD_FAIL" ]]; then
                log_test "FAIL" "URL parsing should have failed for: $url"
            elif [[ "$GITHUB_REPO" == "$expected" ]]; then
                log_test "PASS" "Correctly parsed '$url' → '$GITHUB_REPO'"
            else
                log_test "FAIL" "Incorrect parsing '$url' → got '$GITHUB_REPO', expected '$expected'"
            fi
        else
            if [[ "$expected" == "SHOULD_FAIL" ]]; then
                log_test "PASS" "Correctly failed to parse invalid URL: $url"
            else
                log_test "FAIL" "Failed to parse valid URL: $url"
            fi
        fi

        # Restore git command
        unset -f git
    done
}

test_explicit_override() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 3: Explicit Override ===${COLOR_NC}"

    # Test that explicitly set GITHUB_REPO takes precedence
    export GITHUB_REPO="explicit/override"

    if get_repository_name; then
        if [[ "$GITHUB_REPO" == "explicit/override" ]]; then
            log_test "PASS" "Explicit GITHUB_REPO takes precedence"
        else
            log_test "FAIL" "Explicit GITHUB_REPO was overridden: $GITHUB_REPO"
        fi
    else
        log_test "FAIL" "get_repository_name failed with explicit GITHUB_REPO"
    fi

    unset GITHUB_REPO
}

test_fallback_scenarios() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 4: Fallback Scenarios ===${COLOR_NC}"

    # Mock git to simulate no repository
    git() {
        if [[ "$1" == "rev-parse" && "$2" == "--git-dir" ]]; then
            return 1
        else
            command git "$@"
        fi
    }

    unset GITHUB_REPO
    if get_repository_name 2>/dev/null; then
        log_test "FAIL" "Should fail when not in Git repository and no explicit GITHUB_REPO"
    else
        log_test "PASS" "Correctly fails when no repository detected"
    fi

    # Restore git command
    unset -f git
}

test_integration_with_deployment_mode() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 5: Integration with Deployment Mode ===${COLOR_NC}"

    # Test registry mode auto-detection
    export DEPLOYMENT_MODE="registry"
    unset GITHUB_REPO

    # Mock successful detection
    git() {
        if [[ "$1" == "remote" && "$2" == "get-url" && "$3" == "origin" ]]; then
            echo "https://github.com/integration/test.git"
            return 0
        elif [[ "$1" == "rev-parse" && "$2" == "--git-dir" ]]; then
            return 0
        else
            command git "$@"
        fi
    }

    # Test initialize_configuration with registry mode
    if initialize_configuration 2>/dev/null; then
        if [[ "$GITHUB_REPO" == "integration/test" ]]; then
            log_test "PASS" "Registry mode auto-detects repository during initialization"
        else
            log_test "FAIL" "Repository not set correctly during initialization: $GITHUB_REPO"
        fi
    else
        log_test "FAIL" "initialize_configuration failed with registry mode"
    fi

    # Restore git command
    unset -f git
    unset DEPLOYMENT_MODE
    unset GITHUB_REPO
}

show_current_config() {
    echo ""
    echo -e "${COLOR_BLUE}=== Current Configuration ===${COLOR_NC}"
    echo "GITHUB_REPO: ${GITHUB_REPO:-[not set]}"
    echo "GITHUB_REGISTRY: ${GITHUB_REGISTRY:-[not set]}"
    echo "IMAGE_TAG: ${IMAGE_TAG:-[not set]}"
    echo "DEPLOYMENT_MODE: ${DEPLOYMENT_MODE:-[not set]}"

    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo "Git remote: $(git remote get-url origin 2>/dev/null || echo 'none')"
    else
        echo "Git remote: Not in Git repository"
    fi
}

test_manual_detection() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test 6: Manual Detection ===${COLOR_NC}"

    # Clear environment
    unset GITHUB_REPO

    # Try to detect from current repo if available
    if detect_repository_name 2>/dev/null; then
        log_test "PASS" "Manual detection successful: $GITHUB_REPO"

        # Test that it works with registry URLs
        local test_url="ghcr.io/$GITHUB_REPO/frontend:latest"
        log_test "INFO" "Would use container URL: $test_url"

        if [[ "$test_url" =~ ^ghcr\.io/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+:latest$ ]]; then
            log_test "PASS" "Generated container URL format is valid"
        else
            log_test "FAIL" "Generated container URL format is invalid"
        fi
    else
        log_test "INFO" "Manual detection failed (expected if not in GitHub repo)"
    fi
}

print_summary() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test Summary ===${COLOR_NC}"
    echo "Total tests: $TEST_COUNT"
    echo -e "Passed: ${COLOR_GREEN}$PASS_COUNT${COLOR_NC}"
    echo -e "Failed: ${COLOR_RED}$FAIL_COUNT${COLOR_NC}"

    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "${COLOR_GREEN}🎉 All tests passed!${COLOR_NC}"
        echo ""
        echo "Repository detection is working correctly."
        echo "You can now use the setup script without manually setting GITHUB_REPO."
        exit 0
    else
        echo -e "${COLOR_RED}❌ Some tests failed${COLOR_NC}"
        echo ""
        echo "Please check the repository detection implementation."
        exit 1
    fi
}

main() {
    print_header
    show_current_config
    test_current_repository
    test_url_parsing
    test_explicit_override
    test_fallback_scenarios
    test_integration_with_deployment_mode
    test_manual_detection
    print_summary
}

# Run tests
main "$@"
