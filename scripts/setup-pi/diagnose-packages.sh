#!/bin/bash
# Package Installation Diagnostic Script
# Diagnoses common package installation issues on Raspberry Pi

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m'

# Test results tracking
declare -i PASS_COUNT=0
declare -i WARN_COUNT=0
declare -i FAIL_COUNT=0
declare -a RECOMMENDATIONS=()

log_test() {
    local status="$1"
    local message="$2"

    case "$status" in
        "PASS")
            echo -e "  ${COLOR_GREEN}✓ PASS${COLOR_NC} $message"
            ((PASS_COUNT++))
            ;;
        "WARN")
            echo -e "  ${COLOR_YELLOW}⚠ WARN${COLOR_NC} $message"
            ((WARN_COUNT++))
            ;;
        "FAIL")
            echo -e "  ${COLOR_RED}✗ FAIL${COLOR_NC} $message"
            ((FAIL_COUNT++))
            ;;
        "INFO")
            echo -e "  ${COLOR_BLUE}ℹ INFO${COLOR_NC} $message"
            ;;
    esac
}

print_header() {
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}        Package Installation Diagnostics       ${COLOR_NC}"
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo ""
    echo "This script diagnoses common package installation issues"
    echo "that cause system setup failures on Raspberry Pi."
    echo ""
}

test_basic_requirements() {
    echo -e "${COLOR_CYAN}=== Basic System Requirements ===${COLOR_NC}"
    echo ""

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        log_test "PASS" "Running with root privileges"
    else
        log_test "FAIL" "Must run with sudo/root privileges"
        RECOMMENDATIONS+=("Run script with: sudo $0")
        return 1
    fi

    # Check system type
    if [ -f /etc/os-release ]; then
        local os_info=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        log_test "INFO" "Operating System: $os_info"

        if grep -q "Raspberry Pi OS\|Raspbian\|Ubuntu" /etc/os-release; then
            log_test "PASS" "Supported operating system detected"
        else
            log_test "WARN" "Unsupported OS - may have compatibility issues"
        fi
    else
        log_test "FAIL" "/etc/os-release not found - cannot determine OS"
    fi

    # Check architecture
    local arch=$(uname -m)
    log_test "INFO" "Architecture: $arch"

    if [[ "$arch" =~ ^(armv|aarch64|x86_64).*$ ]]; then
        log_test "PASS" "Supported architecture"
    else
        log_test "WARN" "Unusual architecture - may have package compatibility issues"
    fi

    echo ""
}

test_disk_space() {
    echo -e "${COLOR_CYAN}=== Disk Space Check ===${COLOR_NC}"
    echo ""

    # Check root filesystem space
    local root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    local root_available=$(df -h / | awk 'NR==2 {print $4}')

    log_test "INFO" "Root filesystem usage: ${root_usage}% (${root_available} available)"

    if [ "$root_usage" -lt 80 ]; then
        log_test "PASS" "Sufficient disk space available"
    elif [ "$root_usage" -lt 90 ]; then
        log_test "WARN" "Disk space getting low - consider cleanup"
        RECOMMENDATIONS+=("Free up disk space: sudo apt autoremove && sudo apt autoclean")
    else
        log_test "FAIL" "Insufficient disk space for package installation"
        RECOMMENDATIONS+=("Critical: Free up disk space immediately")
        RECOMMENDATIONS+=("Run: sudo apt autoremove && sudo apt autoclean")
        RECOMMENDATIONS+=("Consider: sudo journalctl --vacuum-time=7d")
    fi

    # Check /var/cache/apt space specifically
    if [ -d /var/cache/apt ]; then
        local cache_size=$(du -sh /var/cache/apt 2>/dev/null | cut -f1)
        log_test "INFO" "APT cache size: $cache_size"
    fi

    echo ""
}

