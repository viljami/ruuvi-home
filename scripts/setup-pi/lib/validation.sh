#!/bin/bash
# Validation utilities for Ruuvi Home setup scripts
# Provides functions to validate system requirements and configuration

# Source logging if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/logging.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
fi

# Validation result constants
readonly VALIDATION_PASS="pass"
readonly VALIDATION_FAIL="fail"

# System Requirements
readonly MIN_DISK_SPACE_GB=10
readonly MIN_RAM_MB=1024
readonly REQUIRED_COMMANDS=("curl" "git" "systemctl" "usermod")

# Validate if running as root
validate_root_privileges() {
    local context="VALIDATION"
    
    if [ "$EUID" -ne 0 ]; then
        log_error "$context" "Script must be run as root (use sudo)"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "Root privileges confirmed"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate operating system
validate_operating_system() {
    local context="VALIDATION"
    
    if [ ! -f /etc/os-release ]; then
        log_error "$context" "Cannot determine operating system"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    source /etc/os-release
    
    case "$ID" in
        "debian"|"ubuntu"|"raspbian")
            log_success "$context" "Operating system: $PRETTY_NAME"
            echo "$VALIDATION_PASS"
            return 0
            ;;
        *)
            log_error "$context" "Unsupported operating system: $PRETTY_NAME"
            echo "$VALIDATION_FAIL"
            return 1
            ;;
    esac
}

# Validate system architecture
validate_architecture() {
    local context="VALIDATION"
    local arch=$(uname -m)
    
    case "$arch" in
        "aarch64"|"arm64"|"x86_64"|"amd64")
            log_success "$context" "Architecture: $arch"
            echo "$VALIDATION_PASS"
            return 0
            ;;
        *)
            log_error "$context" "Unsupported architecture: $arch"
            echo "$VALIDATION_FAIL"
            return 1
            ;;
    esac
}

# Validate available disk space
validate_disk_space() {
    local context="VALIDATION"
    local target_dir="${1:-/}"
    local available_gb=$(df "$target_dir" | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [ "$available_gb" -lt "$MIN_DISK_SPACE_GB" ]; then
        log_error "$context" "Insufficient disk space: ${available_gb}GB available, ${MIN_DISK_SPACE_GB}GB required"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "Disk space: ${available_gb}GB available"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate available memory
validate_memory() {
    local context="VALIDATION"
    local available_mb=$(free -m | awk 'NR==2 {print $2}')
    
    if [ "$available_mb" -lt "$MIN_RAM_MB" ]; then
        log_error "$context" "Insufficient memory: ${available_mb}MB available, ${MIN_RAM_MB}MB required"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "Memory: ${available_mb}MB available"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate required commands exist
validate_required_commands() {
    local context="VALIDATION"
    local missing_commands=()
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "$context" "Missing required commands: ${missing_commands[*]}"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "All required commands available"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate user exists
validate_user_exists() {
    local username="$1"
    local context="VALIDATION"
    
    if [ -z "$username" ]; then
        log_error "$context" "Username not provided"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    if ! id "$username" &>/dev/null; then
        log_error "$context" "User '$username' does not exist"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "User '$username' exists"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate network connectivity
validate_network_connectivity() {
    local context="VALIDATION"
    local test_urls=("github.com" "get.docker.com")
    
    for url in "${test_urls[@]}"; do
        if ! curl -s --connect-timeout 5 "$url" &>/dev/null; then
            log_error "$context" "Cannot reach $url"
            echo "$VALIDATION_FAIL"
            return 1
        fi
    done
    
    log_success "$context" "Network connectivity verified"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate port availability
validate_port_available() {
    local port="$1"
    local context="VALIDATION"
    
    if [ -z "$port" ]; then
        log_error "$context" "Port not specified"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_warn "$context" "Port $port is already in use"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "Port $port is available"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate directory writability
validate_directory_writable() {
    local dir="$1"
    local context="VALIDATION"
    
    if [ -z "$dir" ]; then
        log_error "$context" "Directory not specified"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    # Create directory if it doesn't exist
    if [ ! -d "$dir" ]; then
        if ! mkdir -p "$dir" 2>/dev/null; then
            log_error "$context" "Cannot create directory: $dir"
            echo "$VALIDATION_FAIL"
            return 1
        fi
    fi
    
    # Test write permission
    local test_file="$dir/.write_test_$$"
    if ! touch "$test_file" 2>/dev/null; then
        log_error "$context" "Directory not writable: $dir"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    rm -f "$test_file" 2>/dev/null
    log_success "$context" "Directory writable: $dir"
    echo "$VALIDATION_PASS"
    return 0
}

# Validate environment variable
validate_env_var() {
    local var_name="$1"
    local required="${2:-false}"
    local context="VALIDATION"
    
    if [ -z "$var_name" ]; then
        log_error "$context" "Variable name not specified"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    local var_value="${!var_name}"
    
    if [ "$required" = "true" ] && [ -z "$var_value" ]; then
        log_error "$context" "Required environment variable not set: $var_name"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    if [ -n "$var_value" ]; then
        log_success "$context" "Environment variable set: $var_name"
    else
        log_debug "$context" "Optional environment variable not set: $var_name"
    fi
    
    echo "$VALIDATION_PASS"
    return 0
}

# Validate Docker installation
validate_docker_installed() {
    local context="VALIDATION"
    
    if ! command -v docker &> /dev/null; then
        log_info "$context" "Docker not installed (will be installed)"
        echo "$VALIDATION_PASS"
        return 0
    fi
    
    if ! docker --version &> /dev/null; then
        log_error "$context" "Docker installed but not responding"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "Docker already installed"
    echo "$VALIDATION_PASS"
    return 0
}

# Run comprehensive system validation
validate_system_requirements() {
    local context="VALIDATION"
    local failed_checks=()
    
    log_section "System Requirements Validation"
    
    # Core system checks
    validate_root_privileges || failed_checks+=("root_privileges")
    validate_operating_system || failed_checks+=("operating_system")
    validate_architecture || failed_checks+=("architecture")
    validate_disk_space || failed_checks+=("disk_space")
    validate_memory || failed_checks+=("memory")
    validate_required_commands || failed_checks+=("required_commands")
    validate_network_connectivity || failed_checks+=("network_connectivity")
    validate_docker_installed || failed_checks+=("docker_check")
    
    if [ ${#failed_checks[@]} -gt 0 ]; then
        log_error "$context" "System validation failed: ${failed_checks[*]}"
        echo "$VALIDATION_FAIL"
        return 1
    fi
    
    log_success "$context" "All system requirements validated"
    echo "$VALIDATION_PASS"
    return 0
}

# Export validation functions
export -f validate_root_privileges validate_operating_system validate_architecture
export -f validate_disk_space validate_memory validate_required_commands
export -f validate_user_exists validate_network_connectivity validate_port_available
export -f validate_directory_writable validate_env_var validate_docker_installed
export -f validate_system_requirements