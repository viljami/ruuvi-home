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
Handles GitHub webhook deployments with HTTPS support
"""

import os
import sys
import json
import hmac
import hashlib
import subprocess
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# Configuration
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET', '${WEBHOOK_SECRET}')
WEBHOOK_PORT = int(os.getenv('WEBHOOK_PORT', '${WEBHOOK_PORT}'))
WEBHOOK_ENABLE_HTTPS = os.getenv('WEBHOOK_ENABLE_HTTPS', 'true').lower() == 'true'
WEBHOOK_CERT_PATH = os.getenv('WEBHOOK_CERT_PATH', '${PROJECT_DIR}/ssl/webhook.crt')
WEBHOOK_KEY_PATH = os.getenv('WEBHOOK_KEY_PATH', '${PROJECT_DIR}/ssl/webhook.key')
PROJECT_DIR = '${PROJECT_DIR}'
LOG_FILE = '${LOG_DIR}/webhook.log'

def log_webhook(message):
    """Log webhook messages to file and console"""
    timestamp = os.popen('date "+%Y-%m-%d %H:%M:%S"').read().strip()
    log_entry = f"[{timestamp}] {message}"
    print(log_entry)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, 'a') as f:
            f.write(log_entry + '\n')
    except Exception as e:
        print(f"Failed to write to log file: {e}")

def ensure_ssl_certificates():
    """Ensure SSL certificates exist, generate self-signed if needed"""
    cert_path = Path(WEBHOOK_CERT_PATH)
    key_path = Path(WEBHOOK_KEY_PATH)
    
    if not cert_path.exists() or not key_path.exists():
        log_webhook("SSL certificates not found, generating self-signed certificates...")
        
        # Create SSL directory
        ssl_dir = cert_path.parent
        ssl_dir.mkdir(parents=True, exist_ok=True)
        
        # Generate self-signed certificate
        import subprocess
        try:
            subprocess.run([
                'openssl', 'req', '-x509', '-newkey', 'rsa:4096', '-keyout', str(key_path),
                '-out', str(cert_path), '-days', '365', '-nodes', '-subj',
                '/C=FI/ST=Uusimaa/L=Helsinki/O=RuuviHome/OU=Webhook/CN=webhook.ruuvi.local'
            ], check=True, capture_output=True)
            log_webhook(f"Generated self-signed certificate: {cert_path}")
            log_webhook(f"Generated private key: {key_path}")
            
            # Set proper permissions
            os.chmod(str(key_path), 0o600)
            os.chmod(str(cert_path), 0o644)
            
        except subprocess.CalledProcessError as e:
            log_webhook(f"Failed to generate SSL certificates: {e}")
            return False
        except FileNotFoundError:
            log_webhook("OpenSSL not found, please install: sudo apt install openssl")
            return False
    
    return True

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            content_length = int(self.headers['Content-Length'])
            payload = self.rfile.read(content_length)
            
            log_webhook(f"Received webhook payload from {self.client_address[0]}")
            
            # Verify signature
            signature = self.headers.get('X-Hub-Signature-256')
            if not self.verify_signature(payload, signature):
                log_webhook("Webhook signature verification failed")
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'Unauthorized')
                return
            
            # Parse payload
            data = json.loads(payload.decode('utf-8'))
            
            # Log the event
            event_type = self.headers.get('X-GitHub-Event', 'unknown')
            repository = data.get('repository', {}).get('full_name', 'unknown')
            log_webhook(f"GitHub {event_type} event from {repository}")
            
            # Handle push events to main branch
            if data.get('ref') == 'refs/heads/main':
                log_webhook("Triggering deployment for main branch push")
                self.deploy()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'Deployment triggered successfully')
            else:
                ref = data.get('ref', 'unknown')
                log_webhook(f"No action taken for ref: {ref}")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'No action taken - not main branch')
                
        except json.JSONDecodeError as e:
            log_webhook(f"Invalid JSON payload: {e}")
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'Invalid JSON payload')
        except Exception as e:
            log_webhook(f"Webhook error: {e}")
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b'Internal server error')

    def do_GET(self):
        """Health check endpoint"""
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'Ruuvi Home Webhook Server - OK')

    def log_message(self, format, *args):
        """Override to use our logging function"""
        log_webhook(f"{self.client_address[0]} - {format % args}")
    
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
            log_webhook("Starting deployment process...")
            result = subprocess.run([
                f'{PROJECT_DIR}/scripts/deploy.sh'
            ], check=True, cwd=PROJECT_DIR, capture_output=True, text=True)
            log_webhook("Deployment completed successfully")
            if result.stdout:
                log_webhook(f"Deploy stdout: {result.stdout}")
        except subprocess.CalledProcessError as e:
            error_msg = f"Deployment failed with exit code {e.returncode}"
            if e.stderr:
                error_msg += f": {e.stderr}"
            log_webhook(error_msg)
            raise

if __name__ == '__main__':
    try:
        # Setup SSL if enabled
        if WEBHOOK_ENABLE_HTTPS:
            log_webhook("HTTPS mode enabled")
            if not ensure_ssl_certificates():
                log_webhook("SSL setup failed, falling back to HTTP")
                WEBHOOK_ENABLE_HTTPS = False
        
        # Create server
        server = HTTPServer(('0.0.0.0', WEBHOOK_PORT), WebhookHandler)
        
        if WEBHOOK_ENABLE_HTTPS:
            # Configure SSL context
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(WEBHOOK_CERT_PATH, WEBHOOK_KEY_PATH)
            
            # Security settings
            context.set_ciphers('ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS')
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            
            server.socket = context.wrap_socket(server.socket, server_side=True)
            protocol = "HTTPS"
        else:
            protocol = "HTTP"
        
        log_webhook(f"Webhook server starting on {protocol}://0.0.0.0:{WEBHOOK_PORT}")
        log_webhook(f"Certificate path: {WEBHOOK_CERT_PATH if WEBHOOK_ENABLE_HTTPS else 'N/A'}")
        log_webhook(f"Log file: {LOG_FILE}")
        
        server.serve_forever()
        
    except KeyboardInterrupt:
        log_webhook("Webhook server stopped by user")
    except Exception as e:
        log_webhook(f"Webhook server error: {e}")
        sys.exit(1)
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
cd "$PROJECT_DIR"
git fetch origin
git reset --hard origin/main

# Ensure frontend public directory exists with required files
if [ ! -f "frontend/public/index.html" ]; then
    log_deployment "Creating missing frontend files..."
    mkdir -p frontend/public
    
    # Create basic index.html if missing
    cat > frontend/public/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta name="description" content="Ruuvi Home - Monitor your Ruuvi sensors from home" />
    <link rel="manifest" href="%PUBLIC_URL%/manifest.json" />
    <title>Ruuvi Home</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
HTMLEOF
    
    # Create basic manifest.json if missing
    if [ ! -f "frontend/public/manifest.json" ]; then
        cat > frontend/public/manifest.json << 'JSONEOF'
{
  "short_name": "Ruuvi Home",
  "name": "Ruuvi Home - Sensor Dashboard",
  "description": "Monitor your Ruuvi sensors in real-time",
  "icons": [],
  "start_url": ".",
  "display": "standalone",
  "theme_color": "#1976d2",
  "background_color": "#f5f5f5"
}
JSONEOF
    fi
    
    log_deployment "Frontend files created"
fi

# Deploy based on deployment mode
DEPLOYMENT_MODE=\${DEPLOYMENT_MODE:-local}
COMPOSE_FILE=\${DOCKER_COMPOSE_FILE:-docker-compose.yaml}

if [ "\$DEPLOYMENT_MODE" = "registry" ]; then
    log_deployment "Registry mode: Pulling pre-built images..."
    docker compose -f "\$COMPOSE_FILE" pull
    log_deployment "Starting services with registry images..."
    docker compose -f "\$COMPOSE_FILE" up -d --force-recreate
else
    log_deployment "Local mode: Building Docker images..."
    docker compose -f "\$COMPOSE_FILE" build --no-cache
    log_deployment "Starting services with locally built images..."
    docker compose -f "\$COMPOSE_FILE" up -d --force-recreate
fi

# Wait for services to be ready
log_deployment "Waiting for services to be ready..."
sleep 30

# Verify services are running
if docker compose -f "\$COMPOSE_FILE" ps | grep -q "Up"; then
    log_deployment "Services started successfully"
else
    log_deployment "Warning: Some services may not have started properly"
fi

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
WEBHOOK_ENABLE_HTTPS=${WEBHOOK_ENABLE_HTTPS:-true}
WEBHOOK_CERT_PATH=${PROJECT_DIR}/ssl/webhook.crt
WEBHOOK_KEY_PATH=${PROJECT_DIR}/ssl/webhook.key
WEBHOOK_DOMAIN=${WEBHOOK_DOMAIN:-}
WEBHOOK_EMAIL=${WEBHOOK_EMAIL:-}

# SSL Configuration
ENABLE_LETS_ENCRYPT=${ENABLE_LETS_ENCRYPT:-false}
LETS_ENCRYPT_STAGING=${LETS_ENCRYPT_STAGING:-true}
SSL_CERT_PATH=${PROJECT_DIR}/ssl

# Security
JWT_SECRET=${JWT_SECRET}

# System Configuration
TZ=${TZ}
LOG_FILEPATH=${LOG_DIR}/mqtt-reader.log

# Docker Configuration
TIMESCALEDB_TELEMETRY=off

# Deployment Configuration
DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-local}
DOCKER_COMPOSE_FILE=${DOCKER_COMPOSE_FILE:-docker-compose.yaml}
GITHUB_REGISTRY=${GITHUB_REGISTRY:-ghcr.io}
GITHUB_REPO=${GITHUB_REPO:-}
IMAGE_TAG=${IMAGE_TAG:-latest}

# Public URLs (for production deployments)
PUBLIC_API_URL=${PUBLIC_API_URL:-http://localhost:3000}
CORS_ALLOW_ORIGIN=${CORS_ALLOW_ORIGIN:-*}
EOF
    
    chmod 600 "$env_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$env_path"
    log_success "$context" "Environment file generated"
}

# Generate systemd service files
generate_systemd_services() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Generating systemd service files"
    
    # Determine which compose file to use
    local compose_file="${DOCKER_COMPOSE_FILE:-docker-compose.yaml}"
    log_info "$context" "Using compose file: $compose_file"
    log_info "$context" "Deployment mode: ${DEPLOYMENT_MODE:-local}"
    
    # Detect Docker Compose command and get full path
    local docker_compose_start_cmd
    local docker_compose_stop_cmd
    local docker_compose_pull_cmd
    
    if command -v docker-compose &> /dev/null; then
        local compose_path=$(command -v docker-compose)
        docker_compose_start_cmd="$compose_path -f $compose_file up -d"
        docker_compose_stop_cmd="$compose_path -f $compose_file down"
        docker_compose_pull_cmd="$compose_path -f $compose_file pull"
        log_info "$context" "Using docker-compose at: $compose_path"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        local docker_path=$(command -v docker)
        docker_compose_start_cmd="$docker_path compose -f $compose_file up -d"
        docker_compose_stop_cmd="$docker_path compose -f $compose_file down"
        docker_compose_pull_cmd="$docker_path compose -f $compose_file pull"
        log_info "$context" "Using docker compose plugin at: $docker_path"
    else
        log_error "$context" "Neither docker-compose nor docker compose found"
        return 1
    fi
    
    # For registry mode, add image pull step
    if [ "$DEPLOYMENT_MODE" = "registry" ]; then
        docker_compose_start_cmd="$docker_compose_pull_cmd && $docker_compose_start_cmd"
        log_info "$context" "Registry mode: Will pull images before starting services"
    fi
    
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
ExecStart=${docker_compose_start_cmd}
ExecStop=${docker_compose_stop_cmd}
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

# Generate health check script
generate_health_check_script() {
    local context="$MODULE_CONTEXT"
    local script_path="$PROJECT_DIR/scripts/health-check.py"
    
    log_info "$context" "Generating health check script"
    
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << EOF
#!/usr/bin/env python3
"""
Ruuvi Home Health Check Script
Monitors system and service health
"""

import os
import sys
import time
import subprocess
import json
from datetime import datetime

# Configuration
PROJECT_DIR = '${PROJECT_DIR}'
LOG_FILE = '${LOG_DIR}/health-check.log'

def log_health(level, message):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{timestamp}] [{level}] {message}\n")

def check_docker_services():
    """Check if Docker services are running"""
    try:
        # Try docker compose first, then docker-compose
        try:
            result = subprocess.run(['docker', 'compose', 'ps', '--format', 'json'], 
                                  cwd=PROJECT_DIR, capture_output=True, text=True)
        except FileNotFoundError:
            result = subprocess.run(['docker-compose', 'ps', '--format', 'json'], 
                                  cwd=PROJECT_DIR, capture_output=True, text=True)
        if result.returncode == 0:
            services = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    services.append(json.loads(line))
            
            running_services = [s for s in services if s.get('State') == 'running']
            log_health('INFO', f"Docker services: {len(running_services)}/{len(services)} running")
            return len(running_services) == len(services)
        else:
            log_health('ERROR', 'Failed to check Docker services')
            return False
    except Exception as e:
        log_health('ERROR', f'Docker service check failed: {e}')
        return False

def check_disk_space():
    """Check available disk space"""
    try:
        result = subprocess.run(['df', PROJECT_DIR], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                fields = lines[1].split()
                available = int(fields[3])
                total = int(fields[1])
                usage_percent = ((total - available) / total) * 100
                log_health('INFO', f"Disk usage: {usage_percent:.1f}%")
                return usage_percent < 90
        return False
    except Exception as e:
        log_health('ERROR', f'Disk space check failed: {e}')
        return False

def main():
    log_health('INFO', 'Starting health check')
    
    checks = [
        ('Docker Services', check_docker_services),
        ('Disk Space', check_disk_space),
    ]
    
    failed_checks = []
    for name, check_func in checks:
        if not check_func():
            failed_checks.append(name)
    
    if failed_checks:
        log_health('WARN', f'Failed checks: {", ".join(failed_checks)}')
        sys.exit(1)
    else:
        log_health('INFO', 'All health checks passed')
        sys.exit(0)

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "$script_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$script_path"
    log_success "$context" "Health check script generated"
}

# Generate monitor script
generate_monitor_script() {
    local context="$MODULE_CONTEXT"
    local script_path="$PROJECT_DIR/scripts/monitor.sh"
    
    log_info "$context" "Generating monitor script"
    
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << EOF
#!/bin/bash
# Ruuvi Home System Monitor Script

PROJECT_DIR="${PROJECT_DIR}"
LOG_FILE="${LOG_DIR}/monitoring.log"

log_monitor() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" >> "\$LOG_FILE"
}

# Check CPU usage
cpu_usage=\$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | cut -d'%' -f1)
log_monitor "CPU Usage: \${cpu_usage}%"

# Check memory usage
memory_info=\$(free | grep Mem)
total_mem=\$(echo \$memory_info | awk '{print \$2}')
used_mem=\$(echo \$memory_info | awk '{print \$3}')
mem_percent=\$(( (used_mem * 100) / total_mem ))
log_monitor "Memory Usage: \${mem_percent}%"

# Check disk usage
disk_usage=\$(df \$PROJECT_DIR | tail -1 | awk '{print \$5}' | cut -d'%' -f1)
log_monitor "Disk Usage: \${disk_usage}%"

# Check Docker containers
if command -v docker >/dev/null 2>&1; then
    container_count=\$(docker ps --format "table {{.Names}}" | tail -n +2 | wc -l)
    log_monitor "Running containers: \$container_count"
fi

log_monitor "System monitoring completed"
EOF
    
    chmod +x "$script_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$script_path"
    log_success "$context" "Monitor script generated"
}

# Generate maintenance script
generate_maintenance_script() {
    local context="$MODULE_CONTEXT"
    local script_path="$PROJECT_DIR/scripts/maintenance.sh"
    
    log_info "$context" "Generating maintenance script"
    
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << EOF
#!/bin/bash
# Ruuvi Home Maintenance Script

PROJECT_DIR="${PROJECT_DIR}"
LOG_FILE="${LOG_DIR}/maintenance.log"

log_maintenance() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" | tee -a "\$LOG_FILE"
}

cleanup() {
    log_maintenance "Starting cleanup tasks"
    
    # Clean Docker images and containers
    if command -v docker >/dev/null 2>&1; then
        log_maintenance "Cleaning unused Docker resources"
        docker system prune -f >/dev/null 2>&1 || true
    fi
    
    # Clean old log files (keep last 30 days)
    find "${LOG_DIR}" -name "*.log" -mtime +30 -delete 2>/dev/null || true
    
    log_maintenance "Cleanup completed"
}

update() {
    log_maintenance "Checking for system updates"
    
    # Update package lists
    apt-get update -qq >/dev/null 2>&1 || true
    
    # List available updates
    updates=\$(apt list --upgradable 2>/dev/null | wc -l)
    if [ "\$updates" -gt 1 ]; then
        log_maintenance "\$((updates - 1)) package updates available"
    else
        log_maintenance "System is up to date"
    fi
}

case "\$1" in
    cleanup)
        cleanup
        ;;
    update)
        update
        ;;
    *)
        echo "Usage: \$0 {cleanup|update}"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$script_path"
    chown "$RUUVI_USER:$RUUVI_USER" "$script_path"
    log_success "$context" "Maintenance script generated"
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

# Setup docker-compose file based on deployment mode
setup_docker_compose_file() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Setting up docker-compose file for deployment mode: ${DEPLOYMENT_MODE:-local}"
    
    case "${DEPLOYMENT_MODE:-local}" in
        "registry")
            local compose_file="$PROJECT_DIR/docker-compose.registry.yaml"
            
            # Check if registry compose file exists in the repo
            if [ ! -f "$compose_file" ]; then
                log_info "$context" "Creating docker-compose.registry.yaml file"
                
                cat > "$compose_file" << 'EOF'
services:
  # MQTT Broker
  mosquitto:
    image: eclipse-mosquitto:2.0
    container_name: ruuvi-mosquitto
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./docker/mosquitto/config:/mosquitto/config
      - mosquitto-data:/mosquitto/data
      - mosquitto-log:/mosquitto/log
    restart: unless-stopped
    command: ["mosquitto", "-c", "/mosquitto/config/mosquitto-simple.conf"]
    environment:
      - "ALLOW_ANONYMOUS=true"
    healthcheck:
      test:
        [
          "CMD",
          "mosquitto_sub",
          "-t",
          "$$",
          "-C",
          "1",
          "-i",
          "healthcheck",
          "-W",
          "3",
        ]
      interval: 30s
      timeout: 10s
      retries: 3

  # Time-series Database with TimescaleDB
  timescaledb:
    image: timescale/timescaledb:latest-pg15
    container_name: ruuvi-timescaledb
    ports:
      - "5432:5432"
    volumes:
      - timescaledb-data:/var/lib/postgresql/data
      - ./docker/timescaledb/init-timescaledb.sql:/docker-entrypoint-initdb.d/init-timescaledb.sql
    environment:
      - POSTGRES_DB=ruuvi_home
      - POSTGRES_USER=ruuvi
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ruuvi -d ruuvi_home"]
      interval: 30s
      timeout: 10s
      retries: 3
    command: ["postgres", "-c", "shared_preload_libraries=timescaledb"]

  # MQTT Reader (Rust backend service)
  mqtt-reader:
    image: ${GITHUB_REGISTRY:-ghcr.io}/${GITHUB_REPO}/mqtt-reader:${IMAGE_TAG:-latest}
    container_name: ruuvi-mqtt-reader
    depends_on:
      - mosquitto
      - timescaledb
    environment:
      - MQTT_HOST=mosquitto
      - MQTT_PORT=1883
      - MQTT_TOPIC=ruuvi/gateway/data
      - DATABASE_URL=${DATABASE_URL}
      - RUST_LOG=${RUST_LOG:-info}
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pgrep -f mqtt-reader"]
      interval: 60s
      timeout: 10s
      retries: 3

  # API Server (Rust backend service)
  api-server:
    image: ${GITHUB_REGISTRY:-ghcr.io}/${GITHUB_REPO}/api-server:${IMAGE_TAG:-latest}
    container_name: ruuvi-api-server
    ports:
      - "${API_PORT:-8080}:8080"
    depends_on:
      timescaledb:
        condition: service_healthy
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - API_PORT=8080
      - RUST_LOG=${RUST_LOG:-info}
      - CORS_ALLOW_ORIGIN=${CORS_ALLOW_ORIGIN:-*}
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Frontend Web UI
  frontend:
    image: ${GITHUB_REGISTRY:-ghcr.io}/${GITHUB_REPO}/frontend:${IMAGE_TAG:-latest}
    container_name: ruuvi-frontend
    ports:
      - "${FRONTEND_PORT:-3000}:80"
    depends_on:
      api-server:
        condition: service_healthy
    environment:
      - REACT_APP_API_URL=${PUBLIC_API_URL:-http://localhost:8080}
      - NODE_ENV=production
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  default:
    name: ruuvi-network

volumes:
  timescaledb-data:
  mosquitto-config:
  mosquitto-data:
  mosquitto-log:
EOF
                
                chown "$RUUVI_USER:$RUUVI_USER" "$compose_file"
                log_success "$context" "Created docker-compose.registry.yaml"
            else
                log_info "$context" "Registry compose file already exists"
            fi
            ;;
        "local")
            log_info "$context" "Using existing docker-compose.yaml for local build mode"
            
            # Verify the local compose file exists
            if [ ! -f "$PROJECT_DIR/docker-compose.yaml" ]; then
                log_error "$context" "docker-compose.yaml not found for local build mode"
                return 1
            fi
            ;;
        *)
            log_error "$context" "Unknown deployment mode: ${DEPLOYMENT_MODE}"
            return 1
            ;;
    esac
    
    log_success "$context" "Docker compose file setup completed"
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
        "generate_health_check_script:Health check script"
        "generate_monitor_script:Monitor script"
        "generate_maintenance_script:Maintenance script"
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
        "$PROJECT_DIR/scripts/health-check.py"
        "$PROJECT_DIR/scripts/monitor.sh"
        "$PROJECT_DIR/scripts/maintenance.sh"
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
        "setup_docker_compose_file:Setup docker-compose file"
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