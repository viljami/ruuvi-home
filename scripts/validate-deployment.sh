#!/bin/bash
# Ruuvi Home Deployment Validation Script
# This script validates that the Raspberry Pi is properly configured for Ruuvi Home

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Helper functions
log_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAIL_COUNT++))
}

log_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    ((WARN_COUNT++))
}

log_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        log_pass "$1 is installed"
        return 0
    else
        log_fail "$1 is not installed"
        return 1
    fi
}

check_service() {
    if systemctl is-active --quiet "$1"; then
        log_pass "Service $1 is running"
        return 0
    else
        log_fail "Service $1 is not running"
        return 1
    fi
}

check_port() {
    if netstat -tuln | grep -q ":$1 "; then
        log_pass "Port $1 is listening"
        return 0
    else
        log_fail "Port $1 is not listening"
        return 1
    fi
}

check_http_endpoint() {
    if curl -f -s "$1" > /dev/null 2>&1; then
        log_pass "HTTP endpoint $1 is accessible"
        return 0
    else
        log_fail "HTTP endpoint $1 is not accessible"
        return 1
    fi
}

# Print header
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  Ruuvi Home Deployment Validation         ${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# System Information
log_info "System Information:"
echo "  - Hostname: $(hostname)"
echo "  - OS: $(lsb_release -d | cut -f2)"
echo "  - Kernel: $(uname -r)"
echo "  - Architecture: $(uname -m)"
echo "  - Uptime: $(uptime -p)"
echo "  - Load: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# Check if running on Raspberry Pi
if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    log_pass "Running on Raspberry Pi"
    PI_MODEL=$(cat /proc/device-tree/model | tr -d '\0')
    echo "  - Model: $PI_MODEL"
    PI_TEMP=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2 || echo "Unknown")
    echo "  - Temperature: $PI_TEMP"
else
    log_warn "Not running on Raspberry Pi (this is okay for testing)"
fi
echo ""

# Check system requirements
echo -e "${YELLOW}=== System Requirements ===${NC}"
check_command "curl"
check_command "git"
check_command "docker"
check_command "docker-compose" || check_command "docker compose"
check_command "mosquitto_pub"
check_command "mosquitto_sub"
check_command "systemctl"
check_command "ufw"
echo ""

# Check Docker
echo -e "${YELLOW}=== Docker Configuration ===${NC}"
if check_service "docker"; then
    DOCKER_VERSION=$(docker --version)
    log_info "Docker version: $DOCKER_VERSION"
    
    # Check if pi user is in docker group
    if groups pi | grep -q docker; then
        log_pass "User 'pi' is in docker group"
    else
        log_fail "User 'pi' is not in docker group"
    fi
    
    # Check Docker daemon configuration
    if [ -f /etc/docker/daemon.json ]; then
        log_pass "Docker daemon configuration exists"
        if grep -q "log-driver" /etc/docker/daemon.json; then
            log_pass "Docker logging is configured"
        else
            log_warn "Docker logging configuration not found"
        fi
    else
        log_warn "Docker daemon configuration not found"
    fi
fi
echo ""

# Check project directories
echo -e "${YELLOW}=== Project Directory Structure ===${NC}"
PROJECT_DIR="/home/pi/ruuvi-home"
DATA_DIR="$PROJECT_DIR/data"
LOG_DIR="/var/log/ruuvi-home"

if [ -d "$PROJECT_DIR" ]; then
    log_pass "Project directory exists: $PROJECT_DIR"
    
    # Check ownership
    if [ "$(stat -c %U "$PROJECT_DIR")" = "pi" ]; then
        log_pass "Project directory has correct ownership"
    else
        log_fail "Project directory has incorrect ownership"
    fi
    
    # Check for git repository
    if [ -d "$PROJECT_DIR/.git" ]; then
        log_pass "Git repository exists"
        cd "$PROJECT_DIR"
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
        log_info "Current branch: $CURRENT_BRANCH"
    else
        log_fail "Git repository not found"
    fi
    
    # Check for important files
    if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        log_pass "docker-compose.yml exists"
    else
        log_fail "docker-compose.yml not found"
    fi
    
    if [ -f "$PROJECT_DIR/.env" ]; then
        log_pass ".env file exists"
    else
        log_warn ".env file not found (you may need to copy from .env.example)"
    fi
    
    if [ -f "$PROJECT_DIR/.env.example" ]; then
        log_pass ".env.example file exists"
    else
        log_fail ".env.example file not found"
    fi