test_network_connectivity() {
    echo -e "${COLOR_CYAN}=== Network Connectivity ===${COLOR_NC}"
    echo ""

    # Test basic internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_test "PASS" "Internet connectivity available"
    else
        log_test "FAIL" "No internet connectivity"
        RECOMMENDATIONS+=("Check network connection and DNS settings")
        return 1
    fi

    # Test DNS resolution
    if nslookup archive.ubuntu.com >/dev/null 2>&1; then
        log_test "PASS" "DNS resolution working"
    else
        log_test "FAIL" "DNS resolution failed"
        RECOMMENDATIONS+=("Check DNS settings in /etc/resolv.conf")
        RECOMMENDATIONS+=("Try: echo 'nameserver 8.8.8.8' | sudo tee -a /etc/resolv.conf")
    fi

    # Test repository connectivity
    local repo_hosts=("archive.ubuntu.com" "security.ubuntu.com" "ports.ubuntu.com" "archive.raspberrypi.org")

    for host in "${repo_hosts[@]}"; do
        if ping -c 1 "$host" >/dev/null 2>&1; then
            log_test "PASS" "Can reach repository: $host"
        else
            log_test "WARN" "Cannot reach repository: $host"
        fi
    done

    echo ""
}

test_apt_configuration() {
    echo -e "${COLOR_CYAN}=== APT Configuration ===${COLOR_NC}"
    echo ""

    # Check sources.list
    if [ -f /etc/apt/sources.list ]; then
        local source_count=$(grep -v '^#\|^$' /etc/apt/sources.list | wc -l)
        log_test "INFO" "Main sources.list has $source_count active lines"

        if [ "$source_count" -gt 0 ]; then
            log_test "PASS" "Main sources.list is configured"
        else
            log_test "WARN" "Main sources.list appears empty"
        fi
    else
        log_test "WARN" "Main sources.list not found"
    fi

    # Check additional sources
    if [ -d /etc/apt/sources.list.d ]; then
        local additional_sources=$(find /etc/apt/sources.list.d -name "*.list" | wc -l)
        log_test "INFO" "Additional sources: $additional_sources files"
    fi

    # Check for common repository issues
    if grep -r "http://archive.ubuntu.com" /etc/apt/sources.list* 2>/dev/null | grep -q "arm"; then
        log_test "WARN" "Using x86 Ubuntu repos on ARM - should use ports.ubuntu.com"
        RECOMMENDATIONS+=("Fix ARM repositories: use ports.ubuntu.com instead of archive.ubuntu.com")
    fi

    echo ""
}

test_apt_locks() {
    echo -e "${COLOR_CYAN}=== APT Lock Status ===${COLOR_NC}"
    echo ""

    # Check for apt locks
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )

    local locks_found=false

    for lock_file in "${lock_files[@]}"; do
        if [ -f "$lock_file" ]; then
            if lsof "$lock_file" >/dev/null 2>&1; then
                log_test "FAIL" "Lock active: $lock_file"
                locks_found=true
            else
                log_test "PASS" "Lock file exists but not active: $lock_file"
            fi
        fi
    done

    if [ "$locks_found" = true ]; then
        RECOMMENDATIONS+=("Wait for other package operations to complete, or kill them:")
        RECOMMENDATIONS+=("sudo killall apt apt-get dpkg")
        RECOMMENDATIONS+=("sudo rm /var/lib/dpkg/lock*")
        RECOMMENDATIONS+=("sudo dpkg --configure -a")
    else
        log_test "PASS" "No active APT locks detected"
    fi

    # Check for running package managers
    if pgrep -f "apt|dpkg|unattended-upgrade" >/dev/null; then
        log_test "WARN" "Package manager processes running"
        log_test "INFO" "Running processes:"
        pgrep -af "apt|dpkg|unattended-upgrade" | sed 's/^/    /'
        RECOMMENDATIONS+=("Wait for automatic updates to complete")
    else
        log_test "PASS" "No conflicting package manager processes"
    fi

    echo ""
}

