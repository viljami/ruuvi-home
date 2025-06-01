#!/bin/bash
# Ruuvi Home Development Script
# This script helps with local development environment setup and management

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_COMPOSE="${PROJECT_ROOT}/docker-compose.yaml"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed.${NC}"
    echo "Please install Docker from https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is installed
if ! docker compose version &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not available.${NC}"
    echo "Please install Docker Compose from https://docs.docker.com/compose/install/"
    exit 1
fi

# Create necessary directories
mkdir -p "${PROJECT_ROOT}/docker/mosquitto/config"
mkdir -p "${PROJECT_ROOT}/docker/mosquitto/data"
mkdir -p "${PROJECT_ROOT}/docker/mosquitto/log"

usage() {
    echo -e "${GREEN}Ruuvi Home Development Script${NC}"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start       Start the development environment"
    echo "  stop        Stop the development environment"
    echo "  restart     Restart the development environment"
    echo "  logs        Show logs from all services"
    echo "  clean       Remove all containers and volumes"
    echo "  help        Show this help message"
    echo ""
}

start_dev_environment() {
    echo -e "${GREEN}Starting Ruuvi Home development environment...${NC}"
    docker compose -f "${DOCKER_COMPOSE}" up -d
    echo -e "${GREEN}Development environment is running!${NC}"
    echo -e "API Server:        ${YELLOW}http://localhost:8080${NC}"
    echo -e "Frontend:          ${YELLOW}http://localhost:3000${NC}"
}

stop_dev_environment() {
    echo -e "${YELLOW}Stopping Ruuvi Home development environment...${NC}"
    docker compose -f "${DOCKER_COMPOSE}" down
    echo -e "${GREEN}Development environment stopped.${NC}"
}

show_logs() {
    echo -e "${GREEN}Showing logs from all services...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit logs${NC}"
    docker compose -f "${DOCKER_COMPOSE}" logs -f
}

clean_environment() {
    echo -e "${RED}WARNING: This will remove all containers and volumes.${NC}"
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cleaning up development environment...${NC}"
        docker compose -f "${DOCKER_COMPOSE}" down -v
        echo -e "${GREEN}Development environment cleaned.${NC}"
    fi
}

case "$1" in
    start)
        start_dev_environment
        ;;
    stop)
        stop_dev_environment
        ;;
    restart)
        stop_dev_environment
        start_dev_environment
        ;;
    logs)
        show_logs
        ;;
    clean)
        clean_environment
        ;;
    help|*)
        usage
        ;;
esac
