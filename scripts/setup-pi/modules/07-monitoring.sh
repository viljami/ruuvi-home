#!/bin/bash
# Module: Monitoring Setup
# Description: Configures health monitoring, alerting, and log management
# Dependencies: 04-file-generation.sh (monitoring scripts generated)

set -e

# Module context for logging
readonly MODULE_CONTEXT="MONITORING"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# Monitoring configuration
readonly HEALTH_CHECK_SCRIPT="$PROJECT_DIR/scripts/health-check.py"
readonly MONITOR_SCRIPT="$PROJECT_DIR/scripts/monitor.sh"
readonly MAINTENANCE_SCRIPT="$PROJECT_DIR/scripts/maintenance.sh"
readonly MONITORING_CRON="/etc/cron.d/ruuvi-monitoring"
readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-300}"

# Verify monitoring scripts exist
verify_monitoring_scripts() {
    local context="$MODULE_CONTEXT"
    local required_scripts=(
        "$HEALTH_CHECK_SCRIPT"
        "$MONITOR_SCRIPT" 
        "$MAINTENANCE_SCRIPT"
    )
    
    log_info "$context" "Verifying monitoring scripts exist"
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "$context" "Required monitoring script not found: $script"
            log_error "$context" "Ensure file generation module has run successfully"
            return 1
        fi
        
        if [ ! -x "$script" ]; then
            log_error "$context" "Script not executable: $script"
            return 1
        fi
        
        # Basic syntax check
        local extension="${script##*.}"
        if [ "$extension" = "py" ]; then
            if ! python3 -m py_compile "$script"; then
                log_error "$context" "Python syntax error in: $script"
                return 1
            fi
        elif [ "$extension" = "sh" ]; then
            if ! bash -n "$script"; then
                log_error "$context" "Shell syntax error in: $script"
                return 1
            fi
        fi
    done
    
    log_success "$context" "All monitoring scripts verified"
    return 0
}

# Configure system monitoring
configure_system_monitoring() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Configuring system monitoring"
    
    # Create system monitoring cron jobs
    cat > "$MONITORING_CRON" << EOF
# Ruuvi Home system monitoring
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Health check every 5 minutes
*/5 * * * * $RUUVI_USER $HEALTH_CHECK_SCRIPT >> $LOG_DIR/health-check.log 2>&1

# System resource monitoring every 10 minutes
*/10 * * * * $RUUVI_USER $MONITOR_SCRIPT >> $LOG_DIR/monitoring.log 2>&1

# Daily maintenance at 3 AM
0 3 * * * root $MAINTENANCE_SCRIPT cleanup >> $LOG_DIR/maintenance.log 2>&1

# Weekly system update check on Sundays at 4 AM
0 4 * * 0 root $MAINTENANCE_SCRIPT update >> $LOG_DIR/maintenance.log 2>&1
EOF
    
    # Set proper permissions
    chmod 644 "$MONITORING_CRON"
    chown root:root "$MONITORING_CRON"
    
    # Restart cron service
    if ! systemctl restart cron; then
        log_error "$context" "Failed to restart cron service"
        return 1
    fi
    
    log_success "$context" "System monitoring configured"
    return 0
}

# Configure log rotation for monitoring logs
configure_monitoring_log_rotation() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Configuring monitoring log rotation"
    
    # Create comprehensive logrotate configuration
    cat > /etc/logrotate.d/ruuvi-monitoring << EOF
$LOG_DIR/health-check.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
    su $RUUVI_USER $RUUVI_USER
    create 644 $RUUVI_USER $RUUVI_USER
}

$LOG_DIR/monitoring.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su $RUUVI_USER $RUUVI_USER
    create 644 $RUUVI_USER $RUUVI_USER
}

$LOG_DIR/maintenance.log {
    weekly
    missingok
    rotate 12
    compress
    delaycompress
    notifempty
    copytruncate
    su root root
    create 644 root root
}

$LOG_DIR/deployment.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su $RUUVI_USER $RUUVI_USER
    create 644 $RUUVI_USER $RUUVI_USER
}

$LOG_DIR/webhook.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
    su $RUUVI_USER $RUUVI_USER
    create 644 $RUUVI_USER $RUUVI_USER
}
EOF
    
    # Test logrotate configuration
    if ! logrotate -d /etc/logrotate.d/ruuvi-monitoring &>/dev/null; then
        log_error "$context" "Invalid logrotate configuration"
        return 1
    fi
    
    log_success "$context" "Monitoring log rotation configured"
    return 0
}

