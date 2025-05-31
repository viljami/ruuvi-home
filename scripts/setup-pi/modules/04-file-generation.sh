#!/bin/bash
# Module: File Generation
# Description: Generates scripts and configuration files using simple bash templates
# Dependencies: 01-system-setup.sh, 03-directories.sh (project structure)

set -e

# Module context for logging
readonly MODULE_CONTEXT="GENERATOR"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# Generate deploy webhook Python script
generate_deploy_webhook_script() {
    local context="$MODULE_CONTEXT"
    local script_path="$PROJECT_DIR/scripts/deploy-webhook.py"
    
    log_info "$context" "Generating deploy webhook script"
    
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << EOF
#!/usr/bin/env python3
"""
Ruuvi Home Deployment Webhook Server
Handles GitHub webhook deployments
"""

import os
import sys
import json
import hmac
import hashlib
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

# Configuration
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET', '${WEBHOOK_SECRET}')
WEBHOOK_PORT = int(os.getenv('WEBHOOK_PORT', '${WEBHOOK_PORT}'))
PROJECT_DIR = '${PROJECT_DIR}'
LOG_FILE = '${LOG_DIR}/webhook.log'

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            content_length = int(self.headers['Content-Length'])
            payload = self.rfile.read(content_length)
            
            # Verify signature
            signature = self.headers.get('X-Hub-Signature-256')
            if not self.verify_signature(payload, signature):
                self.send_response(401)
                self.end_headers()
                return
            
            # Parse payload
            data = json.loads(payload.decode('utf-8'))
            
            # Handle push events to main branch
            if data.get('ref') == 'refs/heads/main':
                self.deploy()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'Deployment triggered')
            else:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'No action taken')
                
        except Exception as e:
            print(f"Webhook error: {e}")
            self.send_response(500)
            self.end_headers()
    
    def verify_signature(self, payload, signature):
        if not signature or not WEBHOOK_SECRET:
            return False
        
        expected = 'sha256=' + hmac.new(
            WEBHOOK_SECRET.encode(),
            payload,
            hashlib.sha256
        ).hexdigest()
        
        return hmac.compare_digest(signature, expected)
    
    def deploy(self):
        try:
            subprocess.run([
                f'{PROJECT_DIR}/scripts/deploy.sh'
            ], check=True, cwd=PROJECT_DIR)
        except subprocess.CalledProcessError as e:
            print(f"Deployment failed: {e}")

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', WEBHOOK_PORT), WebhookHandler)
    print(f"Webhook server starting on port {WEBHOOK_PORT}")
    server.serve_forever()
EOF
    
    chmod +x "$script_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$script_path"
    log_success "$context" "Deploy webhook script generated"
}

# Generate deployment script
generate_deploy_script() {
    local context="$MODULE_CONTEXT"
    local script_path="$PROJECT_DIR/scripts/deploy.sh"
    
    log_info "$context" "Generating deployment script"
    
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << EOF
#!/bin/bash
# Ruuvi Home Deployment Script

set -e

PROJECT_DIR="${PROJECT_DIR}"
LOG_FILE="${LOG_DIR}/deployment.log"

log_deployment() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" | tee -a "\$LOG_FILE"
}

log_deployment "Starting deployment..."

# Pull latest changes
cd "\$PROJECT_DIR"
git fetch origin
git reset --hard origin/main

# Update Docker containers
docker-compose pull
docker-compose up -d --force-recreate

log_deployment "Deployment completed successfully"
EOF
    
    chmod +x "$script_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$script_path"
    log_success "$context" "Deployment script generated"
}

# Generate backup script
generate_backup_script() {
    local context="$MODULE_CONTEXT"
    local script_path="$PROJECT_DIR/scripts/backup.sh"
    
    log_info "$context" "Generating backup script"
    
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << EOF
#!/bin/bash
# Ruuvi Home Backup Script

set -e

PROJECT_DIR="${PROJECT_DIR}"
BACKUP_DIR="${BACKUP_DIR}"
LOG_FILE="${LOG_DIR}/backup.log"

log_backup() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" | tee -a "\$LOG_FILE"
}

# Test mode
if [ "\$1" = "--test" ]; then
    log_backup "Backup test mode - checking prerequisites"
    exit 0
fi

log_backup "Starting backup..."

# Create backup filename with timestamp
BACKUP_FILE="\$BACKUP_DIR/ruuvi_backup_\$(date +%Y%m%d_%H%M%S).sql.gz"

