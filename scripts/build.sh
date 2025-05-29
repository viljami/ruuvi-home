#!/bin/bash
# Simplified Docker Build Script for Ruuvi Home
# Works with standard Docker without BuildKit requirements

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REGISTRY="ruuvi-home"

# Default values
PARALLEL_BUILDS=true
USE_CACHE=true
BUILD_SERVICES=""
CLEANUP=false
VERBOSE=false
DRY_RUN=false

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [SERVICES...]

Simple Docker build script for Ruuvi Home (no BuildKit required).

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -p, --parallel          Enable parallel builds (default: true)
    -s, --sequential        Disable parallel builds
    -c, --cache             Use build cache (default: true)
    -n, --no-cache          Disable build cache
    --cleanup               Clean up build artifacts
    --dry-run               Show what would be done without executing

Services:
    mqtt-reader            Build MQTT reader service
    api-server             Build API server service
    frontend               Build frontend service
    mqtt-simulator         Build MQTT simulator service
    all                    Build all services (default)

Examples:
    $0                                    # Build all services
    $0 --parallel --cache frontend       # Fast build of frontend only
    $0 --no-cache api-server             # Clean build of API server
    $0 --cleanup                         # Clean up build artifacts
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -p|--parallel)
            PARALLEL_BUILDS=true
            shift
            ;;
        -s|--sequential)
            PARALLEL_BUILDS=false
            shift
            ;;
        -c|--cache)
            USE_CACHE=true
            shift
            ;;
        -n|--no-cache)
            USE_CACHE=false
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        mqtt-reader|api-server|frontend|mqtt-simulator|all)
            if [ -z "$BUILD_SERVICES" ]; then
                BUILD_SERVICES="$1"
            else
                BUILD_SERVICES="$BUILD_SERVICES $1"
            fi
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Default to building all services
if [ -z "$BUILD_SERVICES" ]; then
    BUILD_SERVICES="all"
fi

# Setup environment
setup_environment() {
    log_section "Setting Up Build Environment"
    
    # Check Docker availability
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Disable BuildKit to ensure compatibility with standard Docker
    export DOCKER_BUILDKIT=0
    
    log_success "Build environment ready"
}

