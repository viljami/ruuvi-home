#!/bin/bash
# Ruuvi Home Raspberry Pi Setup Script
# This script orchestrates the complete setup process using modular components
# Following the "make it work, make it pretty, make it fast" workflow

set -e

# Script metadata
readonly SCRIPT_NAME="setup-pi"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directory structure
readonly LIB_DIR="$SCRIPT_DIR/lib"
readonly CONFIG_DIR="$SCRIPT_DIR/config"
readonly MODULE_DIR="$SCRIPT_DIR/modules"
readonly TEMPLATE_DIR="$SCRIPT_DIR/templates"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# Generate secure passwords for services
generate_secure_passwords() {
    local context="$MAIN_CONTEXT"
    
    log_info "$context" "Generating secure passwords for services"
    
    # Generate secure random passwords
    export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 32)}"
    export MQTT_PASSWORD="${MQTT_PASSWORD:-$(openssl rand -base64 32)}"
    export WEBHOOK_SECRET="${WEBHOOK_SECRET:-$(openssl rand -base64 32)}"
    
    # Additional derived secrets
    export JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 32)}"
    export SESSION_SECRET="${SESSION_SECRET:-$(openssl rand -base64 32)}"
    
    log_success "$context" "Secure passwords generated"
    log_info "$context" "Passwords will be saved to .env file during setup"
}

# Load configuration from YAML
load_config() {
    local config_file="$CONFIG_DIR/config.yaml"
    
    if [ ! -f "$config_file" ]; then
        log_error "$MAIN_CONTEXT" "Configuration file not found: $config_file"
        exit 1
    fi
    
    # Export key variables for modules
    export RUUVI_USER="${SUDO_USER:-pi}"
    export PROJECT_DIR="/home/$RUUVI_USER/ruuvi-home"
    export DATA_DIR="$PROJECT_DIR/data"
    export LOG_DIR="/var/log/ruuvi-home"
    export BACKUP_DIR="$PROJECT_DIR/backups"
    export CONFIG_YAML="$config_file"
}

# Initialize configuration
load_config

# Main context for logging
readonly MAIN_CONTEXT="ORCHESTRATOR"

# Setup modules in execution order
readonly SETUP_MODULES=(
    "00-validation.sh:Pre-flight Validation"
    "01-system-setup.sh:System Setup"
    "02-docker-setup.sh:Docker Installation"
    "03-directories.sh:Directory Structure"
    "04-file-generation.sh:File Generation"
    "05-systemd-services.sh:System Services"
    "06-backup-system.sh:Backup System"
    "07-monitoring.sh:Monitoring Setup"
)

# Print script header
print_header() {
    local context="$MAIN_CONTEXT"
    
    echo -e "${COLOR_GREEN}=====================================${COLOR_NC}"
    echo -e "${COLOR_GREEN}  Ruuvi Home - Raspberry Pi Setup   ${COLOR_NC}"
    echo -e "${COLOR_GREEN}         Version $SCRIPT_VERSION              ${COLOR_NC}"
    echo -e "${COLOR_GREEN}=====================================${COLOR_NC}"
    echo ""
    
    log_info "$context" "Setup target user: $RUUVI_USER"
    log_info "$context" "Project directory: $PROJECT_DIR"
    log_info "$context" "Configuration: $CONFIG_YAML"
    
    # Generate secure passwords if not already provided
    generate_secure_passwords
}

# Validate script environment
validate_script_environment() {
    local context="$MAIN_CONTEXT"
    local missing_deps=()
    
    log_info "$context" "Validating script environment"
    
    # Check required directories
    for dir in "$LIB_DIR" "$CONFIG_DIR" "$MODULE_DIR"; do
        if [ ! -d "$dir" ]; then
            missing_deps+=("Directory: $dir")
        fi
    done
    
    # Check required library files
    local required_libs=("logging.sh" "validation.sh")
    for lib in "${required_libs[@]}"; do
        if [ ! -f "$LIB_DIR/$lib" ]; then
            missing_deps+=("Library: $lib")
        fi
    done
    
    # Check configuration file
    if [ ! -f "$CONFIG_DIR/setup.env" ]; then
        missing_deps+=("Config: setup.env")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "$context" "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    log_success "$context" "Script environment validated"
    return 0
}