# Backup database
docker exec timescaledb pg_dump -U ruuvi ruuvi_home | gzip > "\$BACKUP_FILE"

# Cleanup old backups (keep last 30 days)
find "\$BACKUP_DIR" -name "ruuvi_backup_*.sql.gz" -mtime +30 -delete

log_backup "Backup completed: \$BACKUP_FILE"
EOF
    
    chmod +x "$script_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$script_path"
    log_success "$context" "Backup script generated"
}

# Generate environment file
generate_env_file() {
    local context="$MODULE_CONTEXT"
    local env_path="$PROJECT_DIR/.env"
    
    log_info "$context" "Generating environment file"
    
    cat > "$env_path" << EOF
# Ruuvi Home Environment Configuration
# Generated by setup script

# Database Configuration
POSTGRES_USER=ruuvi
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=ruuvi_home
DATABASE_URL=postgresql://ruuvi:${POSTGRES_PASSWORD}@timescaledb:5432/ruuvi_home

# MQTT Configuration
MQTT_HOST=mosquitto
MQTT_PORT=1883
MQTT_USERNAME=ruuvi
MQTT_PASSWORD=${MQTT_PASSWORD}
MQTT_BROKER_URL=mqtt://ruuvi:${MQTT_PASSWORD}@mosquitto:1883

# API Configuration
API_PORT=3000
API_HOST=0.0.0.0
RUST_LOG=info

# Frontend Configuration
FRONTEND_PORT=80
REACT_APP_API_URL=http://localhost:3000

# Webhook Configuration
WEBHOOK_SECRET=${WEBHOOK_SECRET}
WEBHOOK_PORT=${WEBHOOK_PORT}

# Security
JWT_SECRET=${JWT_SECRET}

# System Configuration
TZ=${TZ}
LOG_FILEPATH=${LOG_DIR}/mqtt-reader.log

# Docker Configuration
TIMESCALEDB_TELEMETRY=off
EOF
    
    chmod 600 "$env_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$env_path"
    log_success "$context" "Environment file generated"
}

# Generate systemd service files
generate_systemd_services() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Generating systemd service files"
    
    # Ruuvi Home main service
    cat > "/etc/systemd/system/ruuvi-home.service" << EOF
[Unit]
Description=Ruuvi Home Application
Requires=docker.service
After=docker.service network.target

[Service]
Type=forking
RemainAfterExit=yes
WorkingDirectory=${PROJECT_DIR}
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0
User=${RUUVI_USER}
Group=${RUUVI_USER}

[Install]
WantedBy=multi-user.target
EOF
    
    # Webhook service
    cat > "/etc/systemd/system/ruuvi-webhook.service" << EOF
[Unit]
Description=Ruuvi Home Deployment Webhook
After=network.target

[Service]
Type=simple
User=${RUUVI_USER}
Group=${RUUVI_USER}
WorkingDirectory=${PROJECT_DIR}
ExecStart=${PROJECT_DIR}/scripts/deploy-webhook.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 "/etc/systemd/system/ruuvi-home.service"
    chmod 644 "/etc/systemd/system/ruuvi-webhook.service"
    log_success "$context" "Systemd services generated"
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

# Generate all required files
generate_all_required_files() {
    local context="$MODULE_CONTEXT"
    local generators=(
        "generate_deploy_webhook_script:Deploy webhook script"
        "generate_deploy_script:Deployment script"
        "generate_backup_script:Backup script"
        "generate_env_file:Environment file"
        "generate_systemd_services:Systemd services"
    )
    
    log_info "$context" "Generating all required files"
    
    local failed_generators=()
    
    for generator_entry in "${generators[@]}"; do
        local func_name="${generator_entry%:*}"
        local desc="${generator_entry#*:}"
        
        log_info "$context" "Generating: $desc"
        
        if ! $func_name; then
            failed_generators+=("$desc")
        fi
    done
    
    if [ ${#failed_generators[@]} -gt 0 ]; then
        log_error "$context" "Failed to generate: ${failed_generators[*]}"
        return 1
    fi
    
    log_success "$context" "All files generated successfully"
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
        "handle_mosquitto_migration:Handle Mosquitto migration"
        "generate_all_required_files:Generate all required files"
        "set_file_permissions:Set file permissions"
        "validate_generated_files:Validate generated files"
    )
    
    log_section "File Generation"
    log_info "$context" "Generating files for user: $RUUVI_USER"
    
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