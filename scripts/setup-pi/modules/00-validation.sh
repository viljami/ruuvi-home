#!/bin/bash
# Validation Module - Pre-flight checks for Ruuvi Home setup
# Validates system requirements before starting installation

set -e

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/config.sh"

# Module context for logging
readonly MODULE_CONTEXT="VALIDATION"

# Validation configuration
readonly VALIDATION_CONFIG=(
    "RUUVI_USER:required"
    "PROJECT_DIR:required"
    "WEBHOOK_SECRET:optional"
    "WEBHOOK_PORT:optional"
)

# Validate configuration variables
validate_configuration() {
    local context="$MODULE_CONTEXT"
    local failed_vars=()

    log_info "$context" "Validating configuration variables"

    for config_item in "${VALIDATION_CONFIG[@]}"; do
        local var_name="${config_item%:*}"
        local required="${config_item#*:}"

        if ! validate_env_var "$var_name" "$([[ $required == 'required' ]] && echo 'true' || echo 'false')"; then
            failed_vars+=("$var_name")
        fi
    done

    if [ ${#failed_vars[@]} -gt 0 ]; then
        log_error "$context" "Configuration validation failed for: ${failed_vars[*]}"
        return 1
    fi

    log_success "$context" "Configuration validation passed"
    return 0
}

# Validate user and permissions
validate_user_setup() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Validating user setup using shared configuration"

    # Use shared config library for user validation
    if ! validate_user_environment; then
        log_error "$context" "User environment validation failed"
        return 1
    fi

    log_success "$context" "User setup validation completed"
    return 0
}

# Validate required ports
validate_ports() {
    local context="$MODULE_CONTEXT"
    local ports_to_check=(
        "$WEBHOOK_PORT"
        "$FRONTEND_PORT"
        "$API_PORT"
        "$MOSQUITTO_PORT"
        "$DB_PORT"
    )

    log_info "$context" "Validating port availability"

    for port in "${ports_to_check[@]}"; do
        if [ -n "$port" ] && [ "$port" != "80" ]; then  # Skip port 80 as it might be in use
            if ! validate_port_available "$port"; then
                log_warn "$context" "Port $port is in use, setup may conflict"
            fi
        fi
    done

    log_success "$context" "Port validation completed"
    return 0
}

# Validate directory structure requirements
validate_directories() {
    local context="$MODULE_CONTEXT"
    local required_dirs=(
        "$(dirname "$PROJECT_DIR")"
        "$(dirname "$LOG_DIR")"
    )

    log_info "$context" "Validating directory requirements"

    for dir in "${required_dirs[@]}"; do
        if ! validate_directory_writable "$dir"; then
            return 1
        fi
    done

    log_success "$context" "Directory validation passed"
    return 0
}

# Validate existing installations
validate_existing_installations() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Checking existing installations"

    # Check if project directory already exists
    if [ -d "$PROJECT_DIR" ]; then
        log_warn "$context" "Project directory already exists: $PROJECT_DIR"

        # Check if it's a git repository
        if [ -d "$PROJECT_DIR/.git" ]; then
            log_info "$context" "Existing git repository found, will update"
        else
            log_warn "$context" "Directory exists but is not a git repository"
        fi
    fi

    # Check systemd services
    local services=("ruuvi-home.service" "ruuvi-webhook.service")
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            log_warn "$context" "Service already exists: $service"
        fi
    done

    log_success "$context" "Existing installation check completed"
    return 0
}

# Validate GitHub connectivity
validate_github_access() {
    local context="$MODULE_CONTEXT"
    local repo_url="https://api.github.com/repos/viljami/ruuvi-home"

    log_info "$context" "Validating GitHub repository access"

    if ! curl -s --connect-timeout 10 "$repo_url" | grep -q '"name"'; then
        log_error "$context" "Cannot access GitHub repository"
        return 1
    fi

    log_success "$context" "GitHub repository access validated"
    return 0
}

# Main validation function
run_validation() {
    local context="$MODULE_CONTEXT"
    local validation_steps=(
        "validate_system_requirements:System Requirements"
        "validate_configuration:Configuration"
        "validate_user_setup:User Setup"
        "validate_directories:Directories"
        "validate_ports:Ports"
        "validate_github_access:GitHub Access"
        "validate_existing_installations:Existing Installations"
    )

    log_section "Pre-flight Validation"
    log_info "$context" "Running validation for user: ${RUUVI_USER:-[detecting...]}"

    local step_num=1
    local total_steps=${#validation_steps[@]}
    local failed_steps=()

    for step in "${validation_steps[@]}"; do
        local func_name="${step%:*}"
        local step_desc="${step#*:}"

        log_step "$step_num" "$total_steps" "$step_desc"

        if ! $func_name; then
            failed_steps+=("$step_desc")
        fi

        ((step_num++))
    done

    if [ ${#failed_steps[@]} -gt 0 ]; then
        log_error "$context" "Validation failed for: ${failed_steps[*]}"
        log_error "$context" "Setup cannot continue until issues are resolved"
        exit 1
    fi

    log_success "$context" "All validation checks passed"
    log_info "$context" "System ready for Ruuvi Home setup"
}

# Export main function
export -f run_validation

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_validation
fi
