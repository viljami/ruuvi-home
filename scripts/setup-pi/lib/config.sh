#!/bin/bash
# Shared Configuration Library
# Single source of truth for all configuration values and construction logic
# Eliminates DRY violations by centralizing configuration management

set -e

# Simple logging functions for config library independence
log_info() {
    local context="${1:-CONFIG}"
    local message="${2:-$1}"
    echo "[INFO][$context] $message" >&2
}

log_warn() {
    local context="${1:-CONFIG}"
    local message="${2:-$1}"
    echo "[WARN][$context] $message" >&2
}

log_error() {
    local context="${1:-CONFIG}"
    local message="${2:-$1}"
    echo "[ERROR][$context] $message" >&2
}

log_success() {
    local context="${1:-CONFIG}"
    local message="${2:-$1}"
    echo "[SUCCESS][$context] $message" >&2
}

# Default Configuration Values
readonly DEFAULT_POSTGRES_USER="ruuvi"
readonly DEFAULT_POSTGRES_DB="ruuvi_home"
readonly DEFAULT_POSTGRES_HOST="timescaledb"
readonly DEFAULT_POSTGRES_PORT="5432"

readonly DEFAULT_AUTH_USER="auth_user"
readonly DEFAULT_AUTH_DB="auth"
readonly DEFAULT_AUTH_HOST="auth-db"
readonly DEFAULT_AUTH_PORT="5432"

readonly DEFAULT_MQTT_HOST="mosquitto"
readonly DEFAULT_MQTT_PORT="1883"
readonly DEFAULT_MQTT_USER="ruuvi"

readonly DEFAULT_API_PORT="3000"
readonly DEFAULT_FRONTEND_PORT="80"
readonly DEFAULT_WEBHOOK_PORT="9000"

readonly DEFAULT_TIMEZONE="Europe/Helsinki"
readonly DEFAULT_LOG_LEVEL="info"

