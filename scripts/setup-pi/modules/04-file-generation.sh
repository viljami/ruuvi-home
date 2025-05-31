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
    
    # Install required packages
    for package in "${REQUIREMENTS[@]}"; do
        log_debug "$context" "Installing: $package"
        if ! pip3 install "$package" --quiet; then
            log_error "$context" "Failed to install: $package"
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

# Main file generation function
setup_file_generation() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "install_generator_dependencies:Install generator dependencies"
        "create_runtime_config:Create runtime configuration"
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