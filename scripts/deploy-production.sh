#!/bin/bash
set -euo pipefail

# Production Deployment Script for Ruuvi Home on Raspberry Pi
# This script ensures mqtt-simulator is never deployed to production

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.production.yaml"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_PRODUCTION_TEMPLATE="$PROJECT_ROOT/.env.production"

# Source docker compatibility library
source "$SCRIPT_DIR/setup-pi/lib/docker-compat.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if running on Raspberry Pi
check_raspberry_pi() {
    if [[ -f /proc/device-tree/model ]] && grep -q "Raspberry Pi" /proc/device-tree/model; then
        log_info "Confirmed running on Raspberry Pi"
        return 0
    else
        log_warn "Not running on Raspberry Pi - proceeding anyway"
        return 0
    fi
}

# Function to validate environment file
validate_environment() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found: $ENV_FILE"
        if [[ -f "$ENV_PRODUCTION_TEMPLATE" ]]; then
            log_info "Copying production template to .env"
            cp "$ENV_PRODUCTION_TEMPLATE" "$ENV_FILE"
            log_warn "Please edit $ENV_FILE with your production values before continuing"
            exit 1
        else
            log_error "No environment template found"
            exit 1
        fi
    fi

    # Check for placeholder values that need to be changed
    local placeholder_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ CHANGE_THIS_TO_ ]]; then
            log_error "Found placeholder value in .env: $line"
            ((placeholder_count++))
        fi
    done < "$ENV_FILE"

    if [[ $placeholder_count -gt 0 ]]; then
        log_error "Found $placeholder_count placeholder values in .env file"
        log_error "Please update all CHANGE_THIS_TO_* values before deploying"
        exit 1
    fi

    log_success "Environment file validation passed"
}

# Function to check Docker and Docker Compose using compatibility library
check_docker() {
    log_info "Checking Docker environment using compatibility detection"

    # Initialize docker compatibility detection
    if ! init_docker_compat; then
        log_error "Docker environment validation failed"
        log_info "Docker environment summary:"
        get_docker_summary
        exit 1
    fi

    log_success "Docker environment check passed"
    log_info "Using Docker Compose command: ${COMPOSE_COMMAND}"
}

# Function to verify production compose file exists and doesn't contain mqtt-simulator
verify_production_config() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Production compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    # Check that mqtt-simulator is NOT in the production config
    if grep -q "mqtt-simulator" "$COMPOSE_FILE"; then
        log_error "CRITICAL: mqtt-simulator found in production configuration!"
        log_error "This service should only be used in development"
        exit 1
    fi

    # Validate compose file syntax using docker-compat library
    log_info "Validating Docker Compose file syntax..."
    if ! test_docker_compose_file "$COMPOSE_FILE"; then
        log_error "Docker Compose file validation failed"
        exit 1
    fi

    log_success "Production configuration verified (mqtt-simulator excluded, syntax valid)"
}

# Function to stop any existing services
stop_existing_services() {
    log_info "Stopping existing services..."

    # Try both development and production compose files
    if [[ -f "$PROJECT_ROOT/docker-compose.yaml" ]]; then
        compose_exec "down" "$PROJECT_ROOT/docker-compose.yaml" "--remove-orphans" || true
    fi

    if [[ -f "$COMPOSE_FILE" ]]; then
        compose_exec "down" "$COMPOSE_FILE" "--remove-orphans" || true
    fi

    log_success "Existing services stopped"
}

# Function to pull latest images
pull_images() {
    log_info "Pulling latest Docker images..."
    cd "$PROJECT_ROOT"
    if ! compose_exec "pull" "$COMPOSE_FILE"; then
        log_error "Failed to pull Docker images"
        exit 1
    fi
    log_success "Images pulled successfully"
}

# Function to build and start services
deploy_services() {
    log_info "Building and starting production services..."
    cd "$PROJECT_ROOT"

    # Build images
    if ! compose_exec "build" "$COMPOSE_FILE"; then
        log_error "Failed to build Docker images"
        exit 1
    fi

    # Start services
    if ! compose_exec "up" "$COMPOSE_FILE" "-d"; then
        log_error "Failed to start services"
        exit 1
    fi

    log_success "Production services started"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    cd "$PROJECT_ROOT"

    # Wait a moment for services to start
    sleep 10

    # Check service status
    compose_exec "ps" "$COMPOSE_FILE" || true

    # Verify no mqtt-simulator is running
    if docker ps --format "table {{.Names}}" | grep -q "mqtt-simulator"; then
        log_error "CRITICAL: mqtt-simulator container is running in production!"
        log_error "Stopping deployment..."
        compose_exec "down" "$COMPOSE_FILE"
        exit 1
    fi

    # Check if API is responding
    log_info "Waiting for API server to be ready..."
    local retry_count=0
    local max_retries=30

    while [[ $retry_count -lt $max_retries ]]; do
        if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
            log_success "API server is responding"
            break
        fi

        ((retry_count++))
        if [[ $retry_count -eq $max_retries ]]; then
            log_error "API server did not start within expected time"
            exit 1
        fi

        sleep 2
    done

    log_success "Deployment verification completed"
}

# Function to show deployment status
show_status() {
    log_info "=== Deployment Status ==="
    cd "$PROJECT_ROOT"
    compose_exec "ps" "$COMPOSE_FILE" || true

    echo ""
    log_info "=== Service URLs ==="
    echo "Frontend: http://localhost:${FRONTEND_PORT:-3000}"
    echo "API: http://localhost:${API_PORT:-8080}"
    echo "API Health: http://localhost:${API_PORT:-8080}/health"

    echo ""
    log_info "=== Port Configuration ==="
    echo "MQTT Broker: ${MOSQUITTO_PORT:-1883}"
    echo "MQTT WebSocket: ${MOSQUITTO_WS_PORT:-9001}"
    echo "API Server: ${API_PORT:-8080}"
    echo "Frontend: ${FRONTEND_PORT:-3000}"
    echo "Webhook (systemd): ${WEBHOOK_PORT:-9000}"
    echo "Database: Internal only (not exposed for security)"

    echo ""
    log_info "=== Network Access ==="
    echo "External access required for:"
    echo "- Frontend: Port ${FRONTEND_PORT:-3000} (Web UI)"
    echo "- API: Port ${API_PORT:-8080} (REST API)"
    echo "- MQTT: Port ${MOSQUITTO_PORT:-1883} (Ruuvi Gateway)"
    echo "- Webhook: Port ${WEBHOOK_PORT:-9000} (GitHub webhooks)"

    echo ""
    log_info "=== Logs ==="
    echo "View logs with: $COMPOSE_COMMAND -f $COMPOSE_FILE logs -f [service_name]"
    echo "Available services: mosquitto, timescaledb, mqtt-reader, api-server, frontend"
}

# Main deployment function
main() {
    log_info "Starting Ruuvi Home production deployment for Raspberry Pi"

    # Pre-deployment checks
    check_raspberry_pi
    check_docker
    validate_environment
    verify_production_config

    # Deployment steps
    stop_existing_services
    pull_images
    deploy_services
    verify_deployment

    # Post-deployment
    show_status

    log_success "🎉 Production deployment completed successfully!"
    log_info "Your Ruuvi Home system is now running in production mode"
    log_warn "Remember: Real Ruuvi sensors must be configured to send data to this MQTT broker"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