else
    log_fail "Project directory not found: $PROJECT_DIR"
fi

# Check data directories
if [ -d "$DATA_DIR" ]; then
    log_pass "Data directory exists: $DATA_DIR"
    
    for subdir in influxdb mosquitto/data mosquitto/log mosquitto/config; do
        if [ -d "$DATA_DIR/$subdir" ]; then
            log_pass "Data subdirectory exists: $subdir"
        else
            log_warn "Data subdirectory missing: $subdir"
        fi
    done
else
    log_fail "Data directory not found: $DATA_DIR"
fi

# Check log directory
if [ -d "$LOG_DIR" ]; then
    log_pass "Log directory exists: $LOG_DIR"
    if [ "$(stat -c %U "$LOG_DIR")" = "pi" ]; then
        log_pass "Log directory has correct ownership"
    else
        log_fail "Log directory has incorrect ownership"
    fi
else
    log_fail "Log directory not found: $LOG_DIR"
fi
echo ""

# Check services
echo -e "${YELLOW}=== System Services ===${NC}"
check_service "docker"
check_service "mosquitto"
check_service "ufw"
check_service "fail2ban"

# Check if ruuvi-home service exists
if systemctl list-unit-files | grep -q ruuvi-home; then
    if systemctl is-enabled --quiet ruuvi-home; then
        log_pass "ruuvi-home service is enabled"
    else
        log_warn "ruuvi-home service is not enabled"
    fi
else
    log_warn "ruuvi-home systemd service not found"
fi
echo ""

# Check network ports
echo -e "${YELLOW}=== Network Ports ===${NC}"
check_port "22"     # SSH
check_port "1883"   # MQTT
check_port "8080"   # API (if running)
check_port "8086"   # InfluxDB (if running)
echo ""

# Check firewall
echo -e "${YELLOW}=== Firewall Configuration ===${NC}"
if ufw status | grep -q "Status: active"; then
    log_pass "UFW firewall is active"
    
    # Check specific rules
    if ufw status | grep -q "1883"; then
        log_pass "MQTT port (1883) is allowed in firewall"
    else
        log_warn "MQTT port (1883) not found in firewall rules"
    fi
    
    if ufw status | grep -q "8080"; then
        log_pass "API port (8080) is allowed in firewall"
    else
        log_warn "API port (8080) not found in firewall rules"
    fi
else
    log_warn "UFW firewall is not active"
fi
echo ""

# Check MQTT broker
echo -e "${YELLOW}=== MQTT Broker ===${NC}"
if check_service "mosquitto"; then
    # Test MQTT connectivity
    if timeout 5 mosquitto_pub -h localhost -t test/validation -m "test" 2>/dev/null; then
        log_pass "MQTT broker accepts connections"
    else
        log_fail "MQTT broker connection test failed"
    fi
    
    # Check MQTT configuration
    if [ -f /etc/mosquitto/conf.d/ruuvi-home.conf ]; then
        log_pass "MQTT configuration file exists"
    else
        log_warn "Custom MQTT configuration not found"
    fi
fi
echo ""

# Check Docker containers (if running)
echo -e "${YELLOW}=== Docker Containers ===${NC}"
if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    cd "$PROJECT_DIR"
    
    if docker-compose ps | grep -q "Up"; then
        log_pass "Some Docker containers are running"
        
        # List running containers
        echo "Running containers:"
        docker-compose ps --format "table {{.Name}}\t{{.Status}}" | grep -v "^NAME"
        
        # Check specific services
        for service in mosquitto influxdb mqtt-reader api-server; do
            if docker-compose ps | grep -q "$service.*Up"; then
                log_pass "Container $service is running"
            else
                log_warn "Container $service is not running"
            fi
        done
    else
        log_warn "No Docker containers are currently running"
    fi
else
    log_warn "Cannot check Docker containers (project directory or compose file missing)"
