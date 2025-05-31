#!/bin/bash
# Module: Directory Structure Setup
# Description: Creates project directory structure and clones repository
# Dependencies: 01-system-setup.sh (git installation)

set -e

# Module context for logging
readonly MODULE_CONTEXT="DIRECTORIES"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"
source "$CONFIG_DIR/setup.env"

# Repository configuration
readonly REPO_URL="https://github.com/viljami/ruuvi-home.git"
readonly REPO_BRANCH="main"

# Create base project directory
create_project_directory() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Creating project directory: $PROJECT_DIR"
    
    # Check if directory already exists
    if [ -d "$PROJECT_DIR" ]; then
        log_warn "$context" "Project directory already exists: $PROJECT_DIR"
        return 0
    fi
    
    # Create directory with proper permissions
    if ! mkdir -p "$PROJECT_DIR"; then
        log_error "$context" "Failed to create project directory: $PROJECT_DIR"
        return 1
    fi
    
    # Set ownership
    if ! chown "$RUUVI_USER:$RUUVI_USER" "$PROJECT_DIR"; then
        log_error "$context" "Failed to set ownership of project directory"
        return 1
    fi
    
    log_success "$context" "Project directory created: $PROJECT_DIR"
    return 0
}

# Clone or update repository
setup_repository() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Setting up repository"
    
    if [ -d "$PROJECT_DIR/.git" ]; then
        log_info "$context" "Updating existing repository"
        
        # Change to project directory as the target user
        cd "$PROJECT_DIR"
        
        # Fetch latest changes
        if ! sudo -u "$RUUVI_USER" git fetch origin; then
            log_error "$context" "Failed to fetch repository updates"
            return 1
        fi
        
        # Reset to latest main branch
        if ! sudo -u "$RUUVI_USER" git reset --hard "origin/$REPO_BRANCH"; then
            log_error "$context" "Failed to reset to latest branch"
            return 1
        fi
        
        log_success "$context" "Repository updated to latest version"
    else
        log_info "$context" "Cloning repository: $REPO_URL"
        
        # Remove project directory if it exists but is not a git repo
        if [ -d "$PROJECT_DIR" ]; then
            rm -rf "$PROJECT_DIR"
        fi
        
        # Clone repository as target user
        if ! sudo -u "$RUUVI_USER" git clone "$REPO_URL" "$PROJECT_DIR"; then
            log_error "$context" "Failed to clone repository"
            return 1
        fi
        
        # Switch to correct branch
        cd "$PROJECT_DIR"
        if ! sudo -u "$RUUVI_USER" git checkout "$REPO_BRANCH"; then
            log_error "$context" "Failed to checkout branch: $REPO_BRANCH"
            return 1
        fi
        
        log_success "$context" "Repository cloned successfully"
    fi
    
    return 0
}

# Create data directories
create_data_directories() {
    local context="$MODULE_CONTEXT"
    local data_dirs=(
        "$DATA_DIR"
        "$DATA_DIR/timescaledb"
        "$DATA_DIR/mosquitto/data"
        "$DATA_DIR/mosquitto/log"
        "$DATA_DIR/mosquitto/config"
        "$DATA_DIR/auth-db"
        "$DATA_DIR/frontend"
        "$DATA_DIR/api"
    )
    
    log_info "$context" "Creating data directories"
    
    for dir in "${data_dirs[@]}"; do
        log_debug "$context" "Creating directory: $dir"
        
        if ! mkdir -p "$dir"; then
            log_error "$context" "Failed to create directory: $dir"
            return 1
        fi
        
        # Set ownership to target user
        if ! chown "$RUUVI_USER:$RUUVI_USER" "$dir"; then
            log_error "$context" "Failed to set ownership: $dir"
            return 1
        fi
    done
    
    # Set specific permissions for sensitive directories
    chmod 750 "$DATA_DIR/timescaledb" || true
    chmod 750 "$DATA_DIR/auth-db" || true
    chmod 755 "$DATA_DIR/mosquitto/data" || true
    chmod 755 "$DATA_DIR/mosquitto/log" || true
    
    log_success "$context" "Data directories created"
    return 0
}

# Create log directories
create_log_directories() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Creating log directories"
    
    # Create main log directory
    if ! mkdir -p "$LOG_DIR"; then
        log_error "$context" "Failed to create log directory: $LOG_DIR"
        return 1
    fi
    
    # Set ownership and permissions
    chown "$RUUVI_USER:$RUUVI_USER" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    # Create log files with proper permissions
    local log_files=(
        "$LOG_DIR/setup.log"
        "$LOG_DIR/deployment.log"
        "$LOG_DIR/backup.log"
        "$LOG_DIR/webhook.log"
        "$LOG_DIR/health-check.log"
    )
    
    for log_file in "${log_files[@]}"; do
        touch "$log_file"
        chown "$RUUVI_USER:$RUUVI_USER" "$log_file"
        chmod 644 "$log_file"
    done
    
    log_success "$context" "Log directories created"
    return 0
}

# Create backup directory
create_backup_directory() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Creating backup directory"
    
    if ! mkdir -p "$BACKUP_DIR"; then
        log_error "$context" "Failed to create backup directory: $BACKUP_DIR"
        return 1
    fi
    
    # Set ownership and permissions
    chown "$RUUVI_USER:$RUUVI_USER" "$BACKUP_DIR"
    chmod 750 "$BACKUP_DIR"  # More restrictive for backups
    
    log_success "$context" "Backup directory created: $BACKUP_DIR"
    return 0
}

