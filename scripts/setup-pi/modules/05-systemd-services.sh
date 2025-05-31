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
    
    # Check if UFW is available
    if ! command -v ufw &> /dev/null; then
        log_warn "$context" "UFW not installed, skipping firewall configuration"
        return 0
    fi
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        log_info "$context" "Enabling UFW firewall"
        if ! ufw --force enable; then
            log_error "$context" "Failed to enable UFW"
            return 1
        fi
    fi
    
    # Allow SSH (important - don't lock ourselves out)
    ufw allow ssh &>/dev/null || log_warn "$context" "SSH rule already exists"
    
    # Allow HTTP and HTTPS for frontend
    ufw allow 80/tcp &>/dev/null || log_warn "$context" "HTTP rule already exists"
    ufw allow 443/tcp &>/dev/null || log_warn "$context" "HTTPS rule already exists"
    
    # Allow API port from local network only
    ufw allow from 192.168.0.0/16 to any port 3000 &>/dev/null || log_warn "$context" "API rule already exists"
    ufw allow from 10.0.0.0/8 to any port 3000 &>/dev/null || log_warn "$context" "API rule already exists"
    ufw allow from 172.16.0.0/12 to any port 3000 &>/dev/null || log_warn "$context" "API rule already exists"
    
    # Allow webhook port from anywhere (GitHub webhooks)
    ufw allow 9000/tcp &>/dev/null || log_warn "$context" "Webhook rule already exists"
    
    # Deny direct access to database and MQTT ports
    ufw deny 5432/tcp &>/dev/null || log_warn "$context" "Database deny rule already exists"
    ufw deny 1883/tcp &>/dev/null || log_warn "$context" "MQTT deny rule already exists"
    
    log_success "$context" "Firewall rules configured"
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
    echo "Frontend (HTTP): http://$(hostname -I | awk '{print $1}'):80"
    echo "API: http://$(hostname -I | awk '{print $1}'):3000"
    echo "Webhook: http://$(hostname -I | awk '{print $1}'):9000"
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
        "configure_firewall:Configure firewall"
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
            failed_steps+=("$step_desc")
            
            # If critical step fails, try to stop services
            if [[ "$func_name" == "start_services" || "$func_name" == "validate_services" ]]; then
                log_warn "$context" "Critical step failed, stopping services for cleanup"
                stop_services || log_error "$context" "Failed to stop services during cleanup"
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