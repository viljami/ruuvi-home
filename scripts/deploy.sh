#!/bin/bash
# Ruuvi Home Deployment Script
# This script deploys the Ruuvi Home application to a Raspberry Pi

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
PI_USER="pi"
PI_HOST=""
SSH_PORT="22"
REMOTE_DIR="/home/pi/ruuvi-home"
REPO_URL="https://github.com/yourusername/ruuvi-home.git"
BRANCH="main"

usage() {
    echo -e "${GREEN}Ruuvi Home Deployment Script${NC}"
    echo ""
    echo "Usage: $0 [options] hostname"
    echo ""
    echo "Options:"
    echo "  -u, --user USER       SSH username (default: pi)"
    echo "  -p, --port PORT       SSH port (default: 22)"
    echo "  -d, --dir DIRECTORY   Target directory on Raspberry Pi (default: /home/pi/ruuvi-home)"
    echo "  -r, --repo URL        Git repository URL (default: ${REPO_URL})"
    echo "  -b, --branch BRANCH   Git branch to deploy (default: main)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 raspberrypi.local"
    echo "  $0 -u pi -p 2222 192.168.1.100"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            PI_USER="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -d|--dir)
            REMOTE_DIR="$2"
            shift 2
            ;;
        -r|--repo)
            REPO_URL="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$PI_HOST" ]; then
                PI_HOST="$1"
                shift
            else
                echo -e "${RED}Error: Unknown parameter $1${NC}"
                usage
            fi
            ;;
    esac
done

# Check if hostname is provided
if [ -z "$PI_HOST" ]; then
    echo -e "${RED}Error: No hostname provided${NC}"
    usage
fi

SSH_CMD="ssh -p $SSH_PORT $PI_USER@$PI_HOST"
SCP_CMD="scp -P $SSH_PORT"

echo -e "${GREEN}Deploying Ruuvi Home to $PI_HOST...${NC}"

# Check SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! $SSH_CMD "echo Connection successful"; then
    echo -e "${RED}Error: Cannot connect to $PI_USER@$PI_HOST${NC}"
    exit 1
fi

# Install required dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
$SSH_CMD "sudo apt-get update && \
          sudo apt-get install -y git docker.io docker-compose mosquitto influxdb && \
          sudo systemctl enable docker && \
          sudo systemctl start docker && \
          sudo usermod -aG docker $PI_USER"

# Clone or update repository
echo -e "${YELLOW}Cloning/updating repository...${NC}"
$SSH_CMD "if [ -d \"$REMOTE_DIR\" ]; then \
            cd \"$REMOTE_DIR\" && git pull; \
          else \
            git clone --branch \"$BRANCH\" \"$REPO_URL\" \"$REMOTE_DIR\"; \
          fi"

# Copy configuration files
echo -e "${YELLOW}Copying configuration files...${NC}"
$SSH_CMD "mkdir -p $REMOTE_DIR/docker/mosquitto/config"
$SSH_CMD "mkdir -p $REMOTE_DIR/docker/influxdb/config"
$SCP_CMD docker/mosquitto/config/mosquitto.conf $PI_USER@$PI_HOST:$REMOTE_DIR/docker/mosquitto/config/

# Set up systemd service
echo -e "${YELLOW}Setting up systemd service...${NC}"
cat > ruuvi-home.service << EOF
[Unit]
Description=Ruuvi Home Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$PI_USER
WorkingDirectory=$REMOTE_DIR
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

$SCP_CMD ruuvi-home.service $PI_USER@$PI_HOST:/tmp/
$SSH_CMD "sudo mv /tmp/ruuvi-home.service /etc/systemd/system/ && \
          sudo systemctl daemon-reload && \
          sudo systemctl enable ruuvi-home.service"

# Start the service
echo -e "${YELLOW}Starting Ruuvi Home service...${NC}"
$SSH_CMD "sudo systemctl restart ruuvi-home.service"

# Check service status
echo -e "${YELLOW}Checking service status...${NC}"
$SSH_CMD "sudo systemctl status ruuvi-home.service"

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "You can access the Ruuvi Home UI at: ${YELLOW}http://$PI_HOST:3000${NC}"

# Cleanup
rm -f ruuvi-home.service