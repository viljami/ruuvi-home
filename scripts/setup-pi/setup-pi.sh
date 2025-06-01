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
readonly MODULE_DIR="$SCRIPT_DIR/modules"
readonly TEMPLATE_DIR="$SCRIPT_DIR/templates"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/config.sh"

# Generate secure passwords for services
generate_secure_passwords() {
    local context="$MAIN_CONTEXT"

    log_info "$context" "Generating secure passwords for services"

    # Generate secure random passwords (32 bytes = 256 bits of entropy)
    export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 32)}"
    export AUTH_DB_PASSWORD="${AUTH_DB_PASSWORD:-$(openssl rand -base64 32)}"
    export MQTT_PASSWORD="${MQTT_PASSWORD:-$(openssl rand -base64 32)}"
    export WEBHOOK_SECRET="${WEBHOOK_SECRET:-$(openssl rand -base64 32)}"

    # Additional derived secrets (JWT requires minimum 32 characters)
    export JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 48)}"
    export SESSION_SECRET="${SESSION_SECRET:-$(openssl rand -base64 32)}"

    log_success "$context" "Secure passwords generated"
    log_info "$context" "Passwords will be saved to .env file during setup"
}

# Initialize configuration using shared library with enhanced IP detection
initialize_shared_configuration() {
    local context="$MAIN_CONTEXT"

    log_info "$context" "Initializing configuration with enhanced network detection"

    # Use enhanced network detection for robust external IP discovery
    log_info "$context" "Detecting network configuration and external IP..."
    detect_network_configuration

    # Use shared configuration library for URL construction
    initialize_configuration

    log_success "$context" "Configuration initialized with network detection"
    log_info "$context" "Network scenario: $NETWORK_SCENARIO"
    log_info "$context" "Local IP: $DETECTED_LOCAL_IP"
    log_info "$context" "External IP: $DETECTED_EXTERNAL_IP"
    log_info "$context" "Webhook IP: $DETECTED_PUBLIC_IP"
    log_info "$context" "Public API URL: $PUBLIC_API_URL"
    log_info "$context" "Public Frontend URL: $PUBLIC_FRONTEND_URL"

    # Show network guidance
    case "$NETWORK_SCENARIO" in
        "nat")
            log_warn "$context" "NAT detected - port forwarding will be required for webhooks"
            log_info "$context" "External webhook URL: https://$DETECTED_EXTERNAL_IP:9000"
            ;;
        "direct")
            log_success "$context" "Direct connection - webhooks should work immediately"
            ;;
        *)
            log_warn "$context" "Network scenario unclear - manual configuration may be needed"
            ;;
    esac
}