fi
echo ""

# Check HTTP endpoints (if services are running)
echo -e "${YELLOW}=== HTTP Endpoints ===${NC}"
check_http_endpoint "http://localhost:8086/health"  # InfluxDB
check_http_endpoint "http://localhost:8080/health"  # API Server
echo ""

# Check environment variables
echo -e "${YELLOW}=== Environment Configuration ===${NC}"
if [ -f "$PROJECT_DIR/.env" ]; then
    cd "$PROJECT_DIR"
    
    # Check for required variables
    REQUIRED_VARS=("INFLUXDB_TOKEN" "GATEWAY_MAC" "MQTT_TOPIC")
    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^$var=" .env && ! grep -q "^$var=$" .env; then
            log_pass "Environment variable $var is set"
        else
            log_warn "Environment variable $var is not set or empty"
        fi
    done
    
    # Check for default/example values that should be changed
    if grep -q "my-super-secret-auth-token" .env; then
        log_warn "INFLUXDB_TOKEN appears to be using default example value"
    fi
    
    if grep -q "AA:BB:CC:DD:EE:FF" .env; then
        log_warn "GATEWAY_MAC appears to be using example value"
    fi
else
    log_fail "Environment file (.env) not found"
fi
echo ""

# Check log rotation
echo -e "${YELLOW}=== Log Management ===${NC}"
if [ -f /etc/logrotate.d/ruuvi-home ]; then
    log_pass "Log rotation configuration exists"
else
    log_warn "Log rotation configuration not found"
fi

# Check for log files
if [ -d "$LOG_DIR" ]; then
    LOG_FILES=$(find "$LOG_DIR" -name "*.log" 2>/dev/null | wc -l)
    if [ "$LOG_FILES" -gt 0 ]; then
        log_pass "Application log files found ($LOG_FILES files)"
    else
        log_warn "No application log files found"
    fi
fi
echo ""

# Check system resources
echo -e "${YELLOW}=== System Resources ===${NC}"
# Memory check
MEMORY_MB=$(free -m | awk 'NR==2{printf "%.0f", $2}')
if [ "$MEMORY_MB" -ge 1024 ]; then
    log_pass "Sufficient memory available (${MEMORY_MB}MB)"
else
    log_warn "Low memory detected (${MEMORY_MB}MB) - consider adding swap"
fi

# Disk space check
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    log_pass "Disk usage is acceptable (${DISK_USAGE}%)"
else
    log_warn "High disk usage detected (${DISK_USAGE}%)"
fi

# Temperature check (Raspberry Pi only)
if command -v vcgencmd &> /dev/null; then
    TEMP=$(vcgencmd measure_temp | grep -o '[0-9.]*')
    if [ "$(echo "$TEMP < 70" | bc -l)" -eq 1 ]; then
        log_pass "CPU temperature is normal (${TEMP}°C)"
    else
        log_warn "High CPU temperature detected (${TEMP}°C)"
    fi
fi
echo ""

# Security checks
echo -e "${YELLOW}=== Security Configuration ===${NC}"
# Check SSH configuration
if [ -f /etc/ssh/sshd_config ]; then
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        log_pass "SSH password authentication is disabled"
    else
        log_warn "SSH password authentication may be enabled"
    fi
    
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        log_pass "SSH root login is disabled"
    else
        log_warn "SSH root login may be enabled"
    fi
fi

# Check for automatic updates
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    log_pass "Automatic security updates are configured"
else
    log_warn "Automatic security updates not configured"
fi
echo ""

# Final summary
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  Validation Summary                        ${NC}"
echo -e "${BLUE}=============================================${NC}"
echo -e "${GREEN}Passed checks: $PASS_COUNT${NC}"
echo -e "${YELLOW}Warnings: $WARN_COUNT${NC}"
echo -e "${RED}Failed checks: $FAIL_COUNT${NC}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    if [ "$WARN_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed! Your Raspberry Pi is ready for Ruuvi Home deployment.${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Validation completed with warnings. Review the warnings above.${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ Validation failed with $FAIL_COUNT critical issues. Please address the failed checks.${NC}"
    exit 1
fi