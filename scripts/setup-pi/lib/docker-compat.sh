#!/bin/bash
# Docker Compatibility Detection Library
# Handles version detection and command compatibility for Docker and Docker Compose
# Provides fallback logic for different Docker installations

set -e

# Docker version requirements
readonly MIN_DOCKER_VERSION="20.10"
readonly MIN_COMPOSE_VERSION="2.0"

# Simple logging functions for library independence
docker_log_info() {
    local context="${1:-DOCKER}"
    local message="${2:-$1}"
    echo "[INFO][$context] $message" >&2
}

docker_log_warn() {
    local context="${1:-DOCKER}"
    local message="${2:-$1}"
    echo "[WARN][$context] $message" >&2
}

docker_log_error() {
    local context="${1:-DOCKER}"
    local message="${2:-$1}"
    echo "[ERROR][$context] $message" >&2
}

docker_log_success() {
    local context="${1:-DOCKER}"
    local message="${2:-$1}"
    echo "[SUCCESS][$context] $message" >&2
}

# Version comparison utility
version_compare() {
    local version1="$1"
    local version2="$2"

    # Remove 'v' prefix if present
    version1="${version1#v}"
    version2="${version2#v}"

    # Split versions into arrays
    local IFS='.'
    local ver1_arr=($version1)
    local ver2_arr=($version2)

    # Compare major, minor, patch
    for i in {0..2}; do
        local v1="${ver1_arr[$i]:-0}"
        local v2="${ver2_arr[$i]:-0}"

        if [ "$v1" -lt "$v2" ]; then
            return 1  # version1 < version2
        elif [ "$v1" -gt "$v2" ]; then
            return 0  # version1 > version2
        fi
    done

    return 0  # versions are equal
}

# Detect Docker installation and version
detect_docker() {
    local context="DOCKER-COMPAT"

    docker_log_info "$context" "Detecting Docker installation"

    if ! command -v docker >/dev/null 2>&1; then
        docker_log_error "$context" "Docker command not found"
        export DOCKER_AVAILABLE="false"
        export DOCKER_VERSION=""
        return 1
    fi

    # Get Docker version
    local docker_version=""
    if docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); then
        export DOCKER_VERSION="$docker_version"
        export DOCKER_AVAILABLE="true"
        docker_log_success "$context" "Docker detected: $docker_version"

        # Check minimum version
        if version_compare "$docker_version" "$MIN_DOCKER_VERSION"; then
            docker_log_success "$context" "Docker version meets minimum requirement ($MIN_DOCKER_VERSION)"
            export DOCKER_VERSION_OK="true"
        else
            docker_log_warn "$context" "Docker version below minimum requirement ($MIN_DOCKER_VERSION)"
            export DOCKER_VERSION_OK="false"
        fi
    else
        docker_log_error "$context" "Could not determine Docker version"
        export DOCKER_AVAILABLE="false"
        export DOCKER_VERSION=""
        export DOCKER_VERSION_OK="false"
        return 1
    fi

    return 0
}

