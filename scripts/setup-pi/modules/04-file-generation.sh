#!/bin/bash
# Module: File Generation
# Description: Generates scripts and configuration files using Python templates
# Dependencies: 01-system-setup.sh (Python installation), 03-directories.sh (project structure)

set -e

# Module context for logging
readonly MODULE_CONTEXT="GENERATOR"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# Generator configuration
readonly GENERATOR_SCRIPT="$(dirname "$SCRIPT_DIR")/generator.py"
readonly REQUIREMENTS=(
    "pyyaml>=5.4.0"
    "jinja2>=3.0.0"
)

# Install Python dependencies for generator
install_generator_dependencies() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Installing Python dependencies for file generator"
    
    # Use system packages to avoid externally-managed-environment error
    local system_packages=(
        "python3-yaml"
        "python3-jinja2"
    )
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package lists first
    if ! apt-get update -qq; then
        log_error "$context" "Failed to update package lists"
        return 1
    fi
    
    # Install required system packages
    for package in "${system_packages[@]}"; do
        log_debug "$context" "Installing system package: $package"
        if ! apt-get install -y -qq "$package"; then
            log_error "$context" "Failed to install system package: $package"
            return 1
        fi
    done
    
    log_success "$context" "Generator dependencies installed"
    return 0
}

# Create runtime configuration for generator
create_runtime_config() {
    local context="$MODULE_CONTEXT"
    local runtime_config="/tmp/ruuvi-setup-config.yaml"
    
    log_info "$context" "Creating runtime configuration"
    
    # Create dynamic config by substituting environment variables
    cat > "$runtime_config" << EOF
# Runtime configuration for Ruuvi Home setup
ruuvi_user: "$RUUVI_USER"
project_dir: "$PROJECT_DIR"
data_dir: "$DATA_DIR"
log_dir: "$LOG_DIR"
backup_dir: "$BACKUP_DIR"
webhook_port: ${WEBHOOK_PORT:-9000}
webhook_secret: "${WEBHOOK_SECRET}"
frontend_port: ${FRONTEND_PORT:-80}
api_port: ${API_PORT:-3000}
db_port: ${DB_PORT:-5432}
db_user: "${DB_USER:-ruuvi}"
db_name: "${DB_NAME:-ruuvi_home}"
mosquitto_port: ${MOSQUITTO_PORT:-1883}
timezone: "${TZ:-Europe/Helsinki}"
python_venv: "$PROJECT_DIR/.venv"
postgres_password: "${POSTGRES_PASSWORD}"
mqtt_password: "${MQTT_PASSWORD}"
jwt_secret: "${JWT_SECRET}"
session_secret: "${SESSION_SECRET}"
EOF
    
    log_success "$context" "Runtime configuration created: $runtime_config"
    echo "$runtime_config"
    return 0
}

# Generate Python scripts
generate_python_scripts() {
    local context="$MODULE_CONTEXT"
    local config_file="$1"
    
    log_info "$context" "Generating Python scripts"
    
    if ! python3 "$GENERATOR_SCRIPT" "$config_file" --type python; then
        log_error "$context" "Failed to generate Python scripts"
        return 1
    fi
    
    log_success "$context" "Python scripts generated"
    return 0
}

# Generate shell scripts
generate_shell_scripts() {
    local context="$MODULE_CONTEXT"
    local config_file="$1"
    
    log_info "$context" "Generating shell scripts"
    
    if ! python3 "$GENERATOR_SCRIPT" "$config_file" --type shell; then
        log_error "$context" "Failed to generate shell scripts"
        return 1
    fi
    
    log_success "$context" "Shell scripts generated"
    return 0
}

# Generate systemd services
generate_systemd_services() {
    local context="$MODULE_CONTEXT"
    local config_file="$1"
    
    log_info "$context" "Generating systemd service files"
    
    if ! python3 "$GENERATOR_SCRIPT" "$config_file" --type systemd; then
        log_error "$context" "Failed to generate systemd services"
        return 1
    fi
    
    log_success "$context" "Systemd services generated"
    return 0
}