test_package_cache() {
    echo -e "${COLOR_CYAN}=== Package Cache Status ===${COLOR_NC}"
    echo ""

    # Check when apt update was last run
    if [ -f /var/cache/apt/pkgcache.bin ]; then
        local cache_age=$(find /var/cache/apt/pkgcache.bin -mtime +1 2>/dev/null | wc -l)
        if [ "$cache_age" -eq 0 ]; then
            log_test "PASS" "Package cache is recent (< 24 hours)"
        else
            log_test "WARN" "Package cache is old (> 24 hours)"
            RECOMMENDATIONS+=("Update package cache: sudo apt update")
        fi
    else
        log_test "WARN" "Package cache not found"
        RECOMMENDATIONS+=("Initialize package cache: sudo apt update")
    fi

    # Test apt update
    log_test "INFO" "Testing apt update..."
    if timeout 30 apt-get -qq update 2>/dev/null; then
        log_test "PASS" "apt update completed successfully"
    else
        log_test "FAIL" "apt update failed or timed out"
        RECOMMENDATIONS+=("Debug with: sudo apt update -v")
    fi

    echo ""
}

test_essential_packages() {
    echo -e "${COLOR_CYAN}=== Essential Package Installation Test ===${COLOR_NC}"
    echo ""

    # Test packages that are most likely to fail
    local test_packages=("curl" "git" "python3" "ca-certificates")

    for package in "${test_packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            log_test "PASS" "Package installed: $package"
        else
            log_test "WARN" "Package not installed: $package"

            # Try to install it
            log_test "INFO" "Attempting to install $package..."
            export DEBIAN_FRONTEND=noninteractive
            if apt-get -y -qq install "$package" 2>/dev/null; then
                log_test "PASS" "Successfully installed: $package"
            else
                log_test "FAIL" "Failed to install: $package"
                RECOMMENDATIONS+=("Debug package installation: sudo apt install -v $package")
            fi
        fi
    done

    echo ""
}

test_raspberry_pi_specific() {
    echo -e "${COLOR_CYAN}=== Raspberry Pi Specific Checks ===${COLOR_NC}"
    echo ""

    # Check if this is a Raspberry Pi
    if [ -f /proc/device-tree/model ]; then
        local model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        log_test "INFO" "Device model: $model"

        if [[ "$model" == *"Raspberry Pi"* ]]; then
            log_test "PASS" "Raspberry Pi detected"

            # Check for Raspberry Pi OS repositories
            if grep -r "raspberrypi.org" /etc/apt/sources.list* >/dev/null 2>&1; then
                log_test "PASS" "Raspberry Pi repositories configured"
            else
                log_test "WARN" "Raspberry Pi repositories not found"
                RECOMMENDATIONS+=("Consider adding: echo 'deb http://archive.raspberrypi.org/debian/ bullseye main' | sudo tee -a /etc/apt/sources.list")
            fi

            # Check for firmware updates
            if command -v rpi-update >/dev/null 2>&1; then
                log_test "PASS" "rpi-update available for firmware updates"
            else
                log_test "WARN" "rpi-update not available"
            fi
        fi
    fi

    # Check memory
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_total / 1024 / 1024))

    log_test "INFO" "Total memory: ${mem_gb}GB"

    if [ "$mem_gb" -ge 2 ]; then
        log_test "PASS" "Sufficient memory for package operations"
    else
        log_test "WARN" "Low memory may cause package installation issues"
        RECOMMENDATIONS+=("Consider increasing swap: sudo dphys-swapfile swapoff && sudo dphys-swapfile swapon")
    fi

    echo ""
}

