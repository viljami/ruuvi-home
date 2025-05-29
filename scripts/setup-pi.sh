#!/bin/bash
# Ruuvi Home Raspberry Pi Setup Script
# This script prepares a Raspberry Pi for the Ruuvi Home application

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Ruuvi Home - Raspberry Pi Setup   ${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (use sudo)${NC}"
  exit 1
fi

# Configuration variables
RUUVI_USER="pi"
PROJECT_DIR="/home/${RUUVI_USER}/ruuvi-home"
DATA_DIR="${PROJECT_DIR}/data"
LOG_DIR="/var/log/ruuvi-home"

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt-get update && apt-get upgrade -y

# Install essential packages
echo -e "${YELLOW}Installing essential packages...${NC}"
apt-get install -y \
  curl \
  wget \
  git \
  htop \
  vim \
  fish \
  ufw \
  fail2ban \
  logrotate \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common \
  rsync \
  jq

# Install Docker
echo -e "${YELLOW}Installing Docker...${NC}"
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
  usermod -aG docker ${RUUVI_USER}
  systemctl enable docker
  systemctl start docker
  
  # Configure Docker daemon for production
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
  systemctl restart docker
  echo -e "${GREEN}Docker installed and configured successfully${NC}"
else
  echo -e "${GREEN}Docker is already installed${NC}"
fi

# Install Docker Compose
echo -e "${YELLOW}Installing Docker Compose...${NC}"
if ! command -v docker-compose &> /dev/null; then
  apt-get install -y docker-compose-plugin
  echo -e "${GREEN}Docker Compose installed successfully${NC}"
else
  echo -e "${GREEN}Docker Compose is already installed${NC}"
fi

# Install Mosquitto MQTT broker
echo -e "${YELLOW}Installing Mosquitto MQTT broker...${NC}"
apt-get install -y mosquitto mosquitto-clients
systemctl enable mosquitto
systemctl start mosquitto

# Configure Mosquitto for anonymous access (for development)
cat > /etc/mosquitto/conf.d/ruuvi-home.conf << EOF
# Ruuvi Home MQTT Configuration
listener 1883
allow_anonymous true
EOF

# Restart Mosquitto to apply configuration
systemctl restart mosquitto
echo -e "${GREEN}Mosquitto MQTT broker configured${NC}"

# Set up Fish shell as default for pi user
echo -e "${YELLOW}Setting up Fish shell...${NC}"
chsh -s /usr/bin/fish pi

# Set up project directories with proper permissions
echo -e "${YELLOW}Setting up project directories...${NC}"
mkdir -p ${PROJECT_DIR}
mkdir -p ${DATA_DIR}/influxdb
mkdir -p ${DATA_DIR}/mosquitto/data
mkdir -p ${DATA_DIR}/mosquitto/log
mkdir -p ${DATA_DIR}/mosquitto/config
mkdir -p ${LOG_DIR}
mkdir -p ${PROJECT_DIR}/backups
mkdir -p ${PROJECT_DIR}/scripts

# Set proper ownership and permissions
chown -R ${RUUVI_USER}:${RUUVI_USER} ${PROJECT_DIR}
chown -R ${RUUVI_USER}:${RUUVI_USER} ${LOG_DIR}
chmod 755 ${PROJECT_DIR}
chmod 750 ${DATA_DIR}
chmod 755 ${LOG_DIR}

# Create environment file from template
curl -fsSL https://raw.githubusercontent.com/viljami/ruuvi-home/main/.env.example -o ${PROJECT_DIR}/.env.example
chown ${RUUVI_USER}:${RUUVI_USER} ${PROJECT_DIR}/.env.example
chmod 644 ${PROJECT_DIR}/.env.example

echo -e "${GREEN}Project directories set up with secure permissions${NC}"

# Network optimization for IoT devices
echo -e "${YELLOW}Optimizing network settings...${NC}"
cat >> /etc/sysctl.conf << EOF

# Network optimizations for IoT
net.core.rmem_max = 1048576
net.core.wmem_max = 1048576
net.ipv4.tcp_rmem = 4096 87380 1048576
net.ipv4.tcp_wmem = 4096 87380 1048576
EOF
sysctl -p

# Setup automatic updates for security
echo -e "${YELLOW}Setting up automatic security updates...${NC}"
apt-get install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Configure firewall
echo -e "${YELLOW}Configuring UFW firewall...${NC}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 1883/tcp  # MQTT
ufw allow 8080/tcp  # API
ufw allow 8086/tcp  # InfluxDB
ufw allow 3000/tcp  # Frontend (development)
ufw --force enable

# Configure fail2ban for SSH protection
echo -e "${YELLOW}Configuring fail2ban...${NC}"
systemctl enable fail2ban
systemctl start fail2ban

# Set timezone to match your location (change as needed)
echo -e "${YELLOW}Setting timezone...${NC}"
timedatectl set-timezone Europe/Helsinki

# Install InfluxDB (optional, can use Docker instead)
echo -e "${YELLOW}Would you like to install InfluxDB locally? (y/n)${NC}"
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Installing InfluxDB...${NC}"
  curl -s https://repos.influxdata.com/influxdb.key | gpg --dearmor > /etc/apt/trusted.gpg.d/influxdb.gpg
  echo "deb https://repos.influxdata.com/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/influxdb.list
  apt-get update
  apt-get install -y influxdb2
  systemctl enable influxdb
  systemctl start influxdb
  echo -e "${GREEN}InfluxDB installed successfully${NC}"
fi

# Final system update
apt-get update && apt-get upgrade -y

# Enable hardware features if this is a Raspberry Pi
if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
  echo -e "${YELLOW}Enabling Raspberry Pi specific features...${NC}"
  
  # Enable I2C
  if ! grep -q "^dtparam=i2c_arm=on" /boot/config.txt; then
    echo "dtparam=i2c_arm=on" >> /boot/config.txt
  fi
  
  # Disable Bluetooth if not needed (saves power)
  if ! grep -q "^dtoverlay=disable-bt" /boot/config.txt; then
    echo "dtoverlay=disable-bt" >> /boot/config.txt
  fi
  
  # Apply changes
  echo -e "${GREEN}Raspberry Pi configuration updated${NC}"
fi

# Set up log rotation for Ruuvi Home
echo -e "${YELLOW}Setting up log rotation...${NC}"
cat > /etc/logrotate.d/ruuvi-home << EOF
${LOG_DIR}/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    su ${RUUVI_USER} ${RUUVI_USER}
}
EOF

