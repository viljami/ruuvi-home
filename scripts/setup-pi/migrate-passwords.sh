#!/bin/bash

# Ruuvi Home Password Migration Script
# Fixes URL-unsafe characters in database passwords
# Version: 1.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
BACKUP_FILE="$PROJECT_ROOT/.env.backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if password contains URL-unsafe characters
has_url_unsafe_chars() {
    local password="$1"
    if [[ "$password" =~ [+/=] ]]; then
        return 0  # Has unsafe characters
    else
        return 1  # Safe
    fi
}

# URL encode password
url_encode_password() {
    local password="$1"
    printf '%s' "$password" | sed 's/+/%2B/g; s/\//%2F/g; s/=/%3D/g'
}

# Generate new URL-safe password
generate_url_safe_password() {
    openssl rand -hex 32
}

# Update password in .env file
update_env_password() {
    local var_name="$1"
    local new_value="$2"

    if grep -q "^${var_name}=" "$ENV_FILE"; then
        sed -i "s|^${var_name}=.*|${var_name}=${new_value}|" "$ENV_FILE"
    else
        echo "${var_name}=${new_value}" >> "$ENV_FILE"
    fi
}

# Update database URL in .env file
update_database_url() {
    local db_user="$1"
    local db_password="$2"
    local db_host="$3"
    local db_port="$4"
    local db_name="$5"
    local url_var="$6"

    local new_url="postgresql://${db_user}:${db_password}@${db_host}:${db_port}/${db_name}"
    update_env_password "$url_var" "$new_url"
}

# Check current environment
check_current_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        exit 1
    fi

    # Source the .env file
    set -a
    source "$ENV_FILE"
    set +a

    log_info "Checking current password configuration..."

    local needs_migration=false

    # Check POSTGRES_PASSWORD
    if [[ -n "${POSTGRES_PASSWORD:-}" ]] && has_url_unsafe_chars "$POSTGRES_PASSWORD"; then
        log_warning "POSTGRES_PASSWORD contains URL-unsafe characters: + / ="
        needs_migration=true
    fi

    # Check AUTH_DB_PASSWORD
    if [[ -n "${AUTH_DB_PASSWORD:-}" ]] && has_url_unsafe_chars "$AUTH_DB_PASSWORD"; then
        log_warning "AUTH_DB_PASSWORD contains URL-unsafe characters: + / ="
        needs_migration=true
    fi

    # Check MQTT_PASSWORD
    if [[ -n "${MQTT_PASSWORD:-}" ]] && has_url_unsafe_chars "$MQTT_PASSWORD"; then
        log_warning "MQTT_PASSWORD contains URL-unsafe characters: + / ="
        needs_migration=true
    fi

    if [[ "$needs_migration" == "true" ]]; then
        return 0  # Needs migration
    else
        log_success "All passwords are already URL-safe!"
        return 1  # No migration needed
    fi
}

# Backup current .env file
backup_env() {
    log_info "Creating backup of .env file..."
    cp "$ENV_FILE" "$BACKUP_FILE"
    log_success "Backup created: $BACKUP_FILE"
}

