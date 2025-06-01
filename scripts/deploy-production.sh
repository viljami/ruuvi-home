#!/bin/bash
set -euo pipefail

# Production Deployment Script for Ruuvi Home on Raspberry Pi
# This script ensures mqtt-simulator is never deployed to production

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.production.yaml"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_PRODUCTION_TEMPLATE="$PROJECT_ROOT/.env.production"

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

# Function to check Docker and Docker Compose
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or user lacks permissions"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        exit 1
    fi

    log_success "Docker environment check passed"
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

    log_success "Production configuration verified (mqtt-simulator excluded)"
}

# Function to stop any existing services
stop_existing_services() {
    log_info "Stopping existing services..."

    # Try both development and production compose files
    if [[ -f "$PROJECT_ROOT/docker-compose.yaml" ]]; then
        docker-compose -f "$PROJECT_ROOT/docker-compose.yaml" down --remove-orphans || true
    fi

    if [[ -f "$COMPOSE_FILE" ]]; then
        docker-compose -f "$COMPOSE_FILE" down --remove-orphans || true
    fi

    log_success "Existing services stopped"
}

# Function to pull latest images
pull_images() {
    log_info "Pulling latest Docker images..."
    cd "$PROJECT_ROOT"
    docker-compose -f "$COMPOSE_FILE" pull
    log_success "Images pulled successfully"
}

# Function to build and start services
deploy_services() {
    log_info "Building and starting production services..."
    cd "$PROJECT_ROOT"

    # Build images
    docker-compose -f "$COMPOSE_FILE" build

    # Start services
    docker-compose -f "$COMPOSE_FILE" up -d

    log_success "Production services started"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    cd "$PROJECT_ROOT"

    # Wait a moment for services to start
    sleep 10

    # Check service status
    docker-compose -f "$COMPOSE_FILE" ps

    # Verify no mqtt-simulator is running
    if docker ps --format "table {{.Names}}" | grep -q "mqtt-simulator"; then
        log_error "CRITICAL: mqtt-simulator container is running in production!"
        log_error "Stopping deployment..."
        docker-compose -f "$COMPOSE_FILE" down
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
    docker-compose -f "$COMPOSE_FILE" ps

    echo ""
    log_info "=== Service URLs ==="
    echo "Frontend: http://localhost:3000"
    echo "API: http://localhost:8080"
    echo "API Health: http://localhost:8080/health"

    echo ""
    log_info "=== Logs ==="
    echo "View logs with: docker-compose -f $COMPOSE_FILE logs -f [service_name]"
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