# Check for existing Mosquitto configuration
check_existing_mosquitto_config() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Checking for existing Mosquitto configuration"
    
    # Common locations for Mosquitto config
    local mosquitto_configs=(
        "/etc/mosquitto/mosquitto.conf"
        "/etc/mosquitto/conf.d"
        "/var/lib/mosquitto"
    )
    
    local found_configs=()
    
    for config_path in "${mosquitto_configs[@]}"; do
        if [ -e "$config_path" ]; then
            found_configs+=("$config_path")
        fi
    done
    
    if [ ${#found_configs[@]} -gt 0 ]; then
        log_info "$context" "Found existing Mosquitto configuration:"
        for config in "${found_configs[@]}"; do
            log_info "$context" "  - $config"
        done
        return 0
    else
        log_info "$context" "No existing Mosquitto configuration found"
        return 1
    fi
}

# Migrate existing Mosquitto configuration
migrate_mosquitto_config() {
    local context="$MODULE_CONTEXT"
    local backup_existing="${1:-true}"
    
    log_info "$context" "Migrating existing Mosquitto configuration"
    
    # Create backup directory
    local backup_dir="$PROJECT_DIR/config/mosquitto-backup"
    mkdir -p "$backup_dir"
    chown "$RUUVI_USER:$RUUVI_USER" "$backup_dir"
    
    # Backup existing configuration
    if [ "$backup_existing" = "true" ]; then
        log_info "$context" "Backing up existing Mosquitto configuration"
        
        if [ -f "/etc/mosquitto/mosquitto.conf" ]; then
            cp "/etc/mosquitto/mosquitto.conf" "$backup_dir/mosquitto.conf.backup"
            log_info "$context" "Backed up main config to $backup_dir/mosquitto.conf.backup"
        fi
        
        if [ -d "/etc/mosquitto/conf.d" ]; then
            cp -r "/etc/mosquitto/conf.d" "$backup_dir/"
            log_info "$context" "Backed up config directory to $backup_dir/conf.d/"
        fi
        
        if [ -d "/var/lib/mosquitto" ]; then
            # Only backup small config files, not large data files
            find "/var/lib/mosquitto" -name "*.conf" -o -name "*.acl" -o -name "*.passwd" | while read -r file; do
                cp "$file" "$backup_dir/"
            done
            log_info "$context" "Backed up Mosquitto data configs to $backup_dir/"
        fi
    fi
    
    # Create enhanced Mosquitto configuration
    local mosquitto_conf="$PROJECT_DIR/config/mosquitto/mosquitto.conf"
    mkdir -p "$(dirname "$mosquitto_conf")"
    
    cat > "$mosquitto_conf" << 'EOF'
# Mosquitto MQTT Broker configuration for Ruuvi Home
# Enhanced configuration with migration from existing setup

# Basic listener configuration
listener 1883 0.0.0.0
protocol mqtt

# WebSockets listener for web UI integration
listener 9001 0.0.0.0
protocol websockets

# Authentication and security
allow_anonymous true
# To enable authentication, uncomment and configure:
# allow_anonymous false
# password_file /mosquitto/config/passwd
# acl_file /mosquitto/config/acl

# Persistence settings
persistence true
persistence_location /mosquitto/data/
autosave_interval 1800

# Logging configuration
log_dest file /mosquitto/log/mosquitto.log
log_dest stdout
log_timestamp true
log_type error
log_type warning
log_type notice
log_type information
connection_messages true

# Performance and limits
max_connections -1
max_queued_messages 1000
max_inflight_messages 20
message_size_limit 268435456

# Ruuvi Gateway compatibility
# Common topic patterns used by Ruuvi gateways:
# - ruuvi/+/data
# - ruuvi/gateway/+
# - homeassistant/sensor/+

# Keep alive settings
keepalive_interval 60
EOF
    
    # If password file exists, create a template
    if [ -f "/etc/mosquitto/passwd" ] || [ -f "$backup_dir/passwd" ]; then
        log_info "$context" "Creating password file template"
        cat > "$PROJECT_DIR/config/mosquitto/passwd" << 'EOF'
# Mosquitto password file
# Generate passwords with: mosquitto_passwd -c passwd username
# Add users with: mosquitto_passwd passwd username
EOF
        
        # Copy existing passwords if available
        if [ -f "/etc/mosquitto/passwd" ]; then
            cat "/etc/mosquitto/passwd" >> "$PROJECT_DIR/config/mosquitto/passwd"
            log_info "$context" "Migrated existing password file"
        elif [ -f "$backup_dir/passwd" ]; then
            cat "$backup_dir/passwd" >> "$PROJECT_DIR/config/mosquitto/passwd"
            log_info "$context" "Restored password file from backup"
        fi
        
        # Update main config to use password file
        sed -i 's/allow_anonymous true/allow_anonymous false/' "$mosquitto_conf"
        sed -i 's/# password_file/password_file/' "$mosquitto_conf"
    fi
    
    # If ACL file exists, create a template
    if [ -f "/etc/mosquitto/acl" ] || [ -f "$backup_dir/acl" ]; then
        log_info "$context" "Creating ACL file template"
        cat > "$PROJECT_DIR/config/mosquitto/acl" << 'EOF'
# Mosquitto Access Control List
# Format: topic [read|write] <topic>
#         user <username>

# Allow all users to access Ruuvi topics
topic readwrite ruuvi/#
topic readwrite homeassistant/#

# Admin user with full access
user admin
topic readwrite #
EOF
        
        # Copy existing ACL if available
        if [ -f "/etc/mosquitto/acl" ]; then
            echo "# --- Migrated from existing configuration ---" >> "$PROJECT_DIR/config/mosquitto/acl"
            cat "/etc/mosquitto/acl" >> "$PROJECT_DIR/config/mosquitto/acl"
            log_info "$context" "Migrated existing ACL file"
        elif [ -f "$backup_dir/acl" ]; then
            echo "# --- Restored from backup ---" >> "$PROJECT_DIR/config/mosquitto/acl"
            cat "$backup_dir/acl" >> "$PROJECT_DIR/config/mosquitto/acl"
            log_info "$context" "Restored ACL file from backup"
        fi
        
        # Update main config to use ACL file
        sed -i 's/# acl_file/acl_file/' "$mosquitto_conf"
    fi
    
    # Set proper ownership
    chown -R "$RUUVI_USER:$RUUVI_USER" "$PROJECT_DIR/config/mosquitto"
    chmod 644 "$mosquitto_conf"
    [ -f "$PROJECT_DIR/config/mosquitto/passwd" ] && chmod 600 "$PROJECT_DIR/config/mosquitto/passwd"
    [ -f "$PROJECT_DIR/config/mosquitto/acl" ] && chmod 644 "$PROJECT_DIR/config/mosquitto/acl"
    
    log_success "$context" "Mosquitto configuration migrated successfully"
    log_info "$context" "Original configuration backed up to: $backup_dir"
    log_info "$context" "New configuration: $mosquitto_conf"
    
    return 0
}



# Generate configuration files
generate_configuration_files() {
    local context="$MODULE_CONTEXT"
    local config_file="$1"
    
    log_info "$context" "Generating configuration files"
    
    if ! python3 "$GENERATOR_SCRIPT" "$config_file" --type config; then
        log_error "$context" "Failed to generate configuration files"
        return 1
    fi
    
    log_success "$context" "Configuration files generated"
    return 0
}

# Set proper permissions on generated files
set_file_permissions() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Setting file permissions"
    
    # Set permissions on scripts
    if [ -d "$PROJECT_DIR/scripts" ]; then
        find "$PROJECT_DIR/scripts" -name "*.py" -exec chmod 755 {} \;
        find "$PROJECT_DIR/scripts" -name "*.sh" -exec chmod 755 {} \;
        chown -R "$RUUVI_USER:$RUUVI_USER" "$PROJECT_DIR/scripts"
    fi
    
    # Set permissions on configuration files
    if [ -f "$PROJECT_DIR/.env" ]; then
        chmod 600 "$PROJECT_DIR/.env"
        chown "$RUUVI_USER:$RUUVI_USER" "$PROJECT_DIR/.env"
    fi
    
    if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        chmod 644 "$PROJECT_DIR/docker-compose.yml"
        chown "$RUUVI_USER:$RUUVI_USER" "$PROJECT_DIR/docker-compose.yml"
    fi
    
    # Set permissions on systemd services
    if [ -f "/etc/systemd/system/ruuvi-home.service" ]; then
        chmod 644 "/etc/systemd/system/ruuvi-home.service"
        chown root:root "/etc/systemd/system/ruuvi-home.service"
    fi
    
    if [ -f "/etc/systemd/system/ruuvi-webhook.service" ]; then
        chmod 644 "/etc/systemd/system/ruuvi-webhook.service"
        chown root:root "/etc/systemd/system/ruuvi-webhook.service"
    fi
    
    log_success "$context" "File permissions set"
    return 0
}

