#!/bin/bash

# Docker Build Troubleshooting Script
# Helps resolve common Docker build issues including network connectivity problems

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check Docker daemon
check_docker() {
    print_status "Checking Docker daemon..."
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running or not accessible"
        print_status "Please start Docker and try again"
        exit 1
    fi
    print_success "Docker daemon is running"
}

# Function to check network connectivity
check_network() {
    print_status "Checking network connectivity..."

    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_error "No internet connectivity"
        exit 1
    fi

    if ! nslookup deb.debian.org >/dev/null 2>&1; then
        print_warning "DNS resolution issues detected"
        print_status "You may experience package download issues"
    fi

    print_success "Network connectivity OK"
}

# Function to clean Docker cache
clean_docker_cache() {
    print_status "Cleaning Docker build cache..."
    docker builder prune -f
    docker system prune -f
    print_success "Docker cache cleaned"
}

# Function to build with retry logic
build_with_retry() {
    local service="$1"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        print_status "Build attempt $attempt/$max_attempts for $service"

        if docker buildx build \
            --file "docker/${service}.Dockerfile" \
            --tag "ruuvi-${service}:latest" \
            --platform linux/amd64 \
            --progress=plain \
            .; then
            print_success "Build successful for $service"
            return 0
        else
            print_warning "Build attempt $attempt failed for $service"
            if [ $attempt -lt $max_attempts ]; then
                print_status "Waiting 10 seconds before retry..."
                sleep 10

                # Clean cache between attempts
                print_status "Cleaning cache before retry..."
                docker builder prune -f
            fi
        fi

        attempt=$((attempt + 1))
    done

    print_error "All build attempts failed for $service"
    return 1
}

# Function to build with offline cache
build_offline() {
    local service="$1"

    print_status "Attempting offline build for $service using cached layers..."

    docker buildx build \
        --file "docker/${service}.Dockerfile" \
        --tag "ruuvi-${service}:latest" \
        --platform linux/amd64 \
        --cache-from type=local,src=/tmp/docker-cache \
        --cache-to type=local,dest=/tmp/docker-cache \
        --progress=plain \
        .
}

# Function to diagnose build issues
diagnose_build() {
    print_status "Running build diagnostics..."

    echo "Docker version:"
    docker version
    echo ""

    echo "Docker info:"
    docker info
    echo ""

    echo "Available disk space:"
    df -h
    echo ""

    echo "Docker images:"
    docker images
    echo ""

    echo "Docker containers:"
    docker ps -a
    echo ""
}

# Function to show usage
show_usage() {
    echo "Docker Build Troubleshooting Script"
    echo ""
    echo "Usage: $0 [command] [service]"
    echo ""
    echo "Commands:"
    echo "  check           - Run all diagnostic checks"
    echo "  clean           - Clean Docker cache and images"
    echo "  build SERVICE   - Build specific service with retry logic"
    echo "  build-all       - Build all services"
    echo "  offline SERVICE - Build with offline cache"
    echo "  diagnose        - Show detailed system information"
    echo ""
    echo "Services:"
    echo "  mqtt-reader     - MQTT reader service"
    echo "  api-server      - API server service"
    echo "  mqtt-simulator  - MQTT simulator service"
    echo ""
    echo "Examples:"
    echo "  $0 check"
    echo "  $0 build mqtt-reader"
    echo "  $0 build-all"
    echo "  $0 clean"
}

# Main script logic
main() {
    cd "$PROJECT_ROOT"

    case "${1:-}" in
        "check")
            check_docker
            check_network
            print_success "All checks passed"
            ;;
        "clean")
            check_docker
            clean_docker_cache
            print_status "Removing unused images..."
            docker image prune -f
            print_success "Docker cleanup complete"
            ;;
        "build")
            if [ -z "${2:-}" ]; then
                print_error "Service name required"
                show_usage
                exit 1
            fi

            check_docker
            check_network
            build_with_retry "$2"
            ;;
        "build-all")
            check_docker
            check_network

            services=("mqtt-reader" "api-server" "mqtt-simulator")
            failed_services=()

            for service in "${services[@]}"; do
                if ! build_with_retry "$service"; then
                    failed_services+=("$service")
                fi
            done

            if [ ${#failed_services[@]} -eq 0 ]; then
                print_success "All services built successfully"
            else
                print_error "Failed to build: ${failed_services[*]}"
                exit 1
            fi
            ;;
        "offline")
            if [ -z "${2:-}" ]; then
                print_error "Service name required"
                show_usage
                exit 1
            fi

            check_docker
            build_offline "$2"
            ;;
        "diagnose")
            diagnose_build
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        "")
            print_error "No command specified"
            show_usage
            exit 1
            ;;
        *)
            print_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
