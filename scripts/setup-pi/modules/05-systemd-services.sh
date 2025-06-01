#!/bin/bash
# Module: SystemD Services Setup
# Description: Installs, enables and starts systemd services for Ruuvi Home
# Dependencies: 04-file-generation.sh (service files generated)

set -e

# Module context for logging
readonly MODULE_CONTEXT="SYSTEMD"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# Service configuration
readonly SERVICE_FILES=(
    "ruuvi-home.service"
    "ruuvi-webhook.service"
)

readonly SERVICE_DIR="/etc/systemd/system"

# Install systemd service files
install_service_files() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Installing systemd service files"
    
    for service in "${SERVICE_FILES[@]}"; do
        local service_file="$SERVICE_DIR/$service"
        
        if [ ! -f "$service_file" ]; then
            log_error "$context" "Service file not found: $service_file"
            log_error "$context" "Ensure file generation module has run successfully"
            return 1
        fi
        
        # Validate service file syntax
        if ! systemd-analyze verify "$service_file" 2>/dev/null; then
            log_error "$context" "Invalid service file: $service"
            return 1
        fi
        
        log_success "$context" "Service file validated: $service"
    done
    
    log_success "$context" "All service files installed and validated"
    return 0
}

# Reload systemd daemon
reload_systemd_daemon() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Reloading systemd daemon"
    
    if ! systemctl daemon-reload; then
        log_error "$context" "Failed to reload systemd daemon"
        return 1
    fi
    
    log_success "$context" "Systemd daemon reloaded"
    return 0
}

# Enable systemd services
enable_services() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Enabling systemd services"
    
    for service in "${SERVICE_FILES[@]}"; do
        log_debug "$context" "Enabling service: $service"
        
        if ! systemctl enable "$service"; then
            log_error "$context" "Failed to enable service: $service"
            return 1
        fi
        
        log_success "$context" "Service enabled: $service"
    done
    
    log_success "$context" "All services enabled"
    return 0
}

# Start systemd services
start_services() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Starting systemd services"
    log_info "$context" "Deployment mode: ${DEPLOYMENT_MODE:-local}"
    
    # For registry mode, ensure images are available
    if [ "${DEPLOYMENT_MODE}" = "registry" ]; then
        log_info "$context" "Registry mode: Verifying image availability"
        
        # Check if required images exist or can be pulled
        local compose_file="${DOCKER_COMPOSE_FILE:-docker-compose.yaml}"
        if [ -f "$PROJECT_DIR/$compose_file" ]; then
            log_info "$context" "Pre-pulling images for registry deployment"
            cd "$PROJECT_DIR"
            
            # Try to pull images with detailed error handling
            local pull_output
            if pull_output=$(sudo -u "$RUUVI_USER" docker compose -f "$compose_file" pull 2>&1); then
                log_success "$context" "Successfully pulled all required images"
            else
                log_error "$context" "Failed to pull images from registry"
                log_error "$context" "Pull output: $pull_output"
                
                # Check if any images are available locally
                local available_images
                if available_images=$(sudo -u "$RUUVI_USER" docker compose -f "$compose_file" images -q 2>/dev/null); then
                    if [ -n "$available_images" ]; then
                        log_warn "$context" "Some images available locally, attempting to start with existing images"
                    else
                        log_error "$context" "No images available locally or from registry"
                        log_error "$context" "Please check:"
                        log_error "$context" "  1. Network connectivity to ${GITHUB_REGISTRY:-ghcr.io}"
                        log_error "$context" "  2. GitHub repository: ${GITHUB_REPO:-not-set}"
                        log_error "$context" "  3. Image tag: ${IMAGE_TAG:-latest}"
                        return 1
                    fi
                else
                    log_error "$context" "Cannot determine image availability"
                    return 1
                fi
            fi
        else
            log_error "$context" "Compose file not found: $PROJECT_DIR/$compose_file"
            return 1
        fi
    fi
    
    # Start services in dependency order
    local ordered_services=("ruuvi-home.service" "ruuvi-webhook.service")
    
    for service in "${ordered_services[@]}"; do
        log_debug "$context" "Starting service: $service"
        
        if ! systemctl start "$service"; then
            log_error "$context" "Failed to start service: $service"
            
            # Show service status for debugging
            log_error "$context" "Service status:"
            systemctl status "$service" --no-pager || true
            
            return 1
        fi
        
        # Wait a moment for service to initialize
        sleep 2
        
        log_success "$context" "Service started: $service"
    done
    
    log_success "$context" "All services started"
    return 0
}

# Validate service health
validate_services() {
    local context="$MODULE_CONTEXT"
    local failed_services=()
    
    log_info "$context" "Validating service health"
    
    for service in "${SERVICE_FILES[@]}"; do
        log_debug "$context" "Checking service: $service"
        
        # Check if service is active
        if ! systemctl is-active --quiet "$service"; then
            log_error "$context" "Service not active: $service"
            failed_services+=("$service")
            continue
        fi
        
        # Check if service is enabled
        if ! systemctl is-enabled --quiet "$service"; then
            log_warn "$context" "Service not enabled: $service"
        fi
        
        # Get service status
        local service_status=$(systemctl show "$service" --property=ActiveState --value)
        local service_substate=$(systemctl show "$service" --property=SubState --value)
        
        if [ "$service_status" = "active" ] && [ "$service_substate" = "running" ]; then
            log_success "$context" "Service healthy: $service ($service_status/$service_substate)"
        else
            log_error "$context" "Service unhealthy: $service ($service_status/$service_substate)"
            failed_services+=("$service")
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        log_error "$context" "Service validation failed for: ${failed_services[*]}"
        return 1
    fi
    
    log_success "$context" "All services are healthy"
    return 0
}