# Configure HTTPS settings
configure_https_settings() {
    local context="$MAIN_CONTEXT"

    if [ "${ENABLE_HTTPS}" != "true" ]; then
        export WEBHOOK_ENABLE_HTTPS="false"
        log_info "$context" "HTTPS disabled by configuration"
        return 0
    fi

    log_section "HTTPS Configuration"

    echo -e "${COLOR_YELLOW}HTTPS Configuration for Local Pi:${COLOR_NC}"
    echo "1) IP-based certificate (default) - Works with Pi's IP address"
    echo "2) Let's Encrypt certificate - Requires public domain name"
    echo ""
    echo "For local Pi deployment, option 1 is recommended."
    echo "Your Pi's IP: $(hostname -I | awk '{print $1}')"
    echo ""

    # Check for non-interactive mode
    if [ -n "$ENABLE_LETS_ENCRYPT" ] && [ "$ENABLE_LETS_ENCRYPT" = "true" ]; then
        log_info "$context" "Non-interactive mode: Using Let's Encrypt"

        if [ -z "$WEBHOOK_DOMAIN" ]; then
            log_error "$context" "Let's Encrypt requires WEBHOOK_DOMAIN environment variable"
            log_error "$context" "Example: export WEBHOOK_DOMAIN=webhook.yourdomain.com"
            return 1
        fi

        # Check if domain is actually an IP address
        if [[ "$WEBHOOK_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "$context" "Let's Encrypt cannot issue certificates for IP addresses"
            log_error "$context" "Use a real domain name or choose option 1 for IP-based certificates"
            return 1
        fi

        if [ -z "$WEBHOOK_EMAIL" ]; then
            log_error "$context" "Let's Encrypt requires WEBHOOK_EMAIL environment variable"
            log_error "$context" "Example: export WEBHOOK_EMAIL=admin@yourdomain.com"
            return 1
        fi
    else
        if [ -z "$ENABLE_LETS_ENCRYPT" ]; then
            while true; do
                read -p "Choose HTTPS method (1 or 2): " choice
                case $choice in
                    1)
                        export ENABLE_LETS_ENCRYPT="false"
                        export WEBHOOK_DOMAIN="$(hostname -I | awk '{print $1}')"
                        break
                        ;;
                    2)
                        export ENABLE_LETS_ENCRYPT="true"
                        echo ""
                        echo "Let's Encrypt requires a public domain name that points to your Pi."
                        echo "This will NOT work with just an IP address."
                        echo ""
                        read -p "Enter your public domain name (e.g., webhook.yourdomain.com): " domain_input
                        read -p "Enter your email address: " email_input
                        export WEBHOOK_DOMAIN="$domain_input"
                        export WEBHOOK_EMAIL="$email_input"
                        break
                        ;;
                    *)
                        echo "Invalid choice. Please enter 1 or 2."
                        ;;
                esac
            done
        fi
    fi

    # Configure based on HTTPS method
    if [ "$ENABLE_LETS_ENCRYPT" = "true" ]; then
        log_info "$context" "Selected: Let's Encrypt SSL certificate"
        log_info "$context" "Domain: $WEBHOOK_DOMAIN"
        log_info "$context" "Email: $WEBHOOK_EMAIL"
    else
        log_info "$context" "Selected: IP-based SSL certificate"
        log_info "$context" "Certificate will be valid for IP: $WEBHOOK_DOMAIN"
        log_info "$context" "GitHub webhook will need SSL verification disabled"
    fi

    export WEBHOOK_ENABLE_HTTPS="true"
    log_success "$context" "HTTPS configuration completed"
}

