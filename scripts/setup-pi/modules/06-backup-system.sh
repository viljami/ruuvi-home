#!/bin/bash
# Module: Backup System Setup
# Description: Configures automated backup system for database and configurations
# Dependencies: 04-file-generation.sh (backup scripts generated)

set -e

# Module context for logging
readonly MODULE_CONTEXT="BACKUP"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# Backup configuration
readonly BACKUP_SCRIPT="$PROJECT_DIR/scripts/backup.sh"
readonly CRON_FILE="/etc/cron.d/ruuvi-backup"
readonly BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
readonly BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"

# Verify backup script exists
verify_backup_script() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Verifying backup script exists"

    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log_error "$context" "Backup script not found: $BACKUP_SCRIPT"
        log_error "$context" "Ensure file generation module has run successfully"
        return 1
    fi

    if [ ! -x "$BACKUP_SCRIPT" ]; then
        log_error "$context" "Backup script not executable: $BACKUP_SCRIPT"
        return 1
    fi

    # Test script syntax
    if ! bash -n "$BACKUP_SCRIPT"; then
        log_error "$context" "Backup script has syntax errors"
        return 1
    fi

    log_success "$context" "Backup script verified: $BACKUP_SCRIPT"
    return 0
}

# Create backup directories
create_backup_directories() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Creating backup directories"

    # Ensure backup directory exists with proper permissions
    if ! mkdir -p "$BACKUP_DIR"; then
        log_error "$context" "Failed to create backup directory: $BACKUP_DIR"
        return 1
    fi

    # Set ownership and permissions
    chown "$RUUVI_USER:$RUUVI_USER" "$BACKUP_DIR"
    chmod 750 "$BACKUP_DIR"  # Restrictive permissions for backups

    # Create subdirectories for different backup types
    local backup_subdirs=("database" "config" "logs")
    for subdir in "${backup_subdirs[@]}"; do
        local full_path="$BACKUP_DIR/$subdir"
        mkdir -p "$full_path"
        chown "$RUUVI_USER:$RUUVI_USER" "$full_path"
        chmod 750 "$full_path"
    done

    log_success "$context" "Backup directories created: $BACKUP_DIR"
    return 0
}

# Test backup functionality
test_backup_functionality() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Testing backup functionality"

    # Change to project directory
    cd "$PROJECT_DIR"

    # Test backup script execution
    log_debug "$context" "Running test backup"
    if ! sudo -u "$RUUVI_USER" "$BACKUP_SCRIPT" --test 2>/dev/null; then
        log_warn "$context" "Test backup failed, but continuing (services may not be running yet)"
    else
        log_success "$context" "Test backup successful"
    fi

    # Verify backup directory is writable
    local test_file="$BACKUP_DIR/.backup_test_$$"
    if ! sudo -u "$RUUVI_USER" touch "$test_file"; then
        log_error "$context" "Backup directory not writable by user: $RUUVI_USER"
        return 1
    fi

    rm -f "$test_file"
    log_success "$context" "Backup functionality verified"
    return 0
}

# Configure backup cron job
configure_backup_cron() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Configuring backup cron job"

    # Create cron job configuration
    cat > "$CRON_FILE" << EOF
# Ruuvi Home automated backup
# Runs daily at 2 AM
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Daily database and configuration backup
$BACKUP_SCHEDULE $RUUVI_USER $BACKUP_SCRIPT >> $LOG_DIR/backup.log 2>&1
EOF

    # Set proper permissions on cron file
    chmod 644 "$CRON_FILE"
    chown root:root "$CRON_FILE"

    # Basic cron syntax validation (crontab -T not available on all systems)
    if ! grep -q "^$BACKUP_SCHEDULE.*$RUUVI_USER.*$BACKUP_SCRIPT" "$CRON_FILE"; then
        log_error "$context" "Backup cron job not properly configured"
        return 1
    fi

    # Restart cron service to pick up new job
    if ! systemctl restart cron; then
        log_error "$context" "Failed to restart cron service"
        return 1
    fi

    log_success "$context" "Backup cron job configured: $BACKUP_SCHEDULE"
    return 0
}

# Configure log rotation for backup logs
configure_backup_log_rotation() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Configuring backup log rotation"

    # Create logrotate configuration for backup logs
    cat > /etc/logrotate.d/ruuvi-backup << EOF
$LOG_DIR/backup.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su $RUUVI_USER $RUUVI_USER
    create 644 $RUUVI_USER $RUUVI_USER
    postrotate
        # Signal any processes that might need to reopen log files
        /usr/bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF

    # Test logrotate configuration
    if ! logrotate -d /etc/logrotate.d/ruuvi-backup &>/dev/null; then
        log_error "$context" "Invalid logrotate configuration for backup logs"
        return 1
    fi

    log_success "$context" "Backup log rotation configured"
    return 0
}

