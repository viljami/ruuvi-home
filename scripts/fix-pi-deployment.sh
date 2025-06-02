#!/bin/bash

# Ruuvi Home Pi Deployment Fix Script
# Addresses ARM64/Pi-specific issues with TimescaleDB and service dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_CMD="docker compose"

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

print_header() {
    echo "=========================================="
    echo "Ruuvi Home Pi Deployment Fix"
    echo "=========================================="
    echo
}

check_environment() {
    log_info "Checking Pi environment..."

    # Check if we're on ARM64
    if [ "$(uname -m)" != "aarch64" ]; then
        log_warning "Not running on ARM64 architecture. This script is optimized for Raspberry Pi."
    fi

    # Check Docker availability
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    # Check Docker Compose availability
    if ! docker compose version &> /dev/null; then
        if command -v docker-compose &> /dev/null; then
            COMPOSE_CMD="docker-compose"
            log_info "Using docker-compose command"
        else
            log_error "Docker Compose is not available"
            exit 1
        fi
    fi

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_DIR/docker-compose.yaml" ]; then
        log_error "Not in Ruuvi Home project directory. Please run from project root or scripts/"
        exit 1
    fi

    log_success "Environment checks passed"
}

diagnose_current_state() {
    log_info "Diagnosing current deployment state..."

    cd "$PROJECT_DIR"

    # Check which containers are running
    echo "Current container status:"
    $COMPOSE_CMD ps || true
    echo

    # Check TimescaleDB logs specifically
    log_info "Checking TimescaleDB logs for errors..."
    if $COMPOSE_CMD ps | grep -q "ruuvi-timescaledb"; then
        echo "Last 20 lines of TimescaleDB logs:"
        $COMPOSE_CMD logs --tail=20 timescaledb || true
        echo
    else
        log_warning "TimescaleDB container is not running"
    fi

    # Check for cgroup issues
    if [ -d "/sys/fs/cgroup" ]; then
        log_info "Checking cgroup configuration..."
        if [ ! -f "/sys/fs/cgroup/memory.max" ]; then
            log_warning "cgroup v2 memory.max not found - this causes TimescaleDB tuning to fail"
        fi
    fi
}

create_pi_optimized_config() {
    log_info "Creating Pi-optimized TimescaleDB configuration..."

    # Ensure directory exists
    mkdir -p "$PROJECT_DIR/docker/timescaledb"

    # Create the ARM64-compatible tuning script if it doesn't exist
    if [ ! -f "$PROJECT_DIR/docker/timescaledb/001_timescaledb_tune.sh" ]; then
        cat > "$PROJECT_DIR/docker/timescaledb/001_timescaledb_tune.sh" << 'EOF'
#!/bin/bash
set -e

# TimescaleDB tuning script for ARM64/Raspberry Pi environments
# This script replaces the default timescaledb-tune which fails on ARM64 due to cgroup issues

echo "=== ARM64-compatible TimescaleDB tuning ==="

# Get the PostgreSQL configuration file path
PG_CONF="${PGDATA}/postgresql.conf"

# Only proceed if the config file exists
if [ ! -f "$PG_CONF" ]; then
    echo "PostgreSQL config file not found at $PG_CONF, skipping tuning"
    exit 0
fi

echo "Using postgresql.conf at: $PG_CONF"

# Create backup
BACKUP_FILE="/tmp/timescaledb_tune.backup$(date +%Y%m%d%H%M)"
echo "Writing backup to: $BACKUP_FILE"
cp "$PG_CONF" "$BACKUP_FILE"

# ARM64/Pi-optimized settings for TimescaleDB
cat >> "$PG_CONF" << 'PGEOF'

# TimescaleDB ARM64/Raspberry Pi optimized settings
# Applied by custom tuning script to avoid cgroup issues

# Memory settings (conservative for Pi)
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 4MB
maintenance_work_mem = 64MB

# Checkpoint settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100

# Connection settings
max_connections = 100

# TimescaleDB specific settings
timescaledb.max_background_workers = 2
max_worker_processes = 4
max_parallel_workers_per_gather = 1
max_parallel_workers = 2

# Performance optimizations for ARM64
random_page_cost = 1.1
effective_io_concurrency = 200

# Logging (reduce for Pi storage)
log_statement = 'none'
log_min_duration_statement = 1000

# Autovacuum tuning for TimescaleDB
autovacuum_max_workers = 2
autovacuum_naptime = 30s

PGEOF

echo "TimescaleDB ARM64 tuning completed successfully"
echo "Configuration applied to: $PG_CONF"
EOF

        chmod +x "$PROJECT_DIR/docker/timescaledb/001_timescaledb_tune.sh"
        log_success "Created ARM64-compatible TimescaleDB tuning script"
    else
        log_info "TimescaleDB tuning script already exists"
    fi
}

