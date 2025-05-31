#!/bin/bash
# Logging utilities for Ruuvi Home setup scripts
# Provides standardized logging functions with levels and formatting

# Source configuration if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/../config/setup.env" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../config/setup.env"
fi

# Default log level if not set
LOG_LEVEL="${LOG_LEVEL:-info}"

# Log levels (numeric for comparison)
declare -A LOG_LEVELS=(
    ["debug"]=0
    ["info"]=1
    ["warn"]=2
    ["error"]=3
)

# Get current log level numeric value
get_log_level_num() {
    echo "${LOG_LEVELS[${LOG_LEVEL}]:-1}"
}

# Check if message should be logged based on level
should_log() {
    local message_level="$1"
    local current_level_num=$(get_log_level_num)
    local message_level_num="${LOG_LEVELS[$message_level]:-1}"
    
    [ "$message_level_num" -ge "$current_level_num" ]
}

# Format log message with timestamp and level
format_log_message() {
    local level="$1"
    local context="$2"
    local action="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] [$context] $action"
}

# Generic log function
log_message() {
    local level="$1"
    local context="$2"
    local action="$3"
    local color="$4"
    
    if should_log "$level"; then
        local message=$(format_log_message "$level" "$context" "$action")
        
        if [ -t 1 ] && [ -n "$color" ]; then
            echo -e "${color}${message}${COLOR_NC:-\033[0m}"
        else
            echo "$message"
        fi
    fi
}

# Debug logging - for developers
log_debug() {
    local context="$1"
    local action="$2"
    log_message "debug" "$context" "$action" ""
}

# Info logging - for business understanding
log_info() {
    local context="$1"
    local action="$2"
    log_message "info" "$context" "$action" "${COLOR_GREEN:-\033[0;32m}"
}

# Warning logging - for recoverable anomalies
log_warn() {
    local context="$1"
    local action="$2"
    log_message "warn" "$context" "$action" "${COLOR_YELLOW:-\033[1;33m}"
}

# Error logging - for logic-stopping failures
log_error() {
    local context="$1"
    local action="$2"
    log_message "error" "$context" "$action" "${COLOR_RED:-\033[0;31m}"
}

# Progress logging with step information
log_step() {
    local step_num="$1"
    local total_steps="$2"
    local description="$3"
    local context="SETUP"
    local action="Step $step_num/$total_steps: $description"
    
    log_info "$context" "$action"
}

# Section header logging
log_section() {
    local section_name="$1"
    local context="SETUP"
    local action="=== $section_name ==="
    
    if [ -t 1 ]; then
        echo -e "\n${COLOR_GREEN:-\033[0;32m}${action}${COLOR_NC:-\033[0m}\n"
    else
        echo -e "\n${action}\n"
    fi
}

# Success logging
log_success() {
    local context="$1"
    local action="$2"
    log_message "info" "$context" "✓ $action" "${COLOR_GREEN:-\033[0;32m}"
}

# Failure logging
log_failure() {
    local context="$1"
    local action="$2"
    log_message "error" "$context" "✗ $action" "${COLOR_RED:-\033[0;31m}"
}

# Log to both console and file
log_to_file() {
    local level="$1"
    local context="$2"
    local action="$3"
    local log_file="${4:-/var/log/ruuvi-home/setup.log}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    
    # Log to console
    case "$level" in
        "debug") log_debug "$context" "$action" ;;
        "info") log_info "$context" "$action" ;;
        "warn") log_warn "$context" "$action" ;;
        "error") log_error "$context" "$action" ;;
    esac
    
    # Log to file (no colors)
    if [ -w "$(dirname "$log_file")" ] 2>/dev/null || [ -w "$log_file" ] 2>/dev/null; then
        format_log_message "$level" "$context" "$action" >> "$log_file"
    fi
}

# Validation logging
log_validation() {
    local check_name="$1"
    local result="$2"
    local context="VALIDATION"
    
    if [ "$result" = "pass" ]; then
        log_success "$context" "$check_name"
    else
        log_failure "$context" "$check_name"
    fi
}

# Export functions for use in other scripts
export -f log_debug log_info log_warn log_error
export -f log_step log_section log_success log_failure
export -f log_to_file log_validation