generate_fix_script() {
    echo -e "${COLOR_CYAN}=== Fix Script Generation ===${COLOR_NC}"
    echo ""

    local fix_script="/tmp/fix-packages.sh"

    cat > "$fix_script" << 'EOF'
#!/bin/bash
# Auto-generated package fix script

set -e

echo "Fixing common package installation issues..."

# Remove package locks
echo "Removing package locks..."
sudo killall apt apt-get dpkg 2>/dev/null || true
sudo rm -f /var/lib/dpkg/lock*
sudo rm -f /var/cache/apt/archives/lock
sudo rm -f /var/lib/apt/lists/lock

# Configure dpkg
echo "Configuring dpkg..."
sudo dpkg --configure -a

# Clean package cache
echo "Cleaning package cache..."
sudo apt-get clean
sudo apt-get autoclean

# Update package lists with detailed output
echo "Updating package lists..."
sudo apt-get update -v

# Fix broken packages
echo "Fixing broken packages..."
sudo apt-get -f install

# Try installing essential packages
echo "Installing essential packages..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get -y install curl git python3 ca-certificates

echo "Package fix script completed!"
EOF

    chmod +x "$fix_script"
    log_test "PASS" "Generated fix script: $fix_script"

    echo ""
}

show_summary() {
    echo -e "${COLOR_BLUE}=== Diagnostic Summary ===${COLOR_NC}"
    echo ""

    echo -e "Test Results:"
    echo -e "  ${COLOR_GREEN}✓ Passed: $PASS_COUNT${COLOR_NC}"
    echo -e "  ${COLOR_YELLOW}⚠ Warnings: $WARN_COUNT${COLOR_NC}"
    echo -e "  ${COLOR_RED}✗ Failed: $FAIL_COUNT${COLOR_NC}"

    echo ""

    if [ ${#RECOMMENDATIONS[@]} -gt 0 ]; then
        echo -e "${COLOR_YELLOW}Recommendations:${COLOR_NC}"
        for rec in "${RECOMMENDATIONS[@]}"; do
            echo "  • $rec"
        done
        echo ""
    fi

    if [ $FAIL_COUNT -gt 0 ]; then
        echo -e "${COLOR_RED}Critical Issues Detected:${COLOR_NC}"
        echo "  1. Run the generated fix script: sudo /tmp/fix-packages.sh"
        echo "  2. Check network connectivity and DNS"
        echo "  3. Ensure sufficient disk space"
        echo "  4. Wait for automatic updates to complete"
        echo ""
    elif [ $WARN_COUNT -gt 0 ]; then
        echo -e "${COLOR_YELLOW}Minor Issues Detected:${COLOR_NC}"
        echo "  1. Consider running: sudo /tmp/fix-packages.sh"
        echo "  2. Monitor disk space usage"
        echo "  3. Update package cache regularly"
        echo ""
    else
        echo -e "${COLOR_GREEN}All Checks Passed:${COLOR_NC}"
        echo "  Package installation should work normally."
        echo "  If you still have issues, check the detailed output above."
        echo ""
    fi

    echo "For more detailed debugging:"
    echo "  • Verbose apt update: sudo apt update -v"
    echo "  • Check logs: sudo journalctl -u apt-daily"
    echo "  • Manual package test: sudo apt install -v curl"
}

main() {
    print_header

    test_basic_requirements || exit 1
    test_disk_space
    test_network_connectivity
    test_apt_configuration
    test_apt_locks
    test_package_cache
    test_essential_packages
    test_raspberry_pi_specific
    generate_fix_script

    show_summary
}

# Handle command line arguments
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Package installation diagnostics for Ruuvi Home setup"
    echo ""
    echo "This script diagnoses common package installation issues"
    echo "that cause system setup failures on Raspberry Pi."
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "The script will:"
    echo "• Check system requirements and disk space"
    echo "• Test network connectivity and DNS"
    echo "• Verify APT configuration and repositories"
    echo "• Check for package manager locks"
    echo "• Test essential package installations"
    echo "• Generate a fix script for common issues"
    echo ""
    exit 0
fi

# Run diagnostics
main "$@"