# Analyze build context
analyze_build_context() {
    log_section "Analyzing Build Context"
    
    cd "$PROJECT_ROOT"
    
    # Check for .dockerignore files
    local missing_dockerignore=()
    if [ ! -f ".dockerignore" ]; then
        missing_dockerignore+=("root")
    fi
    if [ ! -f "frontend/.dockerignore" ]; then
        missing_dockerignore+=("frontend")
    fi
    if [ ! -f "backend/.dockerignore" ]; then
        missing_dockerignore+=("backend")
    fi
    
    if [ ${#missing_dockerignore[@]} -gt 0 ]; then
        log_warning "Missing .dockerignore files: ${missing_dockerignore[*]}"
        log_info "This may result in slower builds due to large build context"
    else
        log_success "All .dockerignore files present"
    fi
    
    # Check context sizes
    local total_size=$(du -sh . 2>/dev/null | cut -f1)
    log_info "Total project size: $total_size"
}

# Build service
build_service() {
    local service=$1
    local dockerfile=$2
    local context=$3
    local extra_args=${4:-""}
    
    log_info "Building $service..."
    
    local build_cmd="docker build"
    local tag="${REGISTRY}/${service}:latest"
    
    # Add cache arguments
    if [ "$USE_CACHE" = false ]; then
        build_cmd="$build_cmd --no-cache"
    fi
    
    # Add verbose output if requested
    if [ "$VERBOSE" = true ]; then
        build_cmd="$build_cmd --progress=plain"
    fi
    
    # Add extra build arguments
    if [ -n "$extra_args" ]; then
        build_cmd="$build_cmd $extra_args"
    fi
    
    # Complete build command
    build_cmd="$build_cmd -f $dockerfile -t $tag $context"
    
    if [ "$VERBOSE" = true ]; then
        echo "Build command: $build_cmd"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: $build_cmd"
        return 0
    fi
    
    # Execute build
    if eval "$build_cmd"; then
        log_success "Built $service successfully"
        return 0
    else
        log_error "Failed to build $service"
        return 1
    fi
}

# Build services
build_services() {
    log_section "Building Services"
    
    cd "$PROJECT_ROOT"
    
    local services_to_build=()
    
    # Determine which services to build
    for service in $BUILD_SERVICES; do
        case $service in
            all)
                services_to_build=("mqtt-reader" "api-server" "frontend" "mqtt-simulator")
                break
                ;;
            mqtt-reader|api-server|frontend|mqtt-simulator)
                services_to_build+=("$service")
                ;;
            *)
                log_warning "Unknown service: $service"
                ;;
        esac
    done
    
    log_info "Building services: ${services_to_build[*]}"
    
    # Build services
    local build_pids=()
    local build_results=()
    local build_logs=()
    
    for service in "${services_to_build[@]}"; do
        case $service in
            mqtt-reader)
                if [ "$PARALLEL_BUILDS" = true ]; then
                    (
                        build_service "mqtt-reader" "./docker/mqtt-reader.Dockerfile" "." \
                            "--build-arg CARGO_INCREMENTAL=0 --build-arg RUST_BACKTRACE=1"
                        echo $? > "/tmp/build_result_mqtt_reader_$$"
                    ) > "/tmp/build_log_mqtt_reader_$$" 2>&1 &
                    build_pids+=($!)
                    build_logs+=("/tmp/build_log_mqtt_reader_$$")
                else
                    build_service "mqtt-reader" "./docker/mqtt-reader.Dockerfile" "." \
                        "--build-arg CARGO_INCREMENTAL=0 --build-arg RUST_BACKTRACE=1"
                    build_results+=($?)
                fi
                ;;
            api-server)
                if [ "$PARALLEL_BUILDS" = true ]; then
                    (
                        build_service "api-server" "./docker/api-server.Dockerfile" "." \
                            "--build-arg CARGO_INCREMENTAL=0 --build-arg RUST_BACKTRACE=1"
                        echo $? > "/tmp/build_result_api_server_$$"
                    ) > "/tmp/build_log_api_server_$$" 2>&1 &
                    build_pids+=($!)
                    build_logs+=("/tmp/build_log_api_server_$$")
                else
                    build_service "api-server" "./docker/api-server.Dockerfile" "." \
                        "--build-arg CARGO_INCREMENTAL=0 --build-arg RUST_BACKTRACE=1"
                    build_results+=($?)
                fi
                ;;
            frontend)
                if [ "$PARALLEL_BUILDS" = true ]; then
                    (
                        cd frontend
                        build_service "frontend" "../docker/frontend.Dockerfile" "." \
                            "--build-arg NODE_ENV=production --build-arg GENERATE_SOURCEMAP=false"
                        echo $? > "/tmp/build_result_frontend_$$"
                    ) > "/tmp/build_log_frontend_$$" 2>&1 &
                    build_pids+=($!)
                    build_logs+=("/tmp/build_log_frontend_$$")
                else
                    (cd frontend && build_service "frontend" "../docker/frontend.Dockerfile" "." \
                        "--build-arg NODE_ENV=production --build-arg GENERATE_SOURCEMAP=false")
                    build_results+=($?)
                fi
                ;;
            mqtt-simulator)
                if [ "$PARALLEL_BUILDS" = true ]; then
                    (
                        build_service "mqtt-simulator" "Dockerfile" "./docker/mqtt-simulator"
                        echo $? > "/tmp/build_result_mqtt_simulator_$$"
                    ) > "/tmp/build_log_mqtt_simulator_$$" 2>&1 &
                    build_pids+=($!)
                    build_logs+=("/tmp/build_log_mqtt_simulator_$$")
                else
                    build_service "mqtt-simulator" "Dockerfile" "./docker/mqtt-simulator"
                    build_results+=($?)
                fi
                ;;
        esac
    done
    
    # Wait for parallel builds to complete
    if [ "$PARALLEL_BUILDS" = true ] && [ ${#build_pids[@]} -gt 0 ]; then
        log_info "Waiting for ${#build_pids[@]} parallel builds to complete..."
        
        for i in "${!build_pids[@]}"; do
            local pid=${build_pids[$i]}
            local log_file=${build_logs[$i]}
            
            wait "$pid"
            
            # Show build output if verbose or if build failed
            if [ "$VERBOSE" = true ] && [ -f "$log_file" ]; then
                echo "=== Build output for PID $pid ==="
                cat "$log_file"
                echo "=== End build output ==="
            fi
            
            # Get result from temp file
            local service_name=$(basename "$log_file" | sed 's/.*_\([^_]*\)_[0-9]*/\1/')
            local result_file="/tmp/build_result_${service_name}_$$"
            if [ -f "$result_file" ]; then
                local result=$(cat "$result_file")
                build_results+=($result)
                rm -f "$result_file"
            else
                build_results+=(1)
            fi
            
            # Clean up log file
            rm -f "$log_file"
        done
    fi
    
    # Check results
    local failed_builds=0
    for result in "${build_results[@]}"; do
        if [ "$result" -ne 0 ]; then
            ((failed_builds++))
        fi
    done
    
    if [ "$failed_builds" -eq 0 ]; then
        log_success "All builds completed successfully"
        return 0
    else
        log_error "$failed_builds build(s) failed"
        return 1
    fi
}

# Cleanup build artifacts
cleanup_builds() {
    log_section "Cleaning Up Build Artifacts"
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would clean up build artifacts"
        return 0
    fi
    
    # Clean Docker build cache
    docker builder prune -f 2>/dev/null || true
    
    # Clean up dangling images
    docker image prune -f
    
    # Clean up Rust build artifacts
    if [ -d "$PROJECT_ROOT/backend/target" ]; then
        log_info "Cleaning Rust build artifacts..."
        rm -rf "$PROJECT_ROOT/backend/target"
    fi
    
    # Clean up Node.js build artifacts
    if [ -d "$PROJECT_ROOT/frontend/node_modules" ]; then
        log_info "Cleaning Node.js node_modules..."
        rm -rf "$PROJECT_ROOT/frontend/node_modules"
    fi
    
    if [ -d "$PROJECT_ROOT/frontend/build" ]; then
        log_info "Cleaning React build artifacts..."
        rm -rf "$PROJECT_ROOT/frontend/build"
    fi
    
    # Clean up temporary files
    rm -f /tmp/build_result_*_$$
    rm -f /tmp/build_log_*_$$
    
    log_success "Build artifacts cleaned up"
}

# Show build statistics
show_build_stats() {
    log_section "Build Statistics"
    
    # Docker images sizes
    log_info "Docker image sizes:"
    for service in mqtt-reader api-server frontend mqtt-simulator; do
        if docker image inspect "${REGISTRY}/${service}:latest" > /dev/null 2>&1; then
            local size=$(docker image inspect "${REGISTRY}/${service}:latest" --format '{{.Size}}' | numfmt --to=iec 2>/dev/null || echo "unknown")
            echo "  $service: $size"
        else
            echo "  $service: not built"
        fi
    done
    
    # Docker system usage
    echo ""
    docker system df 2>/dev/null || true
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    if [ "$CLEANUP" = true ]; then
        cleanup_builds
        exit 0
    fi
    
    setup_environment
    analyze_build_context
    
    if build_services; then
        show_build_stats
        log_success "Build completed successfully!"
        echo ""
        log_info "You can now run the services with:"
        echo "  docker-compose up -d"
        echo ""
        log_info "Or test individual services:"
        echo "  docker run --rm ${REGISTRY}/mqtt-reader:latest"
        echo "  docker run --rm -p 8080:8080 ${REGISTRY}/api-server:latest"
        echo "  docker run --rm -p 3000:80 ${REGISTRY}/frontend:latest"
    else
        log_error "Build failed"
        exit 1
    fi
}

# Run main function
main "$@"