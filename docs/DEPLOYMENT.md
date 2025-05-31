# Ruuvi Home Deployment Guide

This document provides comprehensive instructions for deploying Ruuvi Home to a Raspberry Pi using automated GitHub Actions CI/CD pipeline with TimescaleDB and containerized services.

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

- Raspberry Pi 5 (4GB RAM recommended, 2GB minimum)
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
- Configure Nginx as reverse proxy with rate limiting
- Set up firewall (UFW) with security-first rules (only HTTP/HTTPS exposed publicly)
- Configure fail2ban for SSH and web protection
- Create project directories with proper permissions
- Set up systemd services for the application and webhook handler
- Configure log rotation and automated backups
- Enable automatic security updates
- Create GitHub Actions deployment webhook handler

### 2. Post-Setup Configuration

After running the setup script:

1. **Configure environment variables:**

   ```bash
   cd /home/pi/ruuvi-home
   cp .env.example .env
   nano .env  # Edit with your secure passwords and secrets
   ```

2. **Generate secure passwords:**

   ```bash
   # Generate secure passwords
   openssl rand -base64 32  # For POSTGRES_PASSWORD
   openssl rand -base64 32  # For AUTH_DB_PASSWORD
   openssl rand -base64 64  # For JWT_SECRET
   openssl rand -base64 32  # For WEBHOOK_SECRET
   ```

3. **Reboot the system:**

   ```bash
   sudo reboot
   ```

4. **Start services:**
   ```bash
   sudo systemctl start ruuvi-home
   sudo systemctl start ruuvi-webhook
   ```

## GitHub Actions Configuration

### 1. Required GitHub Secrets

Configure the following secrets in your GitHub repository settings (Settings → Secrets and variables → Actions):

| Secret Name      | Description                   | Example                          |
| ---------------- | ----------------------------- | -------------------------------- |
| `WEBHOOK_URL`    | Raspberry Pi webhook endpoint | `http://YOUR_PI_IP:9000/webhook` |
| `WEBHOOK_SECRET` | Webhook authentication secret | `your-secure-webhook-secret`     |

**Important Security Notes:**

- All secrets are encrypted by GitHub
- Never use GitHub Variables for sensitive data - they are not encrypted
- The webhook endpoint should only be accessible from GitHub's IP ranges

### 2. Repository Configuration

1. **Enable GitHub Container Registry:**

   - The workflow automatically uses `ghcr.io` (GitHub Container Registry)
   - No additional configuration needed for public repositories

2. \*\*Set up repository webhook (optional for
 advanced notifications):**
   - Go to Settings → Webhooks
   - Add webhook URL: `http://YOUR_PI_IP:9000/webhook`
   - Content type: `application/json`
   - Secret: Same as `WEBHOOK_SECRET`
   - Events: Choose "Releases" and "Push"

### 3. Workflow Features

The GitHub Actions workflow (`.github/workflows/deploy.yml`) automatically:
- Runs comprehensive tests including database integration tests
- Builds multi-architecture Docker images (AMD64 and ARM64)
- Pushes images to GitHub Container Registry
- Triggers deployment to Raspberry Pi via webhook
- Performs security vulnerability scans
- Supports both main branch deployments and tagged releases

## Environment Variables

### Production Environment Variables

Update your `.env` file on the Raspberry Pi with secure values:

```bash
# Database Configuration - USE SECURE PASSWORDS
POSTGRES_PASSWORD=your_secure_postgres_password_here
AUTH_DB_PASSWORD=your_secure_auth_db_password_here

# JWT Configuration - GENERATE SECURE SECRET
JWT_SECRET=your_jwt_secret_key_at_least_32_characters_long

# GitHub Webhook Configuration
WEBHOOK_SECRET=your_secure_webhook_secret_here
WEBHOOK_PORT=9000

# Application Configuration
RUST_LOG=info
API_PORT=8080
FRONTEND_PORT=3000

# External URLs (update with your actual domain)
PUBLIC_API_URL=https://your-domain.com/api
PUBLIC_FRONTEND_URL=https://your-domain.com

# MQTT Configuration (internal Docker network)
MQTT_BROKER_URL=mqtt://mosquitto:1883

# Security Configuration
CORS_ALLOW_ORIGIN=https://your-domain.com
SESSION_TIMEOUT=3600

# Production optimizations
NODE_ENV=production
RUST_BACKTRACE=0
TIMESCALEDB_TELEMETRY=off
```

### Container Internal Configuration

The Docker Compose setup uses internal networking for security:
- **TimescaleDB**: Only accessible from localhost:5432
- **Auth Database**: Only accessible from localhost:5433
- **MQTT Broker**: Only accessible from local network and localhost:1883
- **API**: Only accessible from localhost:8080
- **Frontend**: Only accessible from localhost:3000

Nginx reverse proxy handles public access with rate limiting and security headers.

