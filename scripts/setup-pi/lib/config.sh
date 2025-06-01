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

# External IP Detection Services (in priority order)
readonly EXTERNAL_IP_SERVICES=(
    "ifconfig.me"
    "ipinfo.io/ip"
    "api.ipify.org"
    "checkip.amazonaws.com"
    "ipecho.net/plain"
    "icanhazip.com"
    "ident.me"
    "whatismyipaddress.com/api/ip"
)

# Validate IP address format
is_valid_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Check each octet is <= 255
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Detect external/public IP with multiple fallback services
detect_external_ip() {
    local context="CONFIG"
    local external_ip=""
    local timeout="${1:-5}"
    local max_retries="${2:-2}"

    log_info "$context" "Detecting external IP address..."

    # Try each service with retries
    for service in "${EXTERNAL_IP_SERVICES[@]}"; do
        log_info "$context" "Trying service: $service"

        local retry=0
        while [ $retry -lt $max_retries ]; do
            # Try to get IP from service
            local detected_ip=""
            if command -v curl >/dev/null 2>&1; then
                detected_ip=$(curl -s --connect-timeout "$timeout" --max-time "$((timeout * 2))" "$service" 2>/dev/null | tr -d '[:space:]')
            elif command -v wget >/dev/null 2>&1; then
                detected_ip=$(wget -qO- --timeout="$timeout" "$service" 2>/dev/null | tr -d '[:space:]')
            else
                log_warn "$context" "Neither curl nor wget available for IP detection"
                break 2
            fi

            # Validate the response
            if [ -n "$detected_ip" ] && is_valid_ip "$detected_ip"; then
                external_ip="$detected_ip"
                log_success "$context" "External IP detected: $external_ip (via $service)"
                echo "$external_ip"
                return 0
            fi

            ((retry++))
            if [ $retry -lt $max_retries ]; then
                log_warn "$context" "Invalid response from $service (attempt $retry/$max_retries), retrying..."
                sleep 1
            fi
        done

        log_warn "$context" "Service $service failed after $max_retries attempts"
    done

    log_error "$context" "Failed to detect external IP from all services"
    return 1
}

# Detect local IP with cross-platform compatibility
detect_local_ip() {
    local local_ip=""

    # Method 1: hostname -I (Linux)
    if [ -z "$local_ip" ]; then
        local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
    fi

    # Method 2: ifconfig (macOS/Linux)
    if [ -z "$local_ip" ] && command -v ifconfig >/dev/null 2>&1; then
        local_ip=$(ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -1 | sed 's/addr://' || echo "")
    fi

    # Method 3: ip route (Linux)
    if [ -z "$local_ip" ] && command -v ip >/dev/null 2>&1; then
        local_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}' || echo "")
    fi

    # Method 4: netstat (fallback)
    if [ -z "$local_ip" ] && command -v netstat >/dev/null 2>&1; then
        local_ip=$(netstat -rn 2>/dev/null | grep '^default' | awk '{print $NF}' | head -1 || echo "")
        if [ -n "$local_ip" ] && command -v ifconfig >/dev/null 2>&1; then
            local_ip=$(ifconfig "$local_ip" 2>/dev/null | grep -E 'inet [0-9]' | awk '{print $2}' | sed 's/addr://' || echo "")
        fi
    fi

    # Validate the detected IP
    if [ -n "$local_ip" ] && is_valid_ip "$local_ip"; then
        echo "$local_ip"
    else
        echo "127.0.0.1"
    fi
}

# Enhanced Network Configuration Detection
detect_network_configuration() {
    local context="CONFIG"
    local local_ip=$(detect_local_ip)
    local hostname=$(hostname 2>/dev/null || echo "raspberrypi")

    log_info "$context" "Detecting network configuration"

    # Detect external IP with robust fallback
    local external_ip=""
    if external_ip=$(detect_external_ip 3 2); then
        log_success "$context" "External IP detection successful"
    else
        log_warn "$context" "External IP detection failed, using local IP as fallback"
        external_ip="$local_ip"
    fi

    # Export for use by other modules
    export DETECTED_LOCAL_IP="$local_ip"
    export DETECTED_EXTERNAL_IP="$external_ip"
    export DETECTED_HOSTNAME="$hostname"

    # Determine network scenario and best public IP
    if [ "$external_ip" != "$local_ip" ] && [ "$external_ip" != "localhost" ] && is_valid_ip "$external_ip"; then
        export DETECTED_PUBLIC_IP="$external_ip"
        export NETWORK_SCENARIO="nat"
        log_info "$context" "Network scenario: NAT (behind router/firewall)"
        log_info "$context" "Local IP: $local_ip, Public IP: $external_ip"
        log_warn "$context" "Port forwarding will be required for external access"
    else
        export DETECTED_PUBLIC_IP="$local_ip"
        export NETWORK_SCENARIO="direct"
        log_info "$context" "Network scenario: Direct connection or local-only"
        log_info "$context" "Using local IP: $local_ip"
    fi

    # Additional network diagnostics
    log_info "$context" "Network summary:"
    log_info "$context" "  Hostname: $hostname"
    log_info "$context" "  Local IP: $local_ip"
    log_info "$context" "  External IP: $external_ip"
    log_info "$context" "  Public IP (for webhooks): $DETECTED_PUBLIC_IP"
    log_info "$context" "  Scenario: $NETWORK_SCENARIO"
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