# Validate generated files
validate_generated_files() {
    local context="$MODULE_CONTEXT"
    local required_files=(
        "$PROJECT_DIR/scripts/deploy-webhook.py"
        "$PROJECT_DIR/scripts/deploy.sh"
        "$PROJECT_DIR/scripts/backup.sh"
        "$PROJECT_DIR/.env"
        "$PROJECT_DIR/docker-compose.yml"
        "/etc/systemd/system/ruuvi-home.service"
        "/etc/systemd/system/ruuvi-webhook.service"
    )
    
    log_info "$context" "Validating generated files"
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "$context" "Required file not generated: $file"
            return 1
        fi
        
        # Basic syntax check for Python files
        if [[ "$file" == *.py ]]; then
            if ! python3 -m py_compile "$file"; then
                log_error "$context" "Python syntax error in: $file"
                return 1
            fi
        fi
        
        # Basic syntax check for shell files
        if [[ "$file" == *.sh ]]; then
            if ! bash -n "$file"; then
                log_error "$context" "Shell syntax error in: $file"
                return 1
            fi
        fi
    done
    
    log_success "$context" "All generated files validated"
    return 0
}

# Handle Mosquitto configuration migration
handle_mosquitto_migration() {
    local context="$MODULE_CONTEXT"
    
    if check_existing_mosquitto_config; then
        echo ""
        echo "=========================================="
        echo "   Existing Mosquitto Configuration"
        echo "=========================================="
        echo ""
        echo "An existing Mosquitto MQTT broker configuration was found on this system."
        echo "This configuration may contain important settings for your Ruuvi Gateway."
        echo ""
        echo "Options:"
        echo "  1) Migrate existing configuration (Recommended)"
        echo "     - Backup current config and integrate it with Ruuvi Home"
        echo "     - Preserve authentication, ACLs, and custom settings"
        echo ""
        echo "  2) Use default Ruuvi Home configuration"
        echo "     - Start fresh with standard settings"
        echo "     - You can manually configure later if needed"
        echo ""
        
        while true; do
            read -p "Would you like to migrate your existing Mosquitto configuration? (y/N): " response
            case "$response" in
                [Yy]|[Yy][Ee][Ss])
                    log_info "$context" "User chose to migrate existing configuration"
                    if migrate_mosquitto_config true; then
                        echo ""
                        echo "✓ Mosquitto configuration migrated successfully!"
                        echo "  - Original config backed up to: $PROJECT_DIR/config/mosquitto-backup/"
                        echo "  - Enhanced config created at: $PROJECT_DIR/config/mosquitto/"
                        echo ""
                    else
                        log_error "$context" "Failed to migrate Mosquitto configuration"
                        return 1
                    fi
                    break
                    ;;
                [Nn]|[Nn][Oo]|"")
                    log_info "$context" "User chose to use default configuration"
                    echo ""
                    echo "Using default Ruuvi Home Mosquitto configuration."
                    echo "Your existing config is preserved and can be manually integrated later."
                    echo ""
                    break
                    ;;
                *)
                    echo "Please answer yes (y) or no (n)."
                    ;;
            esac
        done
    else
        log_info "$context" "No existing Mosquitto configuration found, using defaults"
    fi
    
    return 0
}