## Security Configuration

### 1. Network Security

The setup implements defense-in-depth security:
- **Public Access**: Only HTTP (80) and HTTPS (443) via Nginx
- **Local Network**: MQTT accessible only from private IP ranges
- **Localhost Only**: All databases and internal services
- **Firewall**: UFW configured with restrictive rules
- **Rate Limiting**: API endpoints protected against abuse

### 2. Container Security

- **Non-root users**: All containers run as unprivileged users
- **Network isolation**: Internal Docker network for service communication
- **Resource limits**: Memory and CPU limits configured
- **Security scanning**: Trivy vulnerability scanner in CI/CD
- **Minimal base images**: Debian slim and Alpine Linux for reduced attack surface

### 3. Application Security

- **JWT Authentication**: Secure token-based authentication
- **Password Hashing**: Secure password storage in auth database
- **SQL Injection Protection**: Parameterized queries with sqlx
- **CORS Configuration**: Restrictive cross-origin resource sharing
- **Security Headers**: Comprehensive HTTP security headers via Nginx

### 4. MQTT Security

MQTT broker is configured for local network access only:
- **Network Binding**: localhost and private networks only
- **Connection Limits**: Maximum connections and message limits
- **No Anonymous Access**: Authentication required for production
- **Message Limits**: Rate limiting on MQTT messages

## Deployment Process

### 1. Automatic Deployment

Deployment happens automatically via GitHub Actions:

1. **Push to main branch or create a release:**
   ```bash
   git push origin main
   # OR
   git tag v1.0.0 && git push origin v1.0.0
   ```

2. **Monitor deployment:**
   - Check GitHub Actions tab for build status
   - SSH to Pi and check service status: `sudo systemctl status ruuvi-home`
   - Verify health: `curl http://localhost/health`

3. **Deployment process:**
   - Tests run with TimescaleDB integration tests
   - Multi-architecture container images built
   - Images pushed to GitHub Container Registry
   - Webhook triggered on Raspberry Pi
   - Pi pulls new images and restarts services
   - Automatic database backup before deployment

### 2. Manual Deployment

For manual deployment or troubleshooting:

```bash
# SSH to Raspberry Pi
ssh pi@YOUR_PI_IP

# Navigate to project directory
cd /home/pi/ruuvi-home

# Manual deployment with specific tag
./scripts/deploy.sh v1.0.0

# Or update to latest
./scripts/deploy.sh latest

# Verify deployment
./scripts/health-check.sh
```

### 3. Rollback Process

Rollback using Docker image tags:

```bash
# SSH to Raspberry Pi
cd /home/pi/ruuvi-home

# List available backups
ls backups/

# Restore database backup (if needed)
docker-compose exec timescaledb psql -U ruuvi -d ruuvi_home < backups/backup-YYYYMMDD-HHMMSS.sql

# Rollback to previous image version
export IMAGE_TAG=previous-version
docker-compose pull
docker-compose up -d
```

## Monitoring and Maintenance

### 1. Service Monitoring

**Check service status:**
```bash
# Main application
sudo systemctl status ruuvi-home

# Webhook handler
sudo systemctl status ruuvi-webhook

# Individual containers
docker-compose ps

# Container health
docker-compose exec timescaledb pg_isready -U ruuvi
curl http://localhost/api/health
```

**Health checks:**
```bash
# Run comprehensive health check
/home/pi/ruuvi-home/scripts/health-check.sh

# API health
curl http://localhost/api/health

# Database health
docker-compose exec timescaledb pg_isready -U ruuvi -d ruuvi_home

# MQTT connectivity
mosquitto_sub -h localhost -t ruuvi/gateway/data -C 1
```

### 2. Log Management

Logs are automatically rotated and stored in:
- Application logs: `/var/log/ruuvi-home/`
- Nginx logs: `/var/log/nginx/`
- Docker logs: Managed by Docker with size limits
- System logs: `/var/log/syslog`

**View logs:**
```bash
# Application logs
tail -f /var/log/ruuvi-home/deployment.log

# Docker service logs
docker-compose logs -f mqtt-reader
docker-compose logs -f api
docker-compose logs -f frontend

# Nginx access logs
tail -f /var/log/nginx/access.log
```

### 3. Database Backup and Maintenance

**Automated backups:**
- Daily backups at 2 AM via cron job
- 30-day retention policy
- Stored in `/home/pi/ruuvi-home/backups/`

**Manual backup:**
```bash
# Create backup
/home/pi/ruuvi-home/scripts/backup.sh

# Restore from backup
docker-compose exec -T timescaledb psql -U ruuvi -d ruuvi_home < backups/ruuvi_backup_YYYYMMDD_HHMMSS.sql.gz
```