# Choose deployment mode
choose_deployment_mode() {
    local context="$MAIN_CONTEXT"

    log_section "Deployment Mode Selection"

    # Check for non-interactive mode via environment variables
    if [ -n "$DEPLOYMENT_MODE" ]; then
        log_info "$context" "Non-interactive mode: Using preset deployment mode"

        # Normalize deployment mode (support numeric and text values)
        case "$DEPLOYMENT_MODE" in
            1|"registry"|"github"|"REGISTRY"|"GITHUB")
                export DEPLOYMENT_MODE="registry"
                ;;
            2|"local"|"build"|"LOCAL"|"BUILD")
                export DEPLOYMENT_MODE="local"
                ;;
            *)
                log_error "$context" "Invalid DEPLOYMENT_MODE environment variable: $DEPLOYMENT_MODE"
                log_error "$context" "Valid values: 1, 2, registry, local, github, build"
                return 1
                ;;
        esac

        log_info "$context" "Environment variable DEPLOYMENT_MODE=$DEPLOYMENT_MODE"

        # For registry mode, check if GITHUB_REPO is also set
        if [ "$DEPLOYMENT_MODE" = "registry" ] && [ -z "$GITHUB_REPO" ]; then
            log_error "$context" "Registry mode requires GITHUB_REPO environment variable"
            log_error "$context" "Example: export GITHUB_REPO=username/ruuvi-home"
            return 1
        fi
    else
        echo -e "${COLOR_YELLOW}Choose deployment mode:${COLOR_NC}"
        echo "1) GitHub Registry (Recommended) - Pull pre-built images from GitHub Actions"
        echo "2) Local Build - Build all images locally from source"
        echo ""
        echo "For non-interactive setup, set environment variables:"
        echo "  export DEPLOYMENT_MODE=1  # or 'registry'"
        echo "  export GITHUB_REPO=username/ruuvi-home  # required for registry mode"
        echo ""

        while true; do
            read -p "Enter choice (1 or 2): " choice
            case $choice in
                1)
                    export DEPLOYMENT_MODE="registry"
                    break
                    ;;
                2)
                    export DEPLOYMENT_MODE="local"
                    break
                    ;;
                *)
                    echo "Invalid choice. Please enter 1 or 2."
                    ;;
            esac
        done
    fi

    # Configure based on deployment mode
    case "$DEPLOYMENT_MODE" in
        "registry")
            log_info "$context" "Selected: GitHub Registry mode"
            export DOCKER_COMPOSE_FILE="docker-compose.registry.yaml"

            # Prompt for GitHub repository if not set
            if [ -z "$GITHUB_REPO" ]; then
                echo ""
                read -p "Enter GitHub repository (e.g., username/ruuvi-home): " repo_input
                export GITHUB_REPO="$repo_input"
            fi

            log_info "$context" "Will pull images from: $GITHUB_REGISTRY/$GITHUB_REPO"
            log_info "$context" "Using compose file: $DOCKER_COMPOSE_FILE"
            ;;
        "local")
            log_info "$context" "Selected: Local build mode"
            export DOCKER_COMPOSE_FILE="docker-compose.yaml"
            log_info "$context" "Will build all images locally from source"
            log_info "$context" "Using compose file: $DOCKER_COMPOSE_FILE"
            ;;
        *)
            log_error "$context" "Invalid deployment mode: $DEPLOYMENT_MODE"
            return 1
            ;;
    esac

    log_success "$context" "Deployment mode configured: $DEPLOYMENT_MODE"
}

# Load configuration variables
load_config() {
    local context="$MAIN_CONTEXT"

    log_info "$context" "Detecting target user for setup"

    # Use robust user detection from shared config library
    if ! detect_target_user; then
        log_error "$context" "Failed to detect target user"
        return 1
    fi

    # Validate user environment
    if ! validate_user_environment; then
        log_error "$context" "User environment validation failed"
        return 1
    fi

    # Export key variables for modules (using detected user)
    export DATA_DIR="$PROJECT_DIR/data"
    export LOG_DIR="/var/log/ruuvi-home"
    export BACKUP_DIR="$PROJECT_DIR/backups"

    # Configuration defaults
    export WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"
    export FRONTEND_PORT="${FRONTEND_PORT:-80}"
    export API_PORT="${API_PORT:-3000}"
    export DB_PORT="${DB_PORT:-5432}"
    export DB_USER="${DB_USER:-ruuvi}"
    export DB_NAME="${DB_NAME:-ruuvi_home}"
    export MOSQUITTO_PORT="${MOSQUITTO_PORT:-1883}"
    export TZ="${TZ:-Europe/Helsinki}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"

    # Feature flags
    export ENABLE_FISH_SHELL="${ENABLE_FISH_SHELL:-true}"
    export ENABLE_BACKUP_CRON="${ENABLE_BACKUP_CRON:-true}"
    export ENABLE_MONITORING="${ENABLE_MONITORING:-true}"
    export ENABLE_FIREWALL="${ENABLE_FIREWALL:-true}"
    export ENABLE_HTTPS="${ENABLE_HTTPS:-true}"
    export ENABLE_LETS_ENCRYPT="${ENABLE_LETS_ENCRYPT:-false}"

    # Default to Pi's IP address for local certificates
    local pi_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "192.168.1.100")
    export DEFAULT_WEBHOOK_DOMAIN="$pi_ip"

    # Backup configuration
    export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
    export BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"

    # Docker configuration
    export DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-10m}"
    export DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-3}"

    # Deployment mode (will be set by choose_deployment_mode)
    export DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-}"
    export DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-}"
    export GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io}"
    export GITHUB_REPO="${GITHUB_REPO:-}"

    # HTTPS/SSL Configuration
    export WEBHOOK_ENABLE_HTTPS="${WEBHOOK_ENABLE_HTTPS:-true}"
    export WEBHOOK_DOMAIN="${WEBHOOK_DOMAIN:-$DEFAULT_WEBHOOK_DOMAIN}"
    export WEBHOOK_EMAIL="${WEBHOOK_EMAIL:-}"
    export SSL_CERT_PATH="$PROJECT_DIR/ssl"
    export LETS_ENCRYPT_STAGING="${LETS_ENCRYPT_STAGING:-true}"

    # Colors for output
    export COLOR_GREEN='\033[0;32m'
    export COLOR_YELLOW='\033[1;33m'
    export COLOR_RED='\033[0;31m'
    export COLOR_NC='\033[0m'
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
    "08-ssl-setup.sh:SSL Certificate Setup"
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

    log_info "$context" "Configuration: Built-in defaults with environment overrides"
    log_info "$context" "Target user: $RUUVI_USER"
    log_info "$context" "Project directory: $PROJECT_DIR"

    # Generate secure passwords if not already provided
    generate_secure_passwords

    # Initialize shared configuration with intelligent defaults
    initialize_shared_configuration
}

