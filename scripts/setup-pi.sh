#!/bin/bash
# Ruuvi Home Raspberry Pi Setup - Main Entry Point
# This script provides a clean entry point to the modular setup system

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$SCRIPT_DIR/setup-pi"
MAIN_SETUP="$SETUP_DIR/setup-pi.sh"

# Print header
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}     Ruuvi Home Setup - Entry       ${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Check if setup directory exists
if [ ! -d "$SETUP_DIR" ]; then
    echo -e "${RED}Error: Setup directory not found: $SETUP_DIR${NC}"
    echo "Please ensure you're running this from the correct location"
    exit 1
fi

# Check if main setup script exists
if [ ! -f "$MAIN_SETUP" ]; then
    echo -e "${RED}Error: Main setup script not found: $MAIN_SETUP${NC}"
    exit 1
fi

# Make setup script executable
chmod +x "$MAIN_SETUP"

# Display setup information
echo -e "${YELLOW}Setup Information:${NC}"
echo "User: ${SUDO_USER:-root}"
echo "Setup directory: $SETUP_DIR"
echo "Target directory: /home/${SUDO_USER:-pi}/ruuvi-home"
echo ""

# Confirm before proceeding
read -p "Continue with Ruuvi Home setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled"
    exit 0
fi

echo ""
echo -e "${GREEN}Starting Ruuvi Home setup...${NC}"
echo ""

# Execute main setup script
exec "$MAIN_SETUP" "$@"