# Detect Docker Compose installation and determine command syntax
detect_docker_compose() {
    local context="DOCKER-COMPAT"

    docker_log_info "$context" "Detecting Docker Compose installation"

    # Test docker compose (plugin) first
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$compose_version" ]; then
            export COMPOSE_COMMAND="docker compose"
            export COMPOSE_VERSION="$compose_version"
            export COMPOSE_AVAILABLE="true"
            export COMPOSE_TYPE="plugin"
            docker_log_success "$context" "Docker Compose plugin detected: $compose_version"

            # Check version compatibility
            if version_compare "$compose_version" "$MIN_COMPOSE_VERSION"; then
                export COMPOSE_VERSION_OK="true"
            else
                export COMPOSE_VERSION_OK="false"
                docker_log_warn "$context" "Docker Compose version below minimum ($MIN_COMPOSE_VERSION)"
            fi
            return 0
        fi
    fi

    # Fallback to standalone docker-compose
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$compose_version" ]; then
            export COMPOSE_COMMAND="docker-compose"
            export COMPOSE_VERSION="$compose_version"
            export COMPOSE_AVAILABLE="true"
            export COMPOSE_TYPE="standalone"
            docker_log_success "$context" "Docker Compose standalone detected: $compose_version"

            # Check version compatibility (standalone versions use different numbering)
            if version_compare "$compose_version" "1.25.0"; then
                export COMPOSE_VERSION_OK="true"
            else
                export COMPOSE_VERSION_OK="false"
                docker_log_warn "$context" "Docker Compose version below minimum (1.25.0 for standalone)"
            fi
            return 0
        fi
    fi

    # No Docker Compose found
    docker_log_error "$context" "Docker Compose not found"
    export COMPOSE_COMMAND=""
    export COMPOSE_VERSION=""
    export COMPOSE_AVAILABLE="false"
    export COMPOSE_TYPE=""
    export COMPOSE_VERSION_OK="false"
    return 1
}

# Test Docker Compose with a specific compose file
test_docker_compose_file() {
    local compose_file="$1"
    local context="DOCKER-COMPAT"

    if [ -z "$compose_file" ]; then
        docker_log_error "$context" "No compose file specified for testing"
        return 1
    fi

    if [ ! -f "$compose_file" ]; then
        docker_log_error "$context" "Compose file not found: $compose_file"
        return 1
    fi

    if [ -z "${COMPOSE_COMMAND:-}" ]; then
        docker_log_error "$context" "COMPOSE_COMMAND not set - run detect_docker_compose first"
        return 1
    fi

    docker_log_info "$context" "Testing Docker Compose with file: $compose_file"

    # Test compose file syntax
    if $COMPOSE_COMMAND -f "$compose_file" config >/dev/null 2>&1; then
        docker_log_success "$context" "Compose file syntax is valid"
        return 0
    else
        docker_log_error "$context" "Compose file syntax validation failed"
        return 1
    fi
}

# Generate Docker Compose command with proper syntax
compose_cmd() {
    local action="$1"
    local compose_file="${2:-docker-compose.yaml}"
    local extra_args="${3:-}"

    if [ -z "${COMPOSE_COMMAND:-}" ]; then
        docker_log_error "DOCKER-COMPAT" "COMPOSE_COMMAND not set - run detect_docker_compose first"
        return 1
    fi

    # Construct command based on detected compose type
    local cmd="$COMPOSE_COMMAND"

    # Add compose file if specified
    if [ -n "$compose_file" ] && [ "$compose_file" != "docker-compose.yaml" ]; then
        cmd="$cmd -f $compose_file"
    fi

    # Add action
    cmd="$cmd $action"

    # Add extra arguments
    if [ -n "$extra_args" ]; then
        cmd="$cmd $extra_args"
    fi

    echo "$cmd"
}

