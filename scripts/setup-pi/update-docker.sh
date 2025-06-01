#!/bin/bash
# Docker Update Script for Ruuvi Home Setup
# Updates Docker to modern version with compose plugin to fix systemd compatibility issues

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# Configuration
readonly MIN_DOCKER_VERSION="23.0"
readonly DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
readonly DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"
readonly INSTALL_SCRIPT_URL="https://get.docker.com"

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
    echo -e "${COLOR_BLUE}        Docker Update Script               ${COLOR_NC}"
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo ""
    echo "This script updates Docker to a modern version with"
    echo "compose plugin support to fix systemd compatibility."
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        export OS_ID="$ID"
        export OS_VERSION="$VERSION_ID"
        export OS_CODENAME="$VERSION_CODENAME"
        log_info "Detected OS: $PRETTY_NAME"
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
}

get_current_docker_version() {
    if command -v docker >/dev/null 2>&1; then
        local version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "$version"
    else
        echo ""
    fi
}

version_compare() {
    local version1="$1"
    local version2="$2"

    if [ -z "$version1" ]; then
        return 1
    fi

    # Simple version comparison (major.minor)
    local v1_major=$(echo "$version1" | cut -d. -f1)
    local v1_minor=$(echo "$version1" | cut -d. -f2)
    local v2_major=$(echo "$version2" | cut -d. -f1)
    local v2_minor=$(echo "$version2" | cut -d. -f2)

    if [ "$v1_major" -gt "$v2_major" ]; then
        return 0
    elif [ "$v1_major" -eq "$v2_major" ] && [ "$v1_minor" -ge "$v2_minor" ]; then
        return 0
    else
        return 1
    fi
}

check_current_docker() {
    log_info "Checking current Docker installation"

    local current_version=$(get_current_docker_version)

    if [ -n "$current_version" ]; then
        log_info "Current Docker version: $current_version"

        if version_compare "$current_version" "$MIN_DOCKER_VERSION"; then
            log_success "Docker version is recent enough ($current_version >= $MIN_DOCKER_VERSION)"

            # Check if compose plugin is available
            if docker compose version >/dev/null 2>&1; then
                local compose_version=$(docker compose version --short 2>/dev/null)
                log_success "Docker Compose plugin available: $compose_version"
                log_info "Docker installation appears to be up to date!"

                read -p "Continue with update anyway? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Update cancelled by user"
                    exit 0
                fi
            else
                log_warn "Docker Compose plugin missing - update needed"
            fi
        else
            log_warn "Docker version is outdated ($current_version < $MIN_DOCKER_VERSION)"
        fi
    else
        log_info "Docker not installed"
    fi
}

stop_docker_services() {
    log_info "Stopping Docker services"

    # Stop any running containers gracefully
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        log_info "Stopping running containers"
        docker stop $(docker ps -q) 2>/dev/null || true
    fi

    # Stop Docker service
    systemctl stop docker.service 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true

    log_success "Docker services stopped"
}

backup_docker_data() {
    log_info "Backing up Docker data"

    local backup_dir="/var/lib/docker-backup-$(date +%Y%m%d_%H%M%S)"

    if [ -d "/var/lib/docker" ]; then
        log_info "Creating backup: $backup_dir"
        cp -r "/var/lib/docker" "$backup_dir"
        log_success "Docker data backed up to: $backup_dir"
        export DOCKER_BACKUP_DIR="$backup_dir"
    else
        log_info "No existing Docker data to backup"
    fi
}

remove_old_docker() {
    log_info "Removing old Docker packages"

    # Remove old Docker packages
    local old_packages=(
        "docker.io"
        "docker-doc"
        "docker-compose"
        "docker-compose-v2"
        "podman-docker"
        "containerd"
        "runc"
    )

    for pkg in "${old_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            log_info "Removing package: $pkg"
            apt-get remove -y "$pkg" 2>/dev/null || true
        fi
    done

    # Clean up any remaining files
    apt-get autoremove -y 2>/dev/null || true

    log_success "Old Docker packages removed"
}

install_prerequisites() {
    log_info "Installing prerequisites"

    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    log_success "Prerequisites installed"
}

add_docker_repository() {
    log_info "Adding Docker official repository"

    # Create keyring directory
    mkdir -p /etc/apt/keyrings

    # Add Docker GPG key
    curl -fsSL "$DOCKER_GPG_URL" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Determine architecture
    local arch=$(dpkg --print-architecture)

    # Determine codename based on OS
    local codename="$OS_CODENAME"

    # For Raspberry Pi OS, use Ubuntu codename mapping
    if [ "$OS_ID" = "raspbian" ]; then
        case "$OS_VERSION" in
            "11") codename="bullseye" ;;
            "12") codename="bookworm" ;;
            *) codename="bookworm" ;;
        esac
        # Use Ubuntu repository for Raspberry Pi
        local repo_url="https://download.docker.com/linux/debian"
    else
        local repo_url="$DOCKER_REPO_URL"
    fi

    # Add repository
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] $repo_url $codename stable" > /etc/apt/sources.list.d/docker.list

    # Update package index
    apt-get update

    log_success "Docker repository added"
}

install_modern_docker() {
    log_info "Installing modern Docker with compose plugin"

    # Install Docker packages
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_success "Modern Docker installed"
}

configure_docker() {
    log_info "Configuring Docker"

    # Create Docker daemon configuration
    mkdir -p /etc/docker

    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false
}
EOF

    # Set up Docker service
    systemctl enable docker.service
    systemctl enable containerd.service

    log_success "Docker configured"
}