# Set up alerting system
setup_alerting_system() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Setting up alerting system"
    
    # Create alert configuration file
    local alert_config="$PROJECT_DIR/config/alerts.conf"
    mkdir -p "$(dirname "$alert_config")"
    
    cat > "$alert_config" << EOF
# Ruuvi Home Alert Configuration
# Thresholds for system monitoring alerts

# Resource thresholds (percentage)
CPU_THRESHOLD=${CPU_THRESHOLD:-80}
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-85}
DISK_THRESHOLD=${DISK_THRESHOLD:-90}

# Service health check timeouts (seconds)
HEALTH_CHECK_TIMEOUT=30
SERVICE_START_TIMEOUT=120

# Alert cooldown periods (seconds)
ALERT_COOLDOWN=3600  # 1 hour between duplicate alerts

# Log file paths
ALERT_LOG="$LOG_DIR/alerts.log"
HEALTH_LOG="$LOG_DIR/health-check.log"
MONITOR_LOG="$LOG_DIR/monitoring.log"

# Email settings (configure if email alerts desired)
# ALERT_EMAIL=""
# SMTP_SERVER=""
# SMTP_PORT=""
EOF
    
    chown "$RUUVI_USER:$RUUVI_USER" "$alert_config"
    chmod 644 "$alert_config"
    
    # Create alert handler script
    local alert_handler="$PROJECT_DIR/scripts/alert-handler.sh"
    cat > "$alert_handler" << EOF
#!/bin/bash
# Alert handler for Ruuvi Home monitoring
# Processes and manages system alerts

ALERT_CONFIG="$alert_config"
source "\$ALERT_CONFIG"

log_alert() {
    local severity="\$1"
    local message="\$2"
    local timestamp=\$(date '+%Y-%m-%d %H:%M:%S')
    echo "[\$timestamp] [\$severity] \$message" | tee -a "\$ALERT_LOG"
}

send_alert() {
    local severity="\$1"
    local message="\$2"
    
    # Log the alert
    log_alert "\$severity" "\$message"
    
    # Add additional alerting mechanisms here (email, webhook, etc.)
    # Example: curl -X POST webhook_url -d "{\\"alert\\": \\"\$message\\"}"
}

# Export functions for use by monitoring scripts
export -f log_alert send_alert
EOF
    
    chmod +x "$alert_handler"
    chown "$RUUVI_USER:$RUUVI_USER" "$alert_handler"
    
    log_success "$context" "Alerting system configured"
    return 0
}

# Install monitoring utilities
install_monitoring_utilities() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Installing monitoring utilities"
    
    # Install additional monitoring tools
    local monitoring_packages=("htop" "iotop" "nethogs" "ncdu" "tree")
    local missing_packages=()
    
    for package in "${monitoring_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_info "$context" "Installing monitoring packages: ${missing_packages[*]}"
        
        export DEBIAN_FRONTEND=noninteractive
        if ! apt-get update -qq && apt-get install -y -qq "${missing_packages[@]}"; then
            log_warn "$context" "Some monitoring packages failed to install"
        else
            log_success "$context" "Monitoring packages installed"
        fi
    else
        log_success "$context" "All monitoring packages already installed"
    fi
    
    return 0
}

# Test monitoring functionality
test_monitoring_functionality() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Testing monitoring functionality"
    
    # Test health check script
    if [ -f "$HEALTH_CHECK_SCRIPT" ]; then
        log_debug "$context" "Testing health check script"
        if sudo -u "$RUUVI_USER" timeout 30 python3 "$HEALTH_CHECK_SCRIPT" &>/dev/null; then
            log_success "$context" "Health check script test passed"
        else
            log_warn "$context" "Health check script test failed (services may not be running)"
        fi
    fi
    
    # Test system monitor script
    if [ -f "$MONITOR_SCRIPT" ]; then
        log_debug "$context" "Testing system monitor script"
        if sudo -u "$RUUVI_USER" timeout 30 bash "$MONITOR_SCRIPT" &>/dev/null; then
            log_success "$context" "System monitor script test passed"
        else
            log_warn "$context" "System monitor script test failed"
        fi
    fi
    
    # Test log file creation
    local test_log="$LOG_DIR/monitoring-test.log"
    if sudo -u "$RUUVI_USER" touch "$test_log"; then
        rm -f "$test_log"
        log_success "$context" "Log file creation test passed"
    else
        log_error "$context" "Cannot create monitoring log files"
        return 1
    fi
    
    return 0
}