# Configure firewall rules
configure_firewall() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Configuring firewall rules"
    
    # Check if UFW is available, try to install if not
    if ! command -v ufw &> /dev/null; then
        log_info "$context" "UFW not installed, attempting to install"
        export DEBIAN_FRONTEND=noninteractive
        if apt-get update -qq && apt-get install -y -qq ufw; then
            log_success "$context" "UFW installed successfully"
        else
            log_warn "$context" "Could not install UFW, skipping firewall configuration"
            return 0
        fi
    fi
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        log_info "$context" "Enabling UFW firewall"
        if ! ufw --force enable; then
            log_warn "$context" "Failed to enable UFW, continuing without firewall"
            return 0
        fi
    fi
    
    # Configure firewall rules with error handling
    local firewall_rules=(
        "ufw allow ssh:Allow SSH access"
        "ufw allow 80/tcp:Allow HTTP for frontend"
        "ufw allow 443/tcp:Allow HTTPS for frontend"
        "ufw allow from 192.168.0.0/16 to any port 3000:Allow API from 192.168.x.x"
        "ufw allow from 10.0.0.0/8 to any port 3000:Allow API from 10.x.x.x"
        "ufw allow from 172.16.0.0/12 to any port 3000:Allow API from 172.16-31.x.x"
        "ufw allow ${WEBHOOK_PORT:-9000}/tcp:Allow webhook port"
        "ufw deny 5432/tcp:Deny direct database access"
        "ufw deny 1883/tcp:Deny direct MQTT access"
    )
    
    for rule_entry in "${firewall_rules[@]}"; do
        local rule_cmd="${rule_entry%:*}"
        local rule_desc="${rule_entry#*:}"
        
        if $rule_cmd &>/dev/null; then
            log_debug "$context" "Firewall rule applied: $rule_desc"
        else
            log_warn "$context" "Firewall rule failed or already exists: $rule_desc"
        fi
    done
    
    log_success "$context" "Firewall configuration completed"
    return 0
}

# Show service status summary
show_service_status() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Service status summary"
    
    echo ""
    echo "=== Ruuvi Home Services ==="
    for service in "${SERVICE_FILES[@]}"; do
        echo "Service: $service"
        systemctl status "$service" --no-pager -l | head -10
        echo ""
    done
    
    echo "=== Service Ports ==="
    echo "Frontend (HTTP): http://$(hostname -I | awk '{print $1}'):${FRONTEND_PORT:-80}"
    echo "API: http://$(hostname -I | awk '{print $1}'):${API_PORT:-8080}"
    
    # Show webhook URL based on HTTPS configuration
    local webhook_protocol="http"
    if [ "${WEBHOOK_ENABLE_HTTPS:-true}" = "true" ]; then
        webhook_protocol="https"
    fi
    echo "Webhook: ${webhook_protocol}://$(hostname -I | awk '{print $1}'):${WEBHOOK_PORT:-9000}"
    echo ""
}

# Stop services (for cleanup or rollback)
stop_services() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Stopping systemd services"
    
    # Stop services in reverse order
    local reverse_services=("ruuvi-webhook.service" "ruuvi-home.service")
    
    for service in "${reverse_services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_debug "$context" "Stopping service: $service"
            
            if ! systemctl stop "$service"; then
                log_error "$context" "Failed to stop service: $service"
                return 1
            fi
            
            log_success "$context" "Service stopped: $service"
        else
            log_debug "$context" "Service already stopped: $service"
        fi
    done
    
    log_success "$context" "All services stopped"
    return 0
}

# Main systemd setup function
setup_systemd_services() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "install_service_files:Install service files"
        "reload_systemd_daemon:Reload systemd daemon"
        "enable_services:Enable services"
        "start_services:Start services"
        "validate_services:Validate service health"
        "configure_firewall:Configure firewall (optional)"
        "show_service_status:Show service status"
    )
    
    log_section "SystemD Services Setup"
    log_info "$context" "Setting up systemd services for user: $RUUVI_USER"
    
    local step_num=1
    local total_steps=${#setup_steps[@]}
    local failed_steps=()
    
    for step in "${setup_steps[@]}"; do
        local func_name="${step%:*}"
        local step_desc="${step#*:}"
        
        log_step "$step_num" "$total_steps" "$step_desc"
        
        if ! $func_name; then
            # Make firewall configuration non-critical
            if [[ "$func_name" == "configure_firewall" ]]; then
                log_warn "$context" "Non-critical step failed but continuing: $step_desc"
            else
                failed_steps+=("$step_desc")
                
                # If critical step fails, try to stop services
                if [[ "$func_name" == "start_services" || "$func_name" == "validate_services" ]]; then
                    log_warn "$context" "Critical step failed, stopping services for cleanup"
                    stop_services || log_error "$context" "Failed to stop services during cleanup"
                fi
            fi
        fi
        
        ((step_num++))
    done
    
    if [ ${#failed_steps[@]} -gt 0 ]; then
        log_error "$context" "SystemD services setup failed at: ${failed_steps[*]}"
        return 1
    fi
    
    log_success "$context" "SystemD services setup completed successfully"
    log_info "$context" "Services are running and healthy"
    return 0
}

# Export main function
export -f setup_systemd_services

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_systemd_services
fi