# Validate script environment
validate_script_environment() {
    local context="$MAIN_CONTEXT"
    local missing_deps=()

    log_info "$context" "Validating script environment"

    # Check required directories
    for dir in "$LIB_DIR" "$MODULE_DIR" "$TEMPLATE_DIR"; do
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
    export SCRIPT_DIR MODULE_DIR LIB_DIR TEMPLATE_DIR
    export RUUVI_USER PROJECT_DIR DATA_DIR LOG_DIR BACKUP_DIR
    export POSTGRES_PASSWORD MQTT_PASSWORD WEBHOOK_SECRET JWT_SECRET SESSION_SECRET
    export DEPLOYMENT_MODE DOCKER_COMPOSE_FILE GITHUB_REGISTRY GITHUB_REPO
    export WEBHOOK_ENABLE_HTTPS WEBHOOK_DOMAIN WEBHOOK_EMAIL ENABLE_LETS_ENCRYPT SSL_CERT_PATH LETS_ENCRYPT_STAGING

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
            if [[ "$module_file" == "00-validation.sh" || "$module_file" == "01-system-setup.sh" || "$module_file" == "02-docker-setup.sh" || "$module_file" == "03-directories.sh" || "$module_file" == "04-file-generation.sh" ]]; then
                log_error "$context" "Critical module failed, cannot continue: $module_file"
                return 1
            else
                log_warn "$context" "Non-critical module failed but continuing: $module_file"
            fi
        fi

        ((step_num++))
    done

    if [ ${#failed_modules[@]} -gt 0 ]; then
        log_error "$context" "Setup failed due to module failures: ${failed_modules[*]}"
        log_error "$context" "Manual intervention required before system is functional"
        return 1
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
- Deployment Mode: $DEPLOYMENT_MODE
- Docker Compose File: $DOCKER_COMPOSE_FILE
- HTTPS Enabled: ${WEBHOOK_ENABLE_HTTPS:-false}
- Let's Encrypt: ${ENABLE_LETS_ENCRYPT:-false}
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
    log_info "$context" "Services configured: ruuvi-home, ruuvi-webhook"
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

    # Choose deployment mode
    if ! choose_deployment_mode; then
        log_error "$context" "Deployment mode selection failed"
        exit 1
    fi

    # Configure HTTPS settings
    if ! configure_https_settings; then
        log_error "$context" "HTTPS configuration failed"
        exit 1
    fi

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
    if ! run_setup_modules; then
        log_error "$context" "Setup failed - system is not functional"
        log_error "$context" "Please fix the issues above and re-run the setup"
        exit 1
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