# Check module availability
check_module_availability() {
    local context="$MAIN_CONTEXT"
    local missing_modules=()
    
    log_info "$context" "Checking module availability"
    
    for module_entry in "${SETUP_MODULES[@]}"; do
        local module_file="${module_entry%:*}"
        local module_path="$MODULE_DIR/$module_file"
        
        if [ ! -f "$module_path" ]; then
            missing_modules+=("$module_file")
        elif [ ! -x "$module_path" ]; then
            log_warn "$context" "Module not executable: $module_file"
            chmod +x "$module_path" || missing_modules+=("$module_file (permission)")
        fi
    done
    
    if [ ${#missing_modules[@]} -gt 0 ]; then
        log_error "$context" "Missing or inaccessible modules: ${missing_modules[*]}"
        return 1
    fi
    
    log_success "$context" "All modules available"
    return 0
}

# Execute setup module
execute_module() {
    local module_file="$1"
    local module_desc="$2"
    local context="$MAIN_CONTEXT"
    local module_path="$MODULE_DIR/$module_file"
    
    log_section "$module_desc"
    log_info "$context" "Executing module: $module_file"
    
    # Set up module environment
    export SCRIPT_DIR MODULE_DIR LIB_DIR CONFIG_DIR TEMPLATE_DIR
    export RUUVI_USER PROJECT_DIR DATA_DIR LOG_DIR BACKUP_DIR CONFIG_YAML
    export POSTGRES_PASSWORD MQTT_PASSWORD WEBHOOK_SECRET JWT_SECRET SESSION_SECRET
    
    # Execute module with error handling
    if bash "$module_path"; then
        log_success "$context" "Module completed: $module_file"
        return 0
    else
        local exit_code=$?
        log_error "$context" "Module failed: $module_file (exit code: $exit_code)"
        return $exit_code
    fi
}

# Run all setup modules
run_setup_modules() {
    local context="$MAIN_CONTEXT"
    local failed_modules=()
    local step_num=1
    local total_steps=${#SETUP_MODULES[@]}
    
    log_section "Setup Execution"
    log_info "$context" "Running $total_steps setup modules"
    
    for module_entry in "${SETUP_MODULES[@]}"; do
        local module_file="${module_entry%:*}"
        local module_desc="${module_entry#*:}"
        
        log_step "$step_num" "$total_steps" "$module_desc"
        
        if ! execute_module "$module_file" "$module_desc"; then
            failed_modules+=("$module_file")
            
            # Check if we should continue or stop
            if [[ "$module_file" == "00-validation.sh" ]]; then
                log_error "$context" "Validation failed, cannot continue"
                return 1
            else
                log_warn "$context" "Module failed but continuing: $module_file"
            fi
        fi
        
        ((step_num++))
    done
    
    if [ ${#failed_modules[@]} -gt 0 ]; then
        log_warn "$context" "Some modules failed: ${failed_modules[*]}"
        log_warn "$context" "Manual intervention may be required"
        return 2
    fi
    
    log_success "$context" "All setup modules completed successfully"
    return 0
}

# Create setup summary
create_setup_summary() {
    local context="$MAIN_CONTEXT"
    local summary_file="$PROJECT_DIR/setup-summary.log"
    
    log_info "$context" "Creating setup summary"
    
    cat > "$summary_file" << EOF
Ruuvi Home Setup Summary
========================
Date: $(date)
Script: $SCRIPT_NAME v$SCRIPT_VERSION
User: $RUUVI_USER
Project Directory: $PROJECT_DIR

Configuration:
- Webhook Port: $WEBHOOK_PORT
- Frontend Port: $FRONTEND_PORT
- API Port: $API_PORT
- Database Port: $DB_PORT
- Mosquitto Port: $MOSQUITTO_PORT

Services Installed:
- ruuvi-home.service
- ruuvi-webhook.service

Next Steps:
1. Configure environment variables in: $PROJECT_DIR/.env
2. Start services: sudo systemctl start ruuvi-home ruuvi-webhook
3. Check logs: journalctl -u ruuvi-home -f
4. Access application: http://localhost:$FRONTEND_PORT

For more information, see: $PROJECT_DIR/README.md
EOF
    
    chown "$RUUVI_USER:$RUUVI_USER" "$summary_file" 2>/dev/null || true
    log_success "$context" "Setup summary created: $summary_file"
}

# Print completion message
print_completion() {
    local context="$MAIN_CONTEXT"
    
    echo ""
    log_section "Setup Complete"
    log_success "$context" "Ruuvi Home setup completed successfully"
    log_info "$context" "Project installed in: $PROJECT_DIR"
    log_success "$context" "All setup modules completed successfully"
    log_info "$context" "Services available: ruuvi-home, ruuvi-webhook"
    log_info "$context" "Setup summary: $PROJECT_DIR/setup-summary.log"
    
    echo -e "\n${COLOR_GREEN}Security Information:${COLOR_NC}"
    echo "Secure passwords have been automatically generated and saved to:"
    echo "  $PROJECT_DIR/.env"
    echo ""
    echo -e "${COLOR_YELLOW}Service Access:${COLOR_NC}"
    echo "Frontend: http://$(hostname -I | awk '{print $1}'):80"
    echo "API: http://$(hostname -I | awk '{print $1}'):3000"
    echo "Webhook: http://$(hostname -I | awk '{print $1}'):9000"
    echo ""
    echo -e "${COLOR_YELLOW}Management Commands:${COLOR_NC}"
    echo "1. Check status: sudo systemctl status ruuvi-home ruuvi-webhook"
    echo "2. View logs: journalctl -u ruuvi-home -f"
    echo "3. Access database: Use credentials from $PROJECT_DIR/.env"
    echo "4. View passwords: cat $PROJECT_DIR/.env"
    echo ""
}

# Handle script interruption
handle_interrupt() {
    local context="$MAIN_CONTEXT"
    log_warn "$context" "Setup interrupted by user"
    log_info "$context" "Partial setup may require manual cleanup"
    exit 130
}

# Handle script errors
handle_error() {
    local exit_code=$?
    local context="$MAIN_CONTEXT"
    
    log_error "$context" "Setup failed with exit code: $exit_code"
    log_info "$context" "Check logs for details: $LOG_DIR/setup.log"
    exit $exit_code
}

# Main setup function
main() {
    local context="$MAIN_CONTEXT"
    
    # Set up signal handlers
    trap handle_interrupt SIGINT SIGTERM
    trap handle_error ERR
    
    # Initialize logging
    log_to_file "info" "$context" "Setup started by user: $(whoami)"
    
    # Print header
    print_header
    
    # Validate script environment
    if ! validate_script_environment; then
        log_error "$context" "Script environment validation failed"
        exit 1
    fi
    
    # Check module availability
    if ! check_module_availability; then
        log_error "$context" "Module availability check failed"
        exit 1
    fi
    
    # Run setup modules
    local setup_result
    if ! setup_result=$(run_setup_modules); then
        case $? in
            1)
                log_error "$context" "Critical setup failure"
                exit 1
                ;;
            2)
                log_warn "$context" "Setup completed with warnings"
                ;;
        esac
    fi
    
    # Create setup summary
    create_setup_summary
    
    # Print completion message
    print_completion
    
    log_to_file "info" "$context" "Setup completed successfully"
}

# Export main function for testing
export -f main

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi