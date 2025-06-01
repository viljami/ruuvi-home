#!/bin/bash
# Fix Script for Docker Compose Systemd Issues
# Automatically fixes common Docker and Docker Compose compatibility issues in systemd services

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# Configuration
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"
readonly SERVICE_FILE="/etc/systemd/system/ruuvi-home.service"
readonly WEBHOOK_SERVICE_FILE="/etc/systemd/system/ruuvi-webhook.service"

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $1"
}

print_header() {
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}    Docker Compose Systemd Fix Script     ${COLOR_NC}"
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_compose_command() {
    local compose_cmd=""

    log_info "Detecting available Docker Compose command"

    # Test docker compose (plugin) first
    if docker compose version >/dev/null 2>&1; then
        compose_cmd="docker compose"
        log_success "Docker Compose plugin detected: docker compose"
    # Fallback to standalone docker-compose
    elif command -v docker-compose >/dev/null 2>&1; then
        compose_cmd="docker-compose"
        log_success "Docker Compose standalone detected: docker-compose"
    else
        log_error "No Docker Compose installation found"
        return 1
    fi

    export DETECTED_COMPOSE_CMD="$compose_cmd"
    return 0
}

install_docker_compose_if_missing() {
    if ! detect_compose_command; then
        log_warn "Installing Docker Compose plugin"

        if command -v apt-get >/dev/null 2>&1; then
            apt-get update
            apt-get install -y docker-compose-plugin
            log_success "Docker Compose plugin installed"
        else
            log_error "Cannot install Docker Compose - unsupported package manager"
            return 1
        fi

        # Re-detect after installation
        if ! detect_compose_command; then
            log_error "Docker Compose installation failed"
            return 1
        fi
    fi

    return 0
}

backup_service_files() {
    log_info "Creating backup of existing service files"

    if [ -f "$SERVICE_FILE" ]; then
        cp "$SERVICE_FILE" "${SERVICE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_success "Backed up: $SERVICE_FILE"
    fi

    if [ -f "$WEBHOOK_SERVICE_FILE" ]; then
        cp "$WEBHOOK_SERVICE_FILE" "${WEBHOOK_SERVICE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_success "Backed up: $WEBHOOK_SERVICE_FILE"
    fi
}

