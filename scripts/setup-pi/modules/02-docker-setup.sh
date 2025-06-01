#!/bin/bash
# Module: Docker Setup
# Description: Installs and configures Docker Engine and Docker Compose
# Dependencies: 00-validation.sh (system requirements)

set -e

# Module context for logging
readonly MODULE_CONTEXT="DOCKER"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# Docker configuration
readonly DOCKER_INSTALL_SCRIPT_URL="https://get.docker.com"
readonly DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"
readonly DOCKER_SERVICE="docker"

# Check if Docker is already installed and working
check_docker_installation() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Checking existing Docker installation"

    if command -v docker &> /dev/null; then
        if docker --version &> /dev/null; then
            local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
            log_success "$context" "Docker already installed: $docker_version"
            return 0
        else
            log_warn "$context" "Docker command found but not responding"
            return 1
        fi
    else
        log_info "$context" "Docker not installed"
        return 1
    fi
}

# Download and execute Docker installation script
install_docker_engine() {
    local context="$MODULE_CONTEXT"
    local install_script="/tmp/get-docker.sh"

    log_info "$context" "Installing Docker Engine"

    # Download installation script
    log_debug "$context" "Downloading Docker installation script"
    if ! curl -fsSL "$DOCKER_INSTALL_SCRIPT_URL" -o "$install_script"; then
        log_error "$context" "Failed to download Docker installation script"
        return 1
    fi

    # Verify script was downloaded
    if [ ! -f "$install_script" ] || [ ! -s "$install_script" ]; then
        log_error "$context" "Docker installation script is empty or missing"
        return 1
    fi

    # Execute installation script
    log_info "$context" "Executing Docker installation script"
    if ! sh "$install_script"; then
        log_error "$context" "Docker installation failed"
        rm -f "$install_script"
        return 1
    fi

    # Cleanup
    rm -f "$install_script"
    log_success "$context" "Docker Engine installation completed"
    return 0
}

# Configure Docker daemon settings
configure_docker_daemon() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Configuring Docker daemon"

    # Ensure Docker config directory exists
    mkdir -p "$(dirname "$DOCKER_DAEMON_CONFIG")"

    # Create daemon configuration
    cat > "$DOCKER_DAEMON_CONFIG" << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "${DOCKER_LOG_MAX_SIZE}",
        "max-file": "${DOCKER_LOG_MAX_FILE}"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "metrics-addr": "127.0.0.1:9323",
    "iptables": true
}
EOF

    if [ $? -eq 0 ]; then
        log_success "$context" "Docker daemon configuration created"
    else
        log_error "$context" "Failed to create Docker daemon configuration"
        return 1
    fi
}

# Set up user permissions for Docker
setup_docker_user_permissions() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Setting up Docker user permissions"

    # Add user to docker group
    if ! usermod -aG docker "$RUUVI_USER"; then
        log_error "$context" "Failed to add user $RUUVI_USER to docker group"
        return 1
    fi

    log_success "$context" "User $RUUVI_USER added to docker group"

    # Verify group membership
    if groups "$RUUVI_USER" | grep -q docker; then
        log_success "$context" "Docker group membership confirmed"
    else
        log_warn "$context" "Docker group membership not immediately visible (requires logout/login)"
    fi

    return 0
}

# Start and enable Docker service
start_docker_service() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Starting Docker service"

    # Reload systemd daemon to pick up new configuration
    if ! systemctl daemon-reload; then
        log_error "$context" "Failed to reload systemd daemon"
        return 1
    fi

    # Enable Docker service
    if ! systemctl enable "$DOCKER_SERVICE"; then
        log_error "$context" "Failed to enable Docker service"
        return 1
    fi

    # Start Docker service
    if ! systemctl start "$DOCKER_SERVICE"; then
        log_error "$context" "Failed to start Docker service"
        return 1
    fi

    # Wait for Docker to be ready
    local max_attempts=30
    local attempt=1

    log_info "$context" "Waiting for Docker service to be ready"

    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet "$DOCKER_SERVICE"; then
            log_success "$context" "Docker service is active"
            break
        fi

        log_debug "$context" "Waiting for Docker service (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        log_error "$context" "Docker service failed to start within timeout"
        return 1
    fi

    return 0
}

# Validate Docker installation
validate_docker_installation() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Validating Docker installation"

    # Check Docker version
    if ! docker --version; then
        log_error "$context" "Docker version check failed"
        return 1
    fi

    # Check Docker Compose version
    if ! docker compose version; then
        log_error "$context" "Docker Compose version check failed"
        return 1
    fi

    # Test Docker functionality with hello-world
    log_info "$context" "Testing Docker functionality"
    if docker run --rm hello-world &>/dev/null; then
        log_success "$context" "Docker functionality test passed"
    else
        log_warn "$context" "Docker functionality test failed (may work after user login)"
    fi

    # Check service status
    if systemctl is-active --quiet "$DOCKER_SERVICE"; then
        log_success "$context" "Docker service is running"
    else
        log_error "$context" "Docker service is not running"
        return 1
    fi

    return 0
}

# Configure Docker for production use
configure_docker_production() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Configuring Docker for production use"

    # Set up log rotation for Docker containers
    cat > /etc/logrotate.d/docker-containers << EOF
/var/lib/docker/containers/*/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    su root root
}
EOF

    # Configure Docker to start on boot
    if ! systemctl is-enabled --quiet "$DOCKER_SERVICE"; then
        systemctl enable "$DOCKER_SERVICE"
    fi

    log_success "$context" "Production configuration completed"
    return 0
}

# Main Docker setup function
setup_docker() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "check_docker_installation:Check existing installation"
        "install_docker_engine:Install Docker Engine"
        "configure_docker_daemon:Configure daemon"
        "setup_docker_user_permissions:Setup user permissions"
        "start_docker_service:Start Docker service"
        "configure_docker_production:Production configuration"
        "validate_docker_installation:Validate installation"
    )

    log_section "Docker Setup"
    log_info "$context" "Starting Docker setup for user: $RUUVI_USER"

    local step_num=1
    local total_steps=${#setup_steps[@]}
    local failed_steps=()

    # Check if Docker is already installed and working
    if check_docker_installation; then
        log_info "$context" "Docker already installed, skipping installation steps"
        # Skip installation but run configuration steps
        local config_steps=(
            "configure_docker_daemon:Configure daemon"
            "setup_docker_user_permissions:Setup user permissions"
            "start_docker_service:Restart Docker service"
            "configure_docker_production:Production configuration"
            "validate_docker_installation:Validate installation"
        )
        setup_steps=("${config_steps[@]}")
        total_steps=${#setup_steps[@]}
    fi

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
        log_error "$context" "Docker setup failed at: ${failed_steps[*]}"
        return 1
    fi

    log_success "$context" "Docker setup completed successfully"
    log_info "$context" "Note: User may need to logout and login for group permissions to take effect"
    return 0
}

# Export main function
export -f setup_docker

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_docker
fi