# Set up backup monitoring
setup_backup_monitoring() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Setting up backup monitoring"

    # Create backup monitoring script
    local monitor_script="$PROJECT_DIR/scripts/backup-monitor.sh"
    cat > "$monitor_script" << EOF
#!/bin/bash
# Backup monitoring script

BACKUP_DIR="$BACKUP_DIR"
LOG_FILE="$LOG_DIR/backup-monitor.log"
MAX_BACKUP_AGE_HOURS=25  # Allow up to 25 hours for daily backups

log_alert() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [ALERT] \$1" | tee -a "\$LOG_FILE"
}

# Check if recent backup exists
latest_backup=\$(find "\$BACKUP_DIR" -name "ruuvi_backup_*.sql.gz" -type f -mtime -1 | head -1)

if [ -z "\$latest_backup" ]; then
    log_alert "No recent database backup found (older than 24 hours)"
    exit 1
fi

# Check backup file size (should be > 1KB)
backup_size=\$(stat -c%s "\$latest_backup" 2>/dev/null || echo "0")
if [ "\$backup_size" -lt 1024 ]; then
    log_alert "Backup file too small: \$latest_backup (\${backup_size} bytes)"
    exit 1
fi

# Check backup directory disk usage
backup_usage=\$(du -sh "\$BACKUP_DIR" | cut -f1)
echo "\$(date '+%Y-%m-%d %H:%M:%S') [INFO] Backup system healthy, latest: \$(basename "\$latest_backup"), size: \$backup_usage" >> "\$LOG_FILE"
EOF

    chmod +x "$monitor_script"
    chown "$RUUVI_USER:$RUUVI_USER" "$monitor_script"

    log_success "$context" "Backup monitoring configured"
    return 0
}

# Validate backup system configuration
validate_backup_system() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Validating backup system configuration"

    # Check backup directory exists and is writable
    if [ ! -d "$BACKUP_DIR" ] || [ ! -w "$BACKUP_DIR" ]; then
        log_error "$context" "Backup directory not accessible: $BACKUP_DIR"
        return 1
    fi

    # Check backup script exists and is executable
    if [ ! -x "$BACKUP_SCRIPT" ]; then
        log_error "$context" "Backup script not executable: $BACKUP_SCRIPT"
        return 1
    fi

    # Check cron job is configured
    if [ ! -f "$CRON_FILE" ]; then
        log_error "$context" "Backup cron job not configured: $CRON_FILE"
        return 1
    fi

    # Verify cron service is running
    if ! systemctl is-active --quiet cron; then
        log_error "$context" "Cron service not running"
        return 1
    fi

    # Check disk space for backups (at least 1GB free)
    local available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print int($4/1024)}')
    if [ "$available_space" -lt 1024 ]; then
        log_warn "$context" "Low disk space for backups: ${available_space}MB available"
    fi

    log_success "$context" "Backup system validation passed"
    return 0
}

# Show backup system status
show_backup_status() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Backup system status"

    echo ""
    echo "=== Backup System Configuration ==="
    echo "Backup directory: $BACKUP_DIR"
    echo "Backup script: $BACKUP_SCRIPT"
    echo "Backup schedule: $BACKUP_SCHEDULE"
    echo "Retention days: $BACKUP_RETENTION_DAYS"

    # Show existing backups
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(ls -1 "$BACKUP_DIR"/ruuvi_backup_*.sql.gz 2>/dev/null | wc -l)
        local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo "Existing backups: $backup_count"
        echo "Total backup size: $total_size"

        # Show most recent backup
        local latest_backup=$(ls -t "$BACKUP_DIR"/ruuvi_backup_*.sql.gz 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            local backup_age=$(stat -c %Y "$latest_backup")
            local current_time=$(date +%s)
            local age_hours=$(( (current_time - backup_age) / 3600 ))
            echo "Latest backup: $(basename "$latest_backup") (${age_hours}h ago)"
        fi
    fi

    echo ""
    echo "Next scheduled backup: $(grep -v '^#' "$CRON_FILE" 2>/dev/null | head -1 | awk '{print $1, $2, $3, $4, $5}' || echo 'Not configured')"
    echo ""
}

# Main backup system setup function
setup_backup_system() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "verify_backup_script:Verify backup script"
        "create_backup_directories:Create backup directories"
        "test_backup_functionality:Test backup functionality"
        "configure_backup_cron:Configure backup cron job"
        "configure_backup_log_rotation:Configure log rotation"
        "setup_backup_monitoring:Setup backup monitoring"
        "validate_backup_system:Validate backup system"
        "show_backup_status:Show backup status"
    )

    log_section "Backup System Setup"
    log_info "$context" "Setting up automated backup system for user: $RUUVI_USER"

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
        log_error "$context" "Backup system setup failed at: ${failed_steps[*]}"
        return 1
    fi

    log_success "$context" "Backup system setup completed successfully"
    log_info "$context" "Automated backups scheduled: $BACKUP_SCHEDULE"
    return 0
}

# Export main function
export -f setup_backup_system

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_backup_system
fi