# Migrate passwords
migrate_passwords() {
    local migration_mode="$1"  # "encode" or "regenerate"

    log_info "Starting password migration (mode: $migration_mode)..."

    # Source current .env
    set -a
    source "$ENV_FILE"
    set +a

    # Migrate POSTGRES_PASSWORD
    if [[ -n "${POSTGRES_PASSWORD:-}" ]] && has_url_unsafe_chars "$POSTGRES_PASSWORD"; then
        local new_postgres_password
        if [[ "$migration_mode" == "regenerate" ]]; then
            new_postgres_password=$(generate_url_safe_password)
            log_info "Generated new POSTGRES_PASSWORD"
        else
            new_postgres_password=$(url_encode_password "$POSTGRES_PASSWORD")
            log_info "URL-encoded existing POSTGRES_PASSWORD"
        fi

        update_env_password "POSTGRES_PASSWORD" "$new_postgres_password"
        update_database_url "${POSTGRES_USER:-ruuvi}" "$new_postgres_password" "timescaledb" "5432" "${POSTGRES_DB:-ruuvi_home}" "DATABASE_URL"
    fi

    # Migrate AUTH_DB_PASSWORD
    if [[ -n "${AUTH_DB_PASSWORD:-}" ]] && has_url_unsafe_chars "$AUTH_DB_PASSWORD"; then
        local new_auth_password
        if [[ "$migration_mode" == "regenerate" ]]; then
            new_auth_password=$(generate_url_safe_password)
            log_info "Generated new AUTH_DB_PASSWORD"
        else
            new_auth_password=$(url_encode_password "$AUTH_DB_PASSWORD")
            log_info "URL-encoded existing AUTH_DB_PASSWORD"
        fi

        update_env_password "AUTH_DB_PASSWORD" "$new_auth_password"
        update_database_url "auth_user" "$new_auth_password" "auth-db" "5432" "auth" "AUTH_DATABASE_URL"
    fi

    # Migrate MQTT_PASSWORD
    if [[ -n "${MQTT_PASSWORD:-}" ]] && has_url_unsafe_chars "$MQTT_PASSWORD"; then
        local new_mqtt_password
        if [[ "$migration_mode" == "regenerate" ]]; then
            new_mqtt_password=$(generate_url_safe_password)
            log_info "Generated new MQTT_PASSWORD"
        else
            new_mqtt_password=$(url_encode_password "$MQTT_PASSWORD")
            log_info "URL-encoded existing MQTT_PASSWORD"
        fi

        update_env_password "MQTT_PASSWORD" "$new_mqtt_password"
    fi

    log_success "Password migration completed!"
}

# Restart services
restart_services() {
    log_info "Restarting Ruuvi Home services..."

    cd "$PROJECT_ROOT"

    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose down
        docker-compose up -d
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker compose down
        docker compose up -d
    else
        log_error "Neither docker-compose nor docker compose found!"
        exit 1
    fi

    log_success "Services restarted!"
}

# Test connectivity
test_connectivity() {
    log_info "Testing API connectivity..."

    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -s http://localhost:8080/health >/dev/null 2>&1; then
            log_success "API server is responding!"
            return 0
        fi

        log_info "Waiting for API server... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    log_error "API server is not responding after $max_attempts attempts"
    log_error "Check logs with: docker compose logs api-server"
    return 1
}

# Main function
main() {
    echo "=========================================="
    echo "  Ruuvi Home Password Migration Script"
    echo "=========================================="
    echo

    log_info "Checking if migration is needed..."

    if ! check_current_env; then
        echo
        log_success "No migration needed. Exiting."
        exit 0
    fi

    echo
    log_warning "Password migration is required!"
    echo
    echo "Choose migration strategy:"
    echo "1) URL-encode existing passwords (recommended - preserves current passwords)"
    echo "2) Generate new URL-safe passwords (requires database reset)"
    echo "3) Cancel migration"
    echo

    while true; do
        read -p "Enter your choice (1-3): " choice
        case $choice in
            1)
                migration_mode="encode"
                break
                ;;
            2)
                migration_mode="regenerate"
                echo
                log_warning "WARNING: This will generate new passwords and require database recreation!"
                read -p "Are you sure? All data will be lost! (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    break
                else
                    log_info "Migration cancelled."
                    exit 0
                fi
                ;;
            3)
                log_info "Migration cancelled by user."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done

    echo
    backup_env

    if [[ "$migration_mode" == "regenerate" ]]; then
        log_info "Removing database volumes for clean start..."
        cd "$PROJECT_ROOT"
        docker compose down -v
    fi

    migrate_passwords "$migration_mode"
    restart_services

    echo
    log_info "Waiting for services to start..."
    sleep 10

    if test_connectivity; then
        echo
        log_success "Migration completed successfully!"
        log_info "Your original .env file was backed up to: $BACKUP_FILE"
        echo
        log_info "You can now access your Ruuvi Home dashboard."
    else
        echo
        log_error "Migration completed but services are not responding properly."
        log_error "Check the logs and consider restoring from backup if needed:"
        log_error "  cp $BACKUP_FILE $ENV_FILE"
    fi
}

# Run main function
main "$@"