**Database maintenance:**
```bash
# Check database size
docker-compose exec timescaledb psql -U ruuvi -d ruuvi_home -c "SELECT * FROM storage_monitoring;"

# Check TimescaleDB chunks
docker-compose exec timescaledb psql -U ruuvi -d ruuvi_home -c "SELECT * FROM timescaledb_information.chunks;"

# Run VACUUM (if needed)
docker-compose exec timescaledb psql -U ruuvi -d ruuvi_home -c "VACUUM ANALYZE;"
```

### 4. System Maintenance

**Update system packages:**
```bash
sudo apt update && sudo apt upgrade -y
```

**Update container images:**
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

**SSL Certificate renewal (if using Let's Encrypt):**
```bash
sudo certbot renew --nginx
```

## Troubleshooting

### Common Issues

#### 1. Services Won't Start

**Check Docker status:**
```bash
sudo systemctl status docker
docker-compose ps
docker-compose logs
```

**Common solutions:**
- Restart Docker: `sudo systemctl restart docker`
- Check disk space: `df -h`
- Verify environment variables: `cat .env`
- Check file permissions: `ls -la /home/pi/ruuvi-home/data/`

#### 2. Database Connection Issues

**Test database connectivity:**
```bash
# Test TimescaleDB
docker-compose exec timescaledb pg_isready -U ruuvi -d ruuvi_home

# Test Auth database
docker-compose exec auth-db pg_isready -U auth_user -d auth

# Check database logs
docker-compose logs timescaledb
docker-compose logs auth-db
```

**Common solutions:**
- Check if containers are running: `docker-compose ps`
- Verify passwords in `.env` file
- Restart database containers: `docker-compose restart timescaledb auth-db`

#### 3. MQTT Connection Issues

**Test MQTT connectivity:**
```bash
# Test local MQTT broker
mosquitto_pub -h localhost -t test -m "hello"
mosquitto_sub -h localhost -t test -C 1

# Check container status
docker-compose logs mosquitto
```

**Check network access:**
```bash
# From local network
mosquitto_sub -h YOUR_PI_IP -t ruuvi/gateway/data -C 1

# Check firewall
sudo ufw status numbered
```

#### 4. GitHub Actions Deployment Issues

**Common deployment problems:**
- **Webhook not triggered**: Check `WEBHOOK_URL` and `WEBHOOK_SECRET` in GitHub secrets
- **Authentication failures**: Verify webhook secret matches between GitHub and Pi
- **Network connectivity**: Ensure Pi is accessible from internet for webhooks
- **Container registry access**: GitHub automatically handles authentication for public repos

**Debug webhook:**
```bash
# Check webhook service
sudo systemctl status ruuvi-webhook

# Check webhook logs
journalctl -u ruuvi-webhook -f

# Test webhook manually
curl -X POST http://localhost:9000/webhook \
  -H "Content-Type: application/json" \
  -d '{"action":"published","release":{"tag_name":"test"}}'
```

#### 5. Memory/Performance Issues

**Check resource usage:**
```bash
# System resources
htop
free -h
df -h

# Container resources
docker stats

# Database performance
docker-compose exec timescaledb psql -U ruuvi -d ruuvi_home -c "SELECT * FROM pg_stat_activity;"
```

**Optimize for Raspberry Pi:**
- Enable swap: `sudo dphys-swapfile setup && sudo dphys-swapfile swapon`
- Reduce logging: Set `RUST_LOG=warn` in `.env`
- Limit container memory in docker-compose.yml
- Use SSD instead of SD card for better I/O

#### 6. SSL/HTTPS Issues

**Configure Let's Encrypt:**
```bash
# Install certificate
sudo certbot --nginx -d your-domain.com

# Test auto-renewal
sudo certbot renew --dry-run
```

**Check certificate status:**
```bash
sudo certbot certificates
```

### Performance Optimization

For optimal performance on Raspberry Pi:

1. **Storage optimization:**
   - Use SSD via USB 3.0 for better I/O performance
   - Mount data directory on SSD: `/home/pi/ruuvi-home/data`

2. **System optimization:**
   - Enable GPU memory split: `gpu_mem=16` in `/boot/config.txt`
   - Disable unnecessary services
   - Use appropriate swapfile size

3. **Database optimization:**
   - TimescaleDB compression is enabled automatically
   - Regular VACUUM operations
   - Monitor chunk size and compression ratios

4. **Container optimization:**
   - Use multi-stage builds to minimize image size
   - Configure appropriate memory limits
   - Use health checks for automatic recovery

### Getting Help

1. **Check logs first**: Always start with application and system logs
2. **Health check script**: Run `/home/pi/ruuvi-home/scripts/health-check.sh`
3. **GitHub Issues**: Report bugs or request features
4. **Documentation**: Refer to project README and API documentation

## Support

For additional support:
- GitHub Issues: https://github.com/viljami/ruuvi-home/issues
- Project Documentation: https://github.com/viljami/ruuvi-home/docs
- Ruuvi Community: https://f.ruuvi.com