# Execute Docker Compose command with proper error handling
compose_exec() {
    local action="$1"
    local compose_file="${2:-docker-compose.yaml}"
    local extra_args="${3:-}"
    local context="DOCKER-COMPAT"

    local cmd=$(compose_cmd "$action" "$compose_file" "$extra_args")
    if [ $? -ne 0 ]; then
        return 1
    fi

    docker_log_info "$context" "Executing: $cmd"

    if eval "$cmd"; then
        docker_log_success "$context" "Command completed successfully"
        return 0
    else
        local exit_code=$?
        docker_log_error "$context" "Command failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Validate complete Docker environment
validate_docker_environment() {
    local context="DOCKER-COMPAT"
    local errors=0

    docker_log_info "$context" "Validating Docker environment"

    # Detect Docker
    if ! detect_docker; then
        ((errors++))
    fi

    # Detect Docker Compose
    if ! detect_docker_compose; then
        ((errors++))
    fi

    # Check Docker daemon
    if [ "${DOCKER_AVAILABLE:-false}" = "true" ]; then
        if ! docker info >/dev/null 2>&1; then
            docker_log_error "$context" "Docker daemon is not running or accessible"
            ((errors++))
        else
            docker_log_success "$context" "Docker daemon is accessible"
        fi
    fi

    # Summary
    if [ $errors -eq 0 ]; then
        docker_log_success "$context" "Docker environment validation passed"
        export DOCKER_ENVIRONMENT_OK="true"
        return 0
    else
        docker_log_error "$context" "Docker environment validation failed ($errors errors)"
        export DOCKER_ENVIRONMENT_OK="false"
        return 1
    fi
}

# Get Docker environment summary
get_docker_summary() {
    cat << EOF
Docker Environment Summary:
  Docker Available: ${DOCKER_AVAILABLE:-unknown}
  Docker Version: ${DOCKER_VERSION:-unknown}
  Docker Version OK: ${DOCKER_VERSION_OK:-unknown}
  Compose Available: ${COMPOSE_AVAILABLE:-unknown}
  Compose Command: ${COMPOSE_COMMAND:-unknown}
  Compose Version: ${COMPOSE_VERSION:-unknown}
  Compose Type: ${COMPOSE_TYPE:-unknown}
  Compose Version OK: ${COMPOSE_VERSION_OK:-unknown}
  Environment OK: ${DOCKER_ENVIRONMENT_OK:-unknown}
EOF
}

# Install Docker Compose plugin if missing
install_docker_compose_plugin() {
    local context="DOCKER-COMPAT"

    docker_log_info "$context" "Installing Docker Compose plugin"

    # Check if Docker is available
    if [ "${DOCKER_AVAILABLE:-false}" != "true" ]; then
        docker_log_error "$context" "Docker must be installed before installing Compose plugin"
        return 1
    fi

    # Try to install compose plugin
    if docker compose version >/dev/null 2>&1; then
        docker_log_info "$context" "Docker Compose plugin already available"
        return 0
    fi

    # For Ubuntu/Debian systems
    if command -v apt-get >/dev/null 2>&1; then
        docker_log_info "$context" "Installing Docker Compose plugin via apt"
        if apt-get update && apt-get install -y docker-compose-plugin; then
            docker_log_success "$context" "Docker Compose plugin installed successfully"

            # Re-detect after installation
            detect_docker_compose
            return 0
        else
            docker_log_error "$context" "Failed to install Docker Compose plugin via apt"
        fi
    fi

    # Fallback to standalone installation
    docker_log_info "$context" "Installing standalone docker-compose"
    local compose_version="2.24.0"
    local arch=$(uname -m)

    # Map architecture names
    case "$arch" in
        "x86_64") arch="x86_64" ;;
        "aarch64") arch="aarch64" ;;
        "armv7l") arch="armv7" ;;
        *) arch="x86_64" ;;
    esac

    local download_url="https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-linux-${arch}"

    if curl -L "$download_url" -o /usr/local/bin/docker-compose && \
       chmod +x /usr/local/bin/docker-compose; then
        docker_log_success "$context" "Standalone docker-compose installed successfully"

        # Re-detect after installation
        detect_docker_compose
        return 0
    else
        docker_log_error "$context" "Failed to install standalone docker-compose"
        return 1
    fi
}

# Initialize Docker compatibility detection
init_docker_compat() {
    local context="DOCKER-COMPAT"

    docker_log_info "$context" "Initializing Docker compatibility detection"

    # Clear previous state
    unset DOCKER_AVAILABLE DOCKER_VERSION DOCKER_VERSION_OK
    unset COMPOSE_AVAILABLE COMPOSE_COMMAND COMPOSE_VERSION COMPOSE_TYPE COMPOSE_VERSION_OK
    unset DOCKER_ENVIRONMENT_OK

    # Run full validation
    if validate_docker_environment; then
        docker_log_success "$context" "Docker compatibility detection completed successfully"
        return 0
    else
        docker_log_error "$context" "Docker compatibility detection failed"
        return 1
    fi
}