# Create systemd service template
echo -e "${YELLOW}Creating systemd service templates...${NC}"
cat > /etc/systemd/system/ruuvi-home.service << EOF
[Unit]
Description=Ruuvi Home Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=${PROJECT_DIR}
User=${RUUVI_USER}
Group=${RUUVI_USER}
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable the service (but don't start it yet)
systemctl daemon-reload
systemctl enable ruuvi-home.service

# Create deployment helper script
cat > ${PROJECT_DIR}/scripts/deploy.sh << 'EOF'
#!/bin/bash
# Ruuvi Home deployment helper script

set -e

PROJECT_DIR="/home/pi/ruuvi-home"
cd ${PROJECT_DIR}

echo "Pulling latest changes..."
git pull origin main

echo "Building and starting services..."
docker-compose down
docker-compose pull
docker-compose up -d

echo "Deployment completed successfully!"
EOF

chmod +x ${PROJECT_DIR}/scripts/deploy.sh
chown ${RUUVI_USER}:${RUUVI_USER} ${PROJECT_DIR}/scripts/deploy.sh

# Final message
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Raspberry Pi setup completed!      ${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Reboot the system: ${YELLOW}sudo reboot${NC}"
echo -e "2. Log in as ${RUUVI_USER} user"
echo -e "3. Clone the Ruuvi Home repository to ${PROJECT_DIR}"
echo -e "4. Copy .env.example to .env and configure your settings"
echo -e "5. Start the application: ${YELLOW}sudo systemctl start ruuvi-home${NC}"
echo ""
echo -e "${YELLOW}Security features enabled:${NC}"
echo -e "- UFW firewall with restrictive rules"
echo -e "- Fail2ban for SSH protection"
echo -e "- Automatic security updates"
echo -e "- Docker logging limits"
echo -e "- Log rotation for application logs"
echo ""
echo -e "${YELLOW}Data persistence configured at:${NC}"
echo -e "- InfluxDB: ${DATA_DIR}/influxdb"
echo -e "- Mosquitto: ${DATA_DIR}/mosquitto"
echo -e "- Logs: ${LOG_DIR}"
echo ""