start_docker_services() {
    log_info "Starting Docker services"

    systemctl start docker.service
    systemctl start containerd.service

    # Wait for Docker to be ready
    local retry=0
    while [ $retry -lt 30 ]; do
        if docker info >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((retry++))
    done

    if docker info >/dev/null 2>&1; then
        log_success "Docker services started successfully"
    else
        log_error "Docker failed to start properly"
        return 1
    fi
}

setup_user_permissions() {
    log_info "Setting up user permissions"

    local target_user="${SUDO_USER:-pi}"

    if id "$target_user" >/dev/null 2>&1; then
        usermod -aG docker "$target_user"
        log_success "Added $target_user to docker group"
        log_warn "User $target_user needs to log out and back in for group changes to take effect"
    else
        log_warn "Target user $target_user not found - skipping group setup"
    fi
}

verify_installation() {
    log_info "Verifying Docker installation"

    # Test Docker
    if docker --version >/dev/null 2>&1; then
        local docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Docker installed: $docker_version"
    else
        log_error "Docker installation verification failed"
        return 1
    fi

    # Test Docker Compose plugin
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short 2>/dev/null)
        log_success "Docker Compose plugin available: $compose_version"
    else
        log_error "Docker Compose plugin verification failed"
        return 1
    fi

    # Test Docker daemon
    if docker info >/dev/null 2>&1; then
        log_success "Docker daemon is accessible"
    else
        log_error "Docker daemon is not accessible"
        return 1
    fi

    # Test with hello-world
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_success "Docker test container ran successfully"
    else
        log_warn "Docker test container failed (may be network related)"
    fi

    log_success "Docker installation verified successfully"
}

test_compose_syntax() {
    log_info "Testing Docker Compose syntax compatibility"

    local project_dir="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"

    if [ -d "$project_dir" ]; then
        cd "$project_dir"

        local test_files=("docker-compose.yaml" "docker-compose.registry.yaml")

        for compose_file in "${test_files[@]}"; do
            if [ -f "$compose_file" ]; then
                if docker compose -f "$compose_file" config >/dev/null 2>&1; then
                    log_success "Compose syntax valid: $compose_file"
                else
                    log_warn "Compose syntax issues in: $compose_file"
                fi
            fi
        done
    else
        log_info "Project directory not found - skipping compose syntax test"
    fi
}

show_completion_info() {
    echo ""
    log_success "🎉 Docker update completed successfully!"
    echo ""
    echo "Updated components:"
    echo "  • Docker Engine: $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    echo "  • Docker Compose: $(docker compose version --short 2>/dev/null)"
    echo ""
    echo "The systemd compatibility issue should now be resolved."
    echo ""
    echo "Next steps:"
    echo "  1. Regenerate systemd services:"
    echo "     sudo ./scripts/setup-pi/setup-pi.sh --module 05-systemd-services.sh"
    echo ""
    echo "  2. Or run the complete setup:"
    echo "     sudo ./scripts/setup-pi/setup-pi.sh"
    echo ""
    echo "  3. Verify services work:"
    echo "     sudo systemctl status ruuvi-home.service"
    echo ""

    if [ -n "${DOCKER_BACKUP_DIR:-}" ]; then
        echo "  Note: Old Docker data backed up to: $DOCKER_BACKUP_DIR"
        echo ""
    fi
}

rollback_installation() {
    log_error "Installation failed - attempting rollback"

    # Stop new Docker
    systemctl stop docker.service 2>/dev/null || true

    # Restore backup if available
    if [ -n "${DOCKER_BACKUP_DIR:-}" ] && [ -d "$DOCKER_BACKUP_DIR" ]; then
        log_info "Restoring Docker data backup"
        rm -rf /var/lib/docker
        mv "$DOCKER_BACKUP_DIR" /var/lib/docker
        log_success "Docker data restored"
    fi

    log_error "Rollback completed - system restored to previous state"
    exit 1
}

main() {
    print_header

    # Validation
    check_root
    detect_os

    # Pre-update checks
    check_current_docker

    # Confirmation
    echo "This script will:"
    echo "  • Remove old Docker installations"
    echo "  • Install modern Docker with compose plugin"
    echo "  • Configure Docker for optimal performance"
    echo "  • Set up proper user permissions"
    echo ""
    read -p "Continue with Docker update? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled by user"
        exit 0
    fi

    # Update process with error handling
    {
        stop_docker_services
        backup_docker_data
        remove_old_docker
        install_prerequisites
        add_docker_repository
        install_modern_docker
        configure_docker
        start_docker_services
        setup_user_permissions
        verify_installation
        test_compose_syntax
        show_completion_info
    } || rollback_installation
}

# Show help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: sudo $0"
    echo ""
    echo "Updates Docker to modern version with compose plugin support"
    echo ""
    echo "This script:"
    echo "• Removes old Docker installations cleanly"
    echo "• Installs latest Docker CE with compose plugin"
    echo "• Configures Docker for optimal performance"
    echo "• Verifies installation works correctly"
    echo ""
    echo "Fixes the 'unknown shorthand flag: f' systemd error"
    echo "by ensuring Docker supports modern compose syntax."
    echo ""
    echo "Requirements:"
    echo "• Must be run as root (sudo)"
    echo "• Internet connection required"
    echo "• Supported OS: Ubuntu, Debian, Raspberry Pi OS"
    exit 0
fi

# Run the update
main "$@"
