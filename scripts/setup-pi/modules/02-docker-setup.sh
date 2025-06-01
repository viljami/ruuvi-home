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
readonly DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"
readonly DOCKER_SERVICE="docker"
readonly MIN_DOCKER_VERSION="23.0"

# Check if Docker is already installed and working
check_docker_installation() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Checking existing Docker installation"

    if command -v docker &> /dev/null; then
        if docker --version &> /dev/null; then
            local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
            log_success "$context" "Docker already installed: $docker_version"

            # Check if it's modern enough and has compose plugin
            local version_major=$(echo "$docker_version" | cut -d'.' -f1)
            if [ "$version_major" -ge 23 ] && docker compose version >/dev/null 2>&1; then
                log_success "$context" "Docker is modern with compose plugin"
                return 0
            else
                log_warn "$context" "Docker is outdated or missing compose plugin - will update"
                return 1
            fi
        else
            log_warn "$context" "Docker command found but not responding"
            return 1
        fi
    else
        log_info "$context" "Docker not installed"
        return 1
    fi
}

# Install modern Docker from official repository
install_docker_engine() {
    local context="$MODULE_CONTEXT"

    log_info "$context" "Installing modern Docker Engine with compose plugin"

    # Install prerequisites
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release

    # Determine OS type and repository details first
    local arch=$(dpkg --print-architecture)
    local codename=$(lsb_release -cs)
    local repo_url="https://download.docker.com/linux/ubuntu"
    local gpg_url="https://download.docker.com/linux/ubuntu/gpg"

    # Detect OS type and set appropriate repository
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "$context" "Detected OS: $ID $VERSION_CODENAME"

        # Handle Debian-based systems (including Raspberry Pi OS)
        if [ "$ID" = "debian" ] || [ "$ID" = "raspbian" ] || [ "$ID_LIKE" = "debian" ]; then
            repo_url="https://download.docker.com/linux/debian"
            gpg_url="https://download.docker.com/linux/debian/gpg"

            # Use stable Debian codename for Raspberry Pi OS
            if [ "$ID" = "raspbian" ]; then
                codename="bookworm"
            fi

            log_info "$context" "Using Debian Docker repository"
        else
            log_info "$context" "Using Ubuntu Docker repository"
        fi
    else
        log_warn "$context" "Could not detect OS, defaulting to Ubuntu repository"
    fi

    log_info "$context" "Repository: $repo_url, Codename: $codename, Architecture: $arch"

    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL "$gpg_url" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] $repo_url $codename stable" > /etc/apt/sources.list.d/docker.list

    # Update package index
    apt-get update

    # Install Docker packages including compose plugin
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_success "$context" "Modern Docker Engine with compose plugin installed"
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

    # Check Docker Compose plugin
    if ! docker compose version; then
        log_error "$context" "Docker Compose plugin check failed"
        return 1
    fi

    local compose_version=$(docker compose version --short 2>/dev/null)
    log_success "$context" "Docker Compose plugin available: $compose_version"

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