# Create configuration directory structure
create_config_directories() {
    local context="$MODULE_CONTEXT"
    local config_dirs=(
        "$PROJECT_DIR/config"
        "$PROJECT_DIR/config/nginx"
        "$PROJECT_DIR/config/mosquitto"
        "$PROJECT_DIR/config/timescaledb"
    )
    
    log_info "$context" "Creating configuration directories"
    
    for dir in "${config_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "$context" "Failed to create config directory: $dir"
            return 1
        fi
        
        chown "$RUUVI_USER:$RUUVI_USER" "$dir"
        chmod 755 "$dir"
    done
    
    log_success "$context" "Configuration directories created"
    return 0
}

# Set up environment file
setup_environment_file() {
    local context="$MODULE_CONTEXT"
    local env_file="$PROJECT_DIR/.env"
    local env_example="$PROJECT_DIR/.env.example"
    
    log_info "$context" "Setting up environment file"
    
    # Check if .env.example exists
    if [ ! -f "$env_example" ]; then
        log_warn "$context" ".env.example not found, creating basic template"
        
        # Create basic .env.example
        cat > "$env_example" << EOF
# Ruuvi Home Environment Configuration
# Copy this file to .env and configure your settings

# Database Configuration
POSTGRES_USER=ruuvi
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_DB=ruuvi_home
DATABASE_URL=postgresql://ruuvi:your_secure_password_here@timescaledb:5432/ruuvi_home

# MQTT Configuration
MQTT_HOST=mosquitto
MQTT_PORT=1883
MQTT_USERNAME=ruuvi
MQTT_PASSWORD=your_mqtt_password_here

# API Configuration
API_PORT=3000
API_HOST=0.0.0.0

# Frontend Configuration
FRONTEND_PORT=80

# Webhook Configuration
WEBHOOK_SECRET=${WEBHOOK_SECRET:-}
WEBHOOK_PORT=${WEBHOOK_PORT}

# Timezone
TZ=${TIMEZONE}
EOF
        
        chown "$RUUVI_USER:$RUUVI_USER" "$env_example"
    fi
    
    # Create .env from example if it doesn't exist
    if [ ! -f "$env_file" ]; then
        log_info "$context" "Creating .env file from template"
        cp "$env_example" "$env_file"
        chown "$RUUVI_USER:$RUUVI_USER" "$env_file"
        chmod 600 "$env_file"  # Restrictive permissions for secrets
        
        log_info "$context" "Please configure $env_file with your settings"
    else
        log_success "$context" "Environment file already exists"
    fi
    
    return 0
}

# Create scripts directory structure
create_scripts_directories() {
    local context="$MODULE_CONTEXT"
    local script_dirs=(
        "$PROJECT_DIR/scripts"
        "$PROJECT_DIR/scripts/maintenance"
        "$PROJECT_DIR/scripts/monitoring"
    )
    
    log_info "$context" "Creating scripts directories"
    
    for dir in "${script_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "$context" "Failed to create scripts directory: $dir"
            return 1
        fi
        
        chown "$RUUVI_USER:$RUUVI_USER" "$dir"
        chmod 755 "$dir"
    done
    
    log_success "$context" "Scripts directories created"
    return 0
}

# Validate directory structure
validate_directory_structure() {
    local context="$MODULE_CONTEXT"
    local required_dirs=(
        "$PROJECT_DIR"
        "$DATA_DIR"
        "$LOG_DIR"
        "$BACKUP_DIR"
        "$PROJECT_DIR/config"
        "$PROJECT_DIR/scripts"
    )
    
    log_info "$context" "Validating directory structure"
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "$context" "Required directory missing: $dir"
            return 1
        fi
        
        if [ ! -w "$dir" ]; then
            log_error "$context" "Directory not writable: $dir"
            return 1
        fi
        
        # Check ownership
        local owner=$(stat -c '%U' "$dir")
        if [ "$owner" != "$RUUVI_USER" ]; then
            log_error "$context" "Incorrect ownership for $dir: $owner (expected: $RUUVI_USER)"
            return 1
        fi
    done
    
    # Check if repository is properly cloned
    if [ ! -d "$PROJECT_DIR/.git" ]; then
        log_error "$context" "Git repository not found in project directory"
        return 1
    fi
    
    # Check if docker-compose.yml exists
    if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
        log_error "$context" "docker-compose.yml not found in project directory"
        return 1
    fi
    
    log_success "$context" "Directory structure validation passed"
    return 0
}

# Main directory setup function
setup_directories() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "create_project_directory:Create project directory"
        "setup_repository:Setup repository"
        "create_data_directories:Create data directories"
        "create_log_directories:Create log directories"
        "create_backup_directory:Create backup directory"
        "create_config_directories:Create config directories"
        "create_scripts_directories:Create scripts directories"
        "setup_environment_file:Setup environment file"
        "validate_directory_structure:Validate directory structure"
    )
    
    log_section "Directory Structure Setup"
    log_info "$context" "Setting up directory structure for: $RUUVI_USER"
    
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
        log_error "$context" "Directory setup failed at: ${failed_steps[*]}"
        return 1
    fi
    
    log_success "$context" "Directory structure setup completed successfully"
    log_info "$context" "Project located at: $PROJECT_DIR"
    return 0
}

# Export main function
export -f setup_directories

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_directories
fi