# Main file generation function
setup_file_generation() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "install_generator_dependencies:Install generator dependencies"
        "create_runtime_config:Create runtime configuration"
        "handle_mosquitto_migration:Handle Mosquitto migration"
        "generate_python_scripts:Generate Python scripts"
        "generate_shell_scripts:Generate shell scripts"
        "generate_systemd_services:Generate systemd services"
        "generate_configuration_files:Generate configuration files"
        "set_file_permissions:Set file permissions"
        "validate_generated_files:Validate generated files"
    )
    
    log_section "File Generation"
    log_info "$context" "Generating files for user: $RUUVI_USER"
    
    local step_num=1
    local total_steps=${#setup_steps[@]}
    local failed_steps=()
    local runtime_config=""
    
    for step in "${setup_steps[@]}"; do
        local func_name="${step%:*}"
        local step_desc="${step#*:}"
        
        log_step "$step_num" "$total_steps" "$step_desc"
        
        case "$func_name" in
            "create_runtime_config")
                if runtime_config=$(create_runtime_config); then
                    log_debug "$context" "Runtime config: $runtime_config"
                else
                    failed_steps+=("$step_desc")
                fi
                ;;
            "generate_python_scripts"|"generate_shell_scripts"|"generate_systemd_services"|"generate_configuration_files")
                if [ -n "$runtime_config" ]; then
                    if ! $func_name "$runtime_config"; then
                        failed_steps+=("$step_desc")
                    fi
                else
                    log_error "$context" "Runtime config not available for $func_name"
                    failed_steps+=("$step_desc")
                fi
                ;;
            *)
                if ! $func_name; then
                    failed_steps+=("$step_desc")
                fi
                ;;
        esac
        
        ((step_num++))
    done
    
    # Cleanup runtime config
    if [ -n "$runtime_config" ] && [ -f "$runtime_config" ]; then
        rm -f "$runtime_config"
    fi
    
    if [ ${#failed_steps[@]} -gt 0 ]; then
        log_error "$context" "File generation failed at: ${failed_steps[*]}"
        return 1
    fi
    
    log_success "$context" "File generation completed successfully"
    return 0
}

# Export main function
export -f setup_file_generation

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_file_generation
fi