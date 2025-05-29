# Ruuvi Home Deployment Guide

This document provides comprehensive instructions for deploying Ruuvi Home to a Raspberry Pi using automated GitHub Actions CI/CD pipeline.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Raspberry Pi Setup](#raspberry-pi-setup)
- [GitHub Actions Configuration](#github-actions-configuration)
- [Environment Variables](#environment-variables)
- [Security Configuration](#security-configuration)
- [Deployment Process](#deployment-process)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Hardware Requirements
- Raspberry Pi 4 (4GB RAM recommended, 2GB minimum)
- MicroSD card (32GB minimum, Class 10)
- Stable internet connection
- Ruuvi Gateway (for real sensor data) or use simulator for testing

### Software Requirements
- Raspberry Pi OS Lite (64-bit recommended)
- Git
- SSH access enabled

## Raspberry Pi Setup

### 1. Automated Setup (Recommended)

Run the automated setup script to configure your Raspberry Pi with all necessary components:

```bash
curl -fsSL https://raw.githubusercontent.com/viljami/ruuvi-home/main/scripts/setup-pi.sh | sudo bash
```

This script will:
- Update the system packages
- Install Docker and Docker Compose
- Configure firewall (UFW) with appropriate rules
- Set up fail2ban for SSH protection
- Create project directories with proper permissions
- Configure log rotation
- Enable automatic security updates
- Set up systemd service for Ruuvi Home

### 2. Manual Setup (Alternative)

If you prefer manual setup, follow these steps:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker pi

# Install Docker Compose
sudo apt install docker-compose-plugin

# Create project directory
mkdir -p /home/pi/ruuvi-home
cd /home/pi/ruuvi-home

# Clone repository
git clone https://github.com/viljami/ruuvi-home.git .
```

### 3. Post-Setup Configuration

After running the setup script:

1. **Reboot the system:**
   ```bash
   sudo reboot
   ```

2. **Clone the repository:**
   ```bash
   cd /home/pi/ruuvi-home
   git clone https://github.com/viljami/ruuvi-home.git .
   ```

3. **Configure environment variables:**
   ```bash
   cp .env.example .env
   nano .env  # Edit with your actual values
   ```

## GitHub Actions Configuration

### 1. Required GitHub Secrets

Configure the following secrets in your GitHub repository settings:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `PI_HOST` | Raspberry Pi IP address or hostname | `192.168.1.100` |
| `PI_USER` | Username for SSH access | `pi` |
| `PI_SSH_KEY` | Private SSH key for Pi access | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `INFLUXDB_TOKEN` | InfluxDB authentication token | `your-secret-token-here` |
| `GATEWAY_MAC` | Your Ruuvi Gateway MAC address | `AA:BB:CC:DD:EE:FF` |
| `SLACK_WEBHOOK_URL` | (Optional) Slack webhook for notifications | `https://hooks.slack.com/...` |

### 2. SSH Key Setup

1. **Generate SSH key pair on your development machine:**
   ```bash
   ssh-keygen -t ed25519 -C "github-actions@ruuvi-home" -f ~/.ssh/ruuvi_pi
   ```

2. **Copy public key to Raspberry Pi:**
   ```bash
   ssh-copy-id -i ~/.ssh/ruuvi_pi.pub pi@YOUR_PI_IP
   ```

3. **Add private key to GitHub Secrets:**
   - Copy the content of `~/.ssh/ruuvi_pi`
   - Add it as `PI_SSH_KEY` secret in GitHub

### 3. Workflow Configuration

The GitHub Actions workflow (`.github/workflows/ci-cd.yml`) automatically:
- Runs tests on every push/PR
- Builds multi-architecture Docker images
- Deploys to Raspberry Pi on main branch pushes
- Performs security scans
- Sends deployment notifications

## Environment Variables

### Production Environment Variables

Create a `.env` file on your Raspberry Pi with the following variables:

```bash
# MQTT Configuration
MQTT_HOST=localhost
MQTT_PORT=1883
MQTT_TOPIC=ruuvi/gateway/data
MQTT_USERNAME=your_mqtt_user
MQTT_PASSWORD=your_mqtt_password

# InfluxDB Configuration
INFLUXDB_URL=http://localhost:8086
INFLUXDB_TOKEN=your-production-token
INFLUXDB_ORG=ruuvi_home
INFLUXDB_BUCKET=ruuvi_metrics

# API Configuration
API_PORT=8080

# Ruuvi Gateway
GATEWAY_MAC=AA:BB:CC:DD:EE:FF

# Logging
RUST_LOG=warn
LOG_FILEPATH=/var/log/ruuvi-home/mqtt-reader.log

# Frontend
REACT_APP_API_URL=http://YOUR_PI_IP:8080
NODE_ENV=production
```

### Environment Variable Security

- **Never commit `.env` files to version control**
- Use GitHub Secrets for sensitive values in CI/CD
- Rotate tokens regularly
- Use least-privilege access principles

## Security Configuration

### 1. Firewall Configuration

The setup script configures UFW with the following rules:
- SSH (port 22): Allowed
- MQTT (port 1883): Allowed
- API (port 8080): Allowed
- InfluxDB (port 8086): Allowed
- Frontend (port 3000): Allowed for development

### 2. Additional Security Measures

- **Fail2ban**: Automatically configured for SSH protection
- **Automatic updates**: Security updates are automatically installed
- **Docker security**: Container logging limits configured
- **User permissions**: Services run with minimal required permissions

### 3. MQTT Security

For production deployment, configure MQTT authentication:

1. **Create MQTT users:**
   ```bash
   sudo mosquitto_passwd -c /etc/mosquitto/passwd ruuvi_user
   ```

2. **Update Mosquitto configuration:**
   ```bash
   sudo nano /etc/mosquitto/conf.d/ruuvi-home.conf
   ```
   
   Add:
   ```
   listener 1883
   allow_anonymous false
   password_file /etc/mosquitto/passwd
   ```

3. **Restart Mosquitto:**
   ```bash
   sudo systemctl restart mosquitto
   ```

## Deployment Process

### 1. Automatic Deployment

Deployment happens automatically when code is pushed to the main branch:

1. **Trigger deployment:**
   ```bash
   git push origin main
   ```

2. **Monitor deployment:**
   - Check GitHub Actions tab for build status
   - Monitor Slack notifications (if configured)
   - SSH to Pi and check service status

### 2. Manual Deployment

For manual deployment or troubleshooting:

```bash
# SSH to Raspberry Pi
ssh pi@YOUR_PI_IP

# Navigate to project directory
cd /home/pi/ruuvi-home

# Pull latest changes
git pull origin main

# Update and restart services
docker-compose -f docker-compose.yml -f docker-compose.prod.yml pull
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Verify deployment
curl http://localhost:8080/health
```

### 3. Rollback Process

If deployment fails, rollback to previous version:

```bash
# SSH to Raspberry Pi
ssh pi@YOUR_PI_IP
cd /home/pi/ruuvi-home

# Rollback to previous commit
git reset --hard HEAD~1

# Restart services
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

## Monitoring and Maintenance

### 1. Service Monitoring

**Check service status:**
```bash
# Using systemd
sudo systemctl status ruuvi-home

# Using Docker Compose
docker-compose ps

# Check logs
docker-compose logs -f
```

**Health checks:**
```bash
# API health
curl http://localhost:8080/health

# InfluxDB health
curl http://localhost:8086/health

# Check MQTT connectivity
mosquitto_sub -h localhost -t ruuvi/gateway/data -C 1
```

### 2. Log Management

Logs are automatically rotated and stored in:
- Application logs: `/var/log/ruuvi-home/`
- Docker logs: Managed by Docker with size limits
- System logs: `/var/log/syslog`

**View logs:**
```bash
# Application logs
tail -f /var/log/ruuvi-home/mqtt-reader.log

# Docker service logs
docker-compose logs -f mqtt-reader
docker-compose logs -f api-server
```

### 3. Data Backup

**Backup InfluxDB data:**
```bash
# Create backup
docker-compose exec influxdb influx backup /var/lib/influxdb2/backup/$(date +%Y%m%d)

# Copy backup to external location
rsync -av /home/pi/ruuvi-home/data/influxdb/backup/ user@backup-server:/backups/ruuvi-home/
```

### 4. System Maintenance

**Update system packages:**
```bash
sudo apt update && sudo apt upgrade -y
```

**Update Docker images:**
```bash
cd /home/pi/ruuvi-home
docker-compose pull
docker-compose up -d
```

**Clean up old Docker resources:**
```bash
docker system prune -f
docker image prune -f
```

## Troubleshooting

### Common Issues

#### 1. Services Won't Start

**Check Docker status:**
```bash
sudo systemctl status docker
docker-compose ps
```

**Check logs:**
```bash
docker-compose logs
journalctl -u ruuvi-home
```

**Common solutions:**
- Restart Docker: `sudo systemctl restart docker`
- Check disk space: `df -h`
- Verify environment variables: `cat .env`

#### 2. MQTT Connection Issues

**Test MQTT connectivity:**
```bash
# Test local MQTT broker
mosquitto_pub -h localhost -t test -m "hello"
mosquitto_sub -h localhost -t test -C 1

# Check if broker is running
sudo systemctl status mosquitto
```

**Check firewall:**
```bash
sudo ufw status
```

#### 3. InfluxDB Issues

**Check InfluxDB status:**
```bash
docker-compose exec influxdb influx ping
curl http://localhost:8086/health
```

**Reset InfluxDB (caution - data loss):**
```bash
docker-compose down
sudo rm -rf /home/pi/ruuvi-home/data/influxdb/*
docker-compose up -d
```

#### 4. Memory/Performance Issues

**Check resource usage:**
```bash
htop
docker stats
```

**Optimize for Raspberry Pi:**
- Reduce Docker memory limits in `docker-compose.prod.yml`
- Set `RUST_LOG=error` to reduce logging overhead
- Consider using swap file for additional memory

#### 5. Network Issues

**Check network connectivity:**
```bash
ping google.com
curl http://localhost:8080/health
netstat -tuln | grep -E '1883|8080|8086'
```

**Reset network configuration:**
```bash
sudo systemctl restart networking
sudo systemctl restart docker
```

### Getting Help

1. **Check logs first**: Always start with application and system logs
2. **GitHub Issues**: Report bugs or request features
3. **Documentation**: Refer to project README and this deployment guide
4. **Community**: Join discussions in GitHub Discussions

### Performance Optimization

For optimal performance on Raspberry Pi:

1. **Use SSD instead of SD card** for better I/O performance
2. **Enable GPU memory split**: Add `gpu_mem=16` to `/boot/config.txt`
3. **Disable unnecessary services**: Use `sudo systemctl disable <service>`
4. **Monitor temperatures**: Use `vcgencmd measure_temp`
5. **Use appropriate logging levels**: Set `RUST_LOG=warn` in production

## Support

For additional support:
- GitHub Issues: [https://github.com/viljami/ruuvi-home/issues](https://github.com/viljami/ruuvi-home/issues)
- Documentation: [https://github.com/viljami/ruuvi-home/docs](https://github.com/viljami/ruuvi-home/docs)
- Ruuvi Community: [https://f.ruuvi.com](https://f.ruuvi.com)