determine_compose_file() {
    local compose_file="docker-compose.yaml"

    # Check if in registry mode
    if [ -f "$PROJECT_DIR/.env" ]; then
        local deployment_mode=$(grep "^DEPLOYMENT_MODE=" "$PROJECT_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "local")
        if [ "$deployment_mode" = "registry" ]; then
            compose_file="docker-compose.registry.yaml"
        fi
    fi

    # Verify compose file exists
    if [ ! -f "$PROJECT_DIR/$compose_file" ]; then
        log_warn "Compose file not found: $compose_file, using docker-compose.yaml"
        compose_file="docker-compose.yaml"
    fi

    echo "$compose_file"
}

generate_ruuvi_home_service() {
    local compose_file="$1"
    local user_name="${SUDO_USER:-pi}"

    log_info "Generating ruuvi-home.service with: $DETECTED_COMPOSE_CMD"

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Ruuvi Home Application
Requires=docker.service
After=docker.service network.target

[Service]
Type=forking
RemainAfterExit=yes
User=$user_name
Group=$user_name
WorkingDirectory=$PROJECT_DIR
ExecStart=$DETECTED_COMPOSE_CMD -f $compose_file pull && $DETECTED_COMPOSE_CMD -f $compose_file up -d
ExecStop=$DETECTED_COMPOSE_CMD -f $compose_file down
ExecReload=$DETECTED_COMPOSE_CMD -f $compose_file restart
TimeoutStartSec=120
TimeoutStopSec=60
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_FILE"
    log_success "Generated: $SERVICE_FILE"
}

generate_webhook_service() {
    local user_name="${SUDO_USER:-pi}"

    log_info "Generating ruuvi-webhook.service"

    cat > "$WEBHOOK_SERVICE_FILE" << EOF
[Unit]
Description=Ruuvi Home Deployment Webhook
After=network.target

[Service]
Type=simple
User=$user_name
Group=$user_name
WorkingDirectory=$PROJECT_DIR
ExecStart=/opt/ruuvi-home/bin/ruuvi-deploy-webhook
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$WEBHOOK_SERVICE_FILE"
    log_success "Generated: $WEBHOOK_SERVICE_FILE"
}

reload_and_restart_services() {
    log_info "Reloading systemd and restarting services"

    # Reload systemd
    systemctl daemon-reload
    log_success "Systemd daemon reloaded"

    # Enable services
    systemctl enable ruuvi-home.service
    systemctl enable ruuvi-webhook.service
    log_success "Services enabled"

    # Stop any running services first
    systemctl stop ruuvi-home.service >/dev/null 2>&1 || true
    systemctl stop ruuvi-webhook.service >/dev/null 2>&1 || true

    # Start services
    if systemctl start ruuvi-home.service; then
        log_success "ruuvi-home.service started successfully"
    else
        log_error "Failed to start ruuvi-home.service"
        log_info "Check logs with: journalctl -u ruuvi-home.service -f"
        return 1
    fi

    if systemctl start ruuvi-webhook.service; then
        log_success "ruuvi-webhook.service started successfully"
    else
        log_warn "ruuvi-webhook.service failed to start (may be normal if webhook script missing)"
    fi
}

verify_fix() {
    log_info "Verifying service status"

    # Check ruuvi-home service
    if systemctl is-active ruuvi-home.service >/dev/null 2>&1; then
        log_success "ruuvi-home.service is active and running"
    else
        log_error "ruuvi-home.service is not active"
        log_info "Service status:"
        systemctl status ruuvi-home.service --no-pager | sed 's/^/  /'
        return 1
    fi

    # Check webhook service
    if systemctl is-active ruuvi-webhook.service >/dev/null 2>&1; then
        log_success "ruuvi-webhook.service is active and running"
    else
        log_warn "ruuvi-webhook.service is not active (check if webhook script exists)"
    fi

    # Test Docker Compose command
    cd "$PROJECT_DIR"
    local compose_file=$(determine_compose_file)

    if $DETECTED_COMPOSE_CMD -f "$compose_file" ps >/dev/null 2>&1; then
        log_success "Docker Compose command working correctly"
    else
        log_warn "Docker Compose command test failed"
        return 1
    fi

    return 0
}

show_service_status() {
    echo ""
    log_info "Current service status:"
    echo ""

    echo "Ruuvi Home Service:"
    systemctl status ruuvi-home.service --no-pager | sed 's/^/  /'

    echo ""
    echo "Ruuvi Webhook Service:"
    systemctl status ruuvi-webhook.service --no-pager | sed 's/^/  /'
}

main() {
    print_header

    # Validation
    check_root

    if [ ! -d "$PROJECT_DIR" ]; then
        log_error "Project directory not found: $PROJECT_DIR"
        exit 1
    fi

    # Fix process
    log_info "Starting Docker Compose systemd fix process"
    echo ""

    # Step 1: Install Docker Compose if missing
    if ! install_docker_compose_if_missing; then
        log_error "Cannot proceed without Docker Compose"
        exit 1
    fi

    # Step 2: Backup existing services
    backup_service_files

    # Step 3: Determine compose file
    local compose_file=$(determine_compose_file)
    log_info "Using compose file: $compose_file"

    # Step 4: Generate new service files
    generate_ruuvi_home_service "$compose_file"
    generate_webhook_service

    # Step 5: Reload and restart
    if reload_and_restart_services; then
        log_success "Services reloaded and restarted successfully"
    else
        log_error "Service restart failed"
        show_service_status
        exit 1
    fi

    # Step 6: Verify fix
    if verify_fix; then
        echo ""
        log_success "🎉 Fix completed successfully!"
        log_info "Your systemd services are now using the correct Docker Compose syntax"
    else
        echo ""
        log_warn "Fix applied but verification failed"
        log_info "Manual troubleshooting may be required"
        show_service_status
        exit 1
    fi

    echo ""
    log_info "Useful commands:"
    echo "  • Check service status: sudo systemctl status ruuvi-home.service"
    echo "  • View service logs: sudo journalctl -u ruuvi-home.service -f"
    echo "  • Restart service: sudo systemctl restart ruuvi-home.service"
    echo "  • Test compose: cd $PROJECT_DIR && $DETECTED_COMPOSE_CMD -f $compose_file ps"
}

# Show help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: sudo $0"
    echo ""
    echo "Automatically fixes Docker Compose systemd service issues"
    echo ""
    echo "This script:"
    echo "• Detects available Docker Compose installation"
    echo "• Installs Docker Compose plugin if missing"
    echo "• Regenerates systemd service files with correct syntax"
    echo "• Restarts services with the fixed configuration"
    echo ""
    echo "Run this script if you're experiencing 'unknown shorthand flag: f'"
    echo "or other Docker Compose related systemd service failures."
    exit 0
fi

# Run the fix
main "$@"