# User Detection and Validation
detect_target_user() {
    local detected_user=""
    local context="CONFIG"

    # Priority order for user detection:
    # 1. RUUVI_USER if explicitly set and valid
    # 2. SUDO_USER if running with sudo and user exists
    # 3. USER if running normally and user exists
    # 4. Current user from whoami
    # 5. Fallback to common usernames

    if [ -n "${RUUVI_USER:-}" ] && id "$RUUVI_USER" &>/dev/null; then
        detected_user="$RUUVI_USER"
        log_info "$context" "Using explicitly set RUUVI_USER: $detected_user"
    elif [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        detected_user="$SUDO_USER"
        log_info "$context" "Detected user from SUDO_USER: $detected_user"
    elif [ -n "${USER:-}" ] && id "$USER" &>/dev/null; then
        detected_user="$USER"
        log_info "$context" "Using current USER: $detected_user"
    else
        # Try whoami as fallback
        local current_user=$(whoami 2>/dev/null || echo "")
        if [ -n "$current_user" ] && id "$current_user" &>/dev/null; then
            detected_user="$current_user"
            log_info "$context" "Detected user from whoami: $detected_user"
        else
            # Last resort: try common usernames
            for fallback_user in pi ubuntu debian admin; do
                if id "$fallback_user" &>/dev/null; then
                    detected_user="$fallback_user"
                    log_warn "$context" "Using fallback user: $detected_user"
                    break
                fi
            done
        fi
    fi

    if [ -z "$detected_user" ]; then
        log_error "$context" "Could not detect valid user - manual intervention required"
        echo "Available users:" >&2
        getent passwd | cut -d: -f1 | grep -E "^(pi|ubuntu|debian|admin|[a-z][a-z0-9_-]*)" | head -10 >&2
        echo "Please set RUUVI_USER environment variable to the target user" >&2
        return 1
    fi

    export RUUVI_USER="$detected_user"
    export RUUVI_HOME="/home/$detected_user"
    export PROJECT_DIR="${PROJECT_DIR:-$RUUVI_HOME/ruuvi-home}"

    return 0
}

validate_user_environment() {
    local context="CONFIG"

    if [ -z "${RUUVI_USER:-}" ]; then
        log_error "$context" "RUUVI_USER not set - call detect_target_user first"
        return 1
    fi

    # Validate user exists
    if ! id "$RUUVI_USER" &>/dev/null; then
        log_error "$context" "User does not exist: $RUUVI_USER"
        return 1
    fi

    # Validate home directory exists
    if [ ! -d "$RUUVI_HOME" ]; then
        log_error "$context" "Home directory does not exist: $RUUVI_HOME"
        log_info "$context" "Creating home directory..."
        if ! mkdir -p "$RUUVI_HOME"; then
            log_error "$context" "Failed to create home directory: $RUUVI_HOME"
            return 1
        fi
        chown "$RUUVI_USER:$RUUVI_USER" "$RUUVI_HOME"
    fi

    # Validate home directory permissions
    if [ ! -w "$RUUVI_HOME" ]; then
        log_warn "$context" "Home directory not writable: $RUUVI_HOME"
        log_info "$context" "Attempting to fix permissions..."
        chown "$RUUVI_USER:$RUUVI_USER" "$RUUVI_HOME"
    fi

    log_success "$context" "User environment validated: $RUUVI_USER"
    return 0
}

# Get user's primary group
get_user_group() {
    local user="${1:-$RUUVI_USER}"
    id -gn "$user" 2>/dev/null || echo "$user"
}

# Check if current process can write to user's home
can_write_to_user_home() {
    local user="${1:-$RUUVI_USER}"
    local home_dir="/home/$user"

    if [ -w "$home_dir" ]; then
        return 0
    elif [ "$EUID" -eq 0 ]; then
        # Running as root, can write anywhere
        return 0
    else
        return 1
    fi
}

# Database URL Construction
construct_database_url() {
    local user="${1:-$DEFAULT_POSTGRES_USER}"
    local password="${2:-${POSTGRES_PASSWORD}}"
    local host="${3:-$DEFAULT_POSTGRES_HOST}"
    local port="${4:-$DEFAULT_POSTGRES_PORT}"
    local db="${5:-$DEFAULT_POSTGRES_DB}"

    echo "postgresql://${user}:${password}@${host}:${port}/${db}"
}

construct_auth_database_url() {
    local user="${1:-$DEFAULT_AUTH_USER}"
    local password="${2:-${AUTH_DB_PASSWORD}}"
    local host="${3:-$DEFAULT_AUTH_HOST}"
    local port="${4:-$DEFAULT_AUTH_PORT}"
    local db="${5:-$DEFAULT_AUTH_DB}"

    echo "postgresql://${user}:${password}@${host}:${port}/${db}"
}

# MQTT URL Construction
construct_mqtt_url() {
    local host="${1:-$DEFAULT_MQTT_HOST}"
    local port="${2:-$DEFAULT_MQTT_PORT}"

    echo "mqtt://${host}:${port}"
}

construct_mqtt_authenticated_url() {
    local user="${1:-$DEFAULT_MQTT_USER}"
    local password="${2:-${MQTT_PASSWORD}}"
    local host="${3:-$DEFAULT_MQTT_HOST}"
    local port="${4:-$DEFAULT_MQTT_PORT}"

    echo "mqtt://${user}:${password}@${host}:${port}"
}

# Network Configuration
detect_network_configuration() {
    local local_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    local external_ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo "$local_ip")
    local hostname=$(hostname 2>/dev/null || echo "raspberrypi")

    # Export for use by other modules
    export DETECTED_LOCAL_IP="$local_ip"
    export DETECTED_EXTERNAL_IP="$external_ip"
    export DETECTED_HOSTNAME="$hostname"

    # Determine best public IP
    if [ "$external_ip" != "$local_ip" ] && [ "$external_ip" != "unknown" ]; then
        export DETECTED_PUBLIC_IP="$external_ip"
        export NETWORK_SCENARIO="nat"
    else
        export DETECTED_PUBLIC_IP="$local_ip"
        export NETWORK_SCENARIO="direct"
    fi
}

# URL Construction
construct_public_api_url() {
    local protocol="${1:-https}"
    local host="${2:-${DETECTED_PUBLIC_IP}}"
    local port="${3:-${DEFAULT_API_PORT}}"

    echo "${protocol}://${host}:${port}"
}