fix_docker_compose() {
    log_info "Ensuring Docker Compose files include Pi fixes..."

    cd "$PROJECT_DIR"

    # Check if production compose already has the tuning script volume
    if ! grep -q "001_timescaledb_tune.sh" docker-compose.production.yaml; then
        log_warning "Production Docker Compose needs updating with Pi fixes"
        log_info "Please update docker-compose.production.yaml to include the tuning script volume"
    fi

    # For development, check and update if needed
    if ! grep -q "001_timescaledb_tune.sh" docker-compose.yaml; then
        log_warning "Development Docker Compose needs updating with Pi fixes"
        log_info "Please update docker-compose.yaml to include the tuning script volume"
    fi
}

stop_and_cleanup() {
    log_info "Stopping existing containers and cleaning up..."

    cd "$PROJECT_DIR"

    # Stop all containers
    $COMPOSE_CMD down || true

    # Remove any problematic TimescaleDB data if needed
    if [ "$1" = "--reset-db" ]; then
        log_warning "Resetting database volumes..."
        $COMPOSE_CMD down -v || true
        docker volume rm ruuvi-home_timescaledb-data 2>/dev/null || true
    fi

    # Clean up any orphaned containers
    docker system prune -f || true

    log_success "Cleanup completed"
}

start_services_sequentially() {
    log_info "Starting services in the correct order..."

    cd "$PROJECT_DIR"

    # Determine which compose file to use
    COMPOSE_FILE="docker-compose.yaml"
    if [ -f ".env" ] && grep -q "production" .env; then
        COMPOSE_FILE="docker-compose.production.yaml"
        log_info "Using production configuration"
    fi

    # Start TimescaleDB first and wait for health check
    log_info "Starting TimescaleDB..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d timescaledb

    # Wait for TimescaleDB to be healthy
    log_info "Waiting for TimescaleDB to become healthy..."
    for i in {1..60}; do
        if $COMPOSE_CMD -f "$COMPOSE_FILE" ps timescaledb | grep -q "healthy"; then
            log_success "TimescaleDB is healthy"
            break
        fi
        if [ $i -eq 60 ]; then
            log_error "TimescaleDB failed to become healthy within 5 minutes"
            $COMPOSE_CMD logs timescaledb
            exit 1
        fi
        sleep 5
        echo -n "."
    done
    echo

    # Start MQTT broker
    log_info "Starting MQTT broker..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d mosquitto

    # Start backend services
    log_info "Starting backend services..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d mqtt-reader api-server

    # Start frontend if available
    if $COMPOSE_CMD -f "$COMPOSE_FILE" config --services | grep -q frontend; then
        log_info "Starting frontend..."
        $COMPOSE_CMD -f "$COMPOSE_FILE" up -d frontend
    fi

    log_success "All services started"
}

verify_deployment() {
    log_info "Verifying deployment..."

    cd "$PROJECT_DIR"

    # Check container status
    echo "Final container status:"
    $COMPOSE_CMD ps
    echo

    # Test database connectivity
    log_info "Testing database connectivity..."
    if $COMPOSE_CMD exec -T timescaledb pg_isready -U ruuvi -d ruuvi_home; then
        log_success "Database is accepting connections"
    else
        log_error "Database connectivity test failed"
        return 1
    fi

    # Test API health endpoint
    log_info "Testing API server..."
    sleep 5
    if curl -f http://localhost:8080/health &>/dev/null; then
        log_success "API server is responding"
    else
        log_warning "API server health check failed - this might be normal during startup"
    fi

    # Show recent logs for any errors
    log_info "Recent service logs:"
    $COMPOSE_CMD logs --tail=10 --since=1m
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --reset-db    Reset database volumes (removes all data)"
    echo "  --diagnose    Only run diagnostics, don't fix"
    echo "  --help        Show this help message"
    echo
    echo "This script fixes common Pi deployment issues including:"
    echo "  - TimescaleDB tuning failures on ARM64"
    echo "  - Service startup dependencies"
    echo "  - Database connectivity issues"
}

main() {
    print_header

    # Parse arguments
    RESET_DB=false
    DIAGNOSE_ONLY=false

    for arg in "$@"; do
        case $arg in
            --reset-db)
                RESET_DB=true
                shift
                ;;
            --diagnose)
                DIAGNOSE_ONLY=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                show_usage
                exit 1
                ;;
        esac
    done

    # Run checks and diagnostics
    check_environment
    diagnose_current_state

    if [ "$DIAGNOSE_ONLY" = true ]; then
        log_info "Diagnostics complete. Use without --diagnose to apply fixes."
        exit 0
    fi

    # Apply fixes
    create_pi_optimized_config
    fix_docker_compose

    # Stop and restart services
    if [ "$RESET_DB" = true ]; then
        stop_and_cleanup --reset-db
    else
        stop_and_cleanup
    fi

    start_services_sequentially
    verify_deployment

    log_success "Pi deployment fix completed!"
    echo
    echo "Next steps:"
    echo "1. Monitor logs: docker compose logs -f"
    echo "2. Check health: docker compose ps"
    echo "3. Access frontend: http://localhost:3000"
    echo "4. API endpoint: http://localhost:8080"
}

# Run main function with all arguments
main "$@"