# Validate monitoring system
validate_monitoring_system() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Validating monitoring system"
    
    # Check cron jobs are configured
    if [ ! -f "$MONITORING_CRON" ]; then
        log_error "$context" "Monitoring cron jobs not configured"
        return 1
    fi
    
    # Verify cron service is running
    if ! systemctl is-active --quiet cron; then
        log_error "$context" "Cron service not running"
        return 1
    fi
    
    # Check log directory permissions
    if [ ! -w "$LOG_DIR" ]; then
        log_error "$context" "Log directory not writable: $LOG_DIR"
        return 1
    fi
    
    # Verify logrotate configuration
    if ! logrotate -d /etc/logrotate.d/ruuvi-monitoring &>/dev/null; then
        log_error "$context" "Logrotate configuration invalid"
        return 1
    fi
    
    # Check disk space for logs (at least 500MB)
    local available_space=$(df "$LOG_DIR" | awk 'NR==2 {print int($4/1024)}')
    if [ "$available_space" -lt 500 ]; then
        log_warn "$context" "Low disk space for logs: ${available_space}MB available"
    fi
    
    log_success "$context" "Monitoring system validation passed"
    return 0
}

# Show monitoring system status
show_monitoring_status() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Monitoring system status"
    
    echo ""
    echo "=== Monitoring System Configuration ==="
    echo "Health check interval: ${HEALTH_CHECK_INTERVAL}s"
    echo "Log directory: $LOG_DIR"
    echo "Alert configuration: $PROJECT_DIR/config/alerts.conf"
    
    # Show monitoring schedule
    echo ""
    echo "=== Monitoring Schedule ==="
    if [ -f "$MONITORING_CRON" ]; then
        grep -v '^#' "$MONITORING_CRON" | grep -v '^$' | while read -r line; do
            echo "  $line"
        done
    fi
    
    # Show log file status
    echo ""
    echo "=== Log Files ==="
    if [ -d "$LOG_DIR" ]; then
        ls -la "$LOG_DIR"/*.log 2>/dev/null | tail -5 || echo "No log files found"
        
        local total_log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
        echo "Total log size: $total_log_size"
    fi
    
    # Show available monitoring tools
    echo ""
    echo "=== Available Monitoring Tools ==="
    local tools=("htop" "iotop" "nethogs" "ncdu" "docker" "docker-compose")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool (not installed)"
        fi
    done
    echo ""
}

# Main monitoring setup function
setup_monitoring() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "verify_monitoring_scripts:Verify monitoring scripts"
        "install_monitoring_utilities:Install monitoring utilities"
        "configure_system_monitoring:Configure system monitoring"
        "configure_monitoring_log_rotation:Configure log rotation"
        "setup_alerting_system:Setup alerting system"
        "test_monitoring_functionality:Test monitoring functionality"
        "validate_monitoring_system:Validate monitoring system"
        "show_monitoring_status:Show monitoring status"
    )
    
    log_section "Monitoring Setup"
    log_info "$context" "Setting up monitoring system for user: $RUUVI_USER"
    
    local step_num=1
    local total_steps=${#setup_steps[@]}
    local failed_steps=()
    
    for step in "${setup_steps[@]}"; do
        local func_name="${step%:*}"
        local step_desc="${step#*:}"
        
        log_step "$step_num" "$total_steps" "$step_desc"
        
        if ! $func_name; then
            failed_steps+=("$step_desc")
        fi
        
        ((step_num++))
    done
    
    if [ ${#failed_steps[@]} -gt 0 ]; then
        log_error "$context" "Monitoring setup failed at: ${failed_steps[*]}"
        return 1
    fi
    
    log_success "$context" "Monitoring setup completed successfully"
    log_info "$context" "System monitoring active with health checks every ${HEALTH_CHECK_INTERVAL}s"
    return 0
}

# Export main function
export -f setup_monitoring

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_monitoring
fi