construct_public_frontend_url() {
    local protocol="${1:-https}"
    local host="${2:-${DETECTED_PUBLIC_IP}}"
    local port="${3:-${DEFAULT_FRONTEND_PORT}}"

    echo "${protocol}://${host}:${port}"
}

# CORS Configuration
construct_cors_origins() {
    local primary_origin="${1:-${PUBLIC_FRONTEND_URL}}"

    if [[ "$primary_origin" == "*" ]]; then
        echo "*"
    else
        echo "${primary_origin},http://localhost:3000,http://127.0.0.1:3000,https://localhost:3000,https://127.0.0.1:3000"
    fi
}

# Environment Variable Reading Utilities
read_env_var() {
    local var_name="$1"
    local env_file="${2:-${PROJECT_DIR}/.env}"
    local default_value="${3:-}"

    if [ -f "$env_file" ]; then
        grep "^${var_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2- || echo "$default_value"
    else
        echo "$default_value"
    fi
}

# Configuration Validation
validate_required_vars() {
    local vars=("$@")
    local missing=()

    for var in "${vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required variables: ${missing[*]}" >&2
        return 1
    fi

    return 0
}

# Security Configuration
get_secure_file_permissions() {
    echo "0o600"
}

get_standard_file_permissions() {
    echo "0o644"
}

get_script_permissions() {
    echo "0o755"
}

# Service Configuration
get_service_ports() {
    cat << EOF
{
    "webhook": ${WEBHOOK_PORT:-$DEFAULT_WEBHOOK_PORT},
    "frontend": ${FRONTEND_PORT:-$DEFAULT_FRONTEND_PORT},
    "api": ${API_PORT:-$DEFAULT_API_PORT},
    "database": ${POSTGRES_PORT:-$DEFAULT_POSTGRES_PORT},
    "mosquitto": ${MQTT_PORT:-$DEFAULT_MQTT_PORT}
}
EOF
}

# Docker Configuration Helpers
get_docker_restart_policy() {
    echo "unless-stopped"
}

get_docker_log_config() {
    cat << EOF
{
    "driver": "json-file",
    "options": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
}

# Backup Configuration
get_backup_config() {
    cat << EOF
{
    "retention_days": 30,
    "schedule": "0 2 * * *",
    "enabled": true
}
EOF
}

# Monitoring Configuration
get_monitoring_config() {
    cat << EOF
{
    "health_check_interval": 30,
    "log_retention_days": 14,
    "alert_thresholds": {
        "cpu_usage": 80,
        "memory_usage": 85,
        "disk_usage": 90
    }
}
EOF
}

# Production Environment Settings
get_production_env_vars() {
    cat << EOF
NODE_ENV=production
RUST_BACKTRACE=0
TIMESCALEDB_TELEMETRY=off
EOF
}

# Initialization function to set up all derived configuration
initialize_configuration() {
    # Detect network first
    detect_network_configuration

    # Set up derived URLs if not already set
    export DATABASE_URL="${DATABASE_URL:-$(construct_database_url)}"
    export AUTH_DATABASE_URL="${AUTH_DATABASE_URL:-$(construct_auth_database_url)}"
    export MQTT_BROKER_URL="${MQTT_BROKER_URL:-$(construct_mqtt_url)}"
    export PUBLIC_API_URL="${PUBLIC_API_URL:-$(construct_public_api_url)}"
    export PUBLIC_FRONTEND_URL="${PUBLIC_FRONTEND_URL:-$(construct_public_frontend_url)}"
    export CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-$(construct_cors_origins)}"

    # Set default ports
    export WEBHOOK_PORT="${WEBHOOK_PORT:-$DEFAULT_WEBHOOK_PORT}"
    export API_PORT="${API_PORT:-$DEFAULT_API_PORT}"
    export FRONTEND_PORT="${FRONTEND_PORT:-$DEFAULT_FRONTEND_PORT}"
    export POSTGRES_PORT="${POSTGRES_PORT:-$DEFAULT_POSTGRES_PORT}"
    export MQTT_PORT="${MQTT_PORT:-$DEFAULT_MQTT_PORT}"

    # Set system defaults
    export TZ="${TZ:-$DEFAULT_TIMEZONE}"
    export LOG_LEVEL="${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"
}
