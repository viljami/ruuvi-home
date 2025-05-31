# Production Deployment Guide

This guide covers deploying Ruuvi Home to production on Raspberry Pi, ensuring the `mqtt-simulator` is never deployed to production environments.

## Overview

Ruuvi Home has two deployment configurations:

- **Development** (`docker-compose.yaml`) - includes mqtt-simulator for testing
- **Production** (`docker-compose.production.yaml`) - excludes mqtt-simulator, expects real sensors

## Critical Security Note

⚠️ **The `mqtt-simulator` service MUST NEVER be deployed to production.** It is for development and testing only.

## Quick Production Deployment

```bash
# 1. Run the automated deployment script
./scripts/deploy-production.sh

# 2. Or manually deploy
docker-compose -f docker-compose.production.yaml up -d
```

## Prerequisites

### Hardware Requirements
- Raspberry Pi 4 (4GB RAM recommended)
- 32GB+ SD Card (Class 10)
- Stable internet connection
- Ruuvi Gateway or compatible MQTT publisher

### Software Requirements
- Raspberry Pi OS (64-bit recommended)
- Docker and Docker Compose
- Git

### Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose -y

# Reboot to apply group changes
sudo reboot
```

## Environment Configuration

### 1. Copy Production Environment Template

```bash
cp .env.production .env
```

### 2. Update Critical Values

Edit `.env` and replace ALL `CHANGE_THIS_TO_*` placeholders:

```bash
# REQUIRED: Change these values
POSTGRES_PASSWORD=your_secure_database_password
AUTH_DB_PASSWORD=your_secure_auth_password
JWT_SECRET=your_secure_jwt_secret_at_least_32_characters

# OPTIONAL: Update these for your domain
PUBLIC_API_URL=https://your-domain.com/api
PUBLIC_FRONTEND_URL=https://your-domain.com
CORS_ALLOW_ORIGIN=https://your-domain.com
```

### 3. Validate Configuration

The deployment script will validate your environment and fail if placeholder values remain.

## Production Services

The production configuration includes:

- **mosquitto** - MQTT broker for sensor data
- **timescaledb** - Time-series database
- **mqtt-reader** - Rust service for MQTT→DB pipeline
- **api-server** - REST API backend
- **frontend** - React web application

**Excluded in production:**
- ❌ **mqtt-simulator** - Development only

## Deployment Methods

### Method 1: Automated Script (Recommended)

```bash
# Run the production deployment script
./scripts/deploy-production.sh
```

The script will:
1. Verify you're on Raspberry Pi
2. Check Docker installation
3. Validate environment configuration
4. Verify mqtt-simulator is excluded
5. Stop any existing services
6. Deploy production services
7. Verify deployment health

### Method 2: Manual Deployment

```bash
# Stop any existing services
docker-compose down --remove-orphans

# Deploy production services
docker-compose -f docker-compose.production.yaml up -d

# Verify deployment
docker-compose -f docker-compose.production.yaml ps
```

## Post-Deployment Verification

### 1. Check Service Status

```bash
docker-compose -f docker-compose.production.yaml ps
```

All services should show `Up` status.

### 2. Verify No Simulator Running

```bash
# This should return empty
docker ps | grep mqtt-simulator
```

### 3. Test API Health

```bash
curl http://localhost:8080/health
```

Expected response: `{"status":"healthy","timestamp":"..."}`

### 4. Access Frontend

Open http://localhost:3000 in your browser.

## Real Sensor Configuration

### Ruuvi Gateway Setup

Your Ruuvi Gateway must be configured to publish data to:

- **MQTT Broker**: `your-pi-ip:1883`
- **Topic**: `ruuvi/gateway/data`
- **Format**: JSON payload with sensor readings

### Expected Data Format

```json
{
  "gateway_mac": "AA:BB:CC:DD:EE:FF",
  "timestamp": 1640995200,
  "sensors": [
    {
      "mac": "AA:BB:CC:DD:EE:01",
      "rssi": -65,
      "temperature": 21.5,
      "humidity": 45.2,
      "pressure": 1013.25,
      "battery": 2800
    }
  ]
}
```

## Monitoring and Maintenance

### View Logs

```bash
# All services
docker-compose -f docker-compose.production.yaml logs -f

# Specific service
docker-compose -f docker-compose.production.yaml logs -f api-server
```

### Database Backup

```bash
# Create backup
docker exec ruuvi-timescaledb pg_dump -U ruuvi ruuvi_home > backup-$(date +%Y%m%d).sql

# Restore backup
docker exec -i ruuvi-timescaledb psql -U ruuvi -d ruuvi_home < backup-20240101.sql
```

### Updates

```bash
# Pull latest code
git pull origin main

# Rebuild and restart
docker-compose -f docker-compose.production.yaml down
docker-compose -f docker-compose.production.yaml up -d --build
```

## Security Considerations

### 1. Change Default Passwords

Ensure all database passwords are changed from defaults.

### 2. Firewall Configuration

```bash
# Allow only necessary ports
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 3000/tcp  # Frontend
sudo ufw allow 8080/tcp  # API
sudo ufw allow 1883/tcp  # MQTT
```

### 3. SSL/TLS (Optional)

For production domains, consider:
- Setting up reverse proxy (nginx)
- Obtaining SSL certificates (Let's Encrypt)
- Updating CORS_ALLOW_ORIGIN

### 4. Regular Updates

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Docker images
docker-compose -f docker-compose.production.yaml pull
docker-compose -f docker-compose.production.yaml up -d
```

## Troubleshooting

### Services Won't Start

```bash
# Check service logs
docker-compose -f docker-compose.production.yaml logs

# Check individual service
docker logs ruuvi-api-server
```

### Database Connection Issues

```bash
# Test database connectivity
docker exec ruuvi-timescaledb psql -U ruuvi -d ruuvi_home -c "SELECT 1;"
```

### No Sensor Data

1. Verify MQTT broker is receiving data:
   ```bash
   docker exec ruuvi-mosquitto mosquitto_sub -t "ruuvi/gateway/data" -v
   ```

2. Check mqtt-reader service logs:
   ```bash
   docker logs ruuvi-mqtt-reader
   ```

3. Verify Gateway configuration points to correct IP/port

### API Not Responding

```bash
# Check API server logs
docker logs ruuvi-api-server

# Verify database connection
curl http://localhost:8080/health
```

### Frontend Not Loading

```bash
# Check frontend logs
docker logs ruuvi-frontend

# Verify API URL in environment
grep REACT_APP_API_URL .env
```

## Development vs Production

| Feature | Development | Production |
|---------|-------------|------------|
| mqtt-simulator | ✅ Included | ❌ Excluded |
| Real sensors | ⚪ Optional | ✅ Required |
| Environment | `NODE_ENV=development` | `NODE_ENV=production` |
| Passwords | Defaults OK | Must be changed |
| Monitoring | Basic | Health checks |
| SSL/TLS | Not required | Recommended |

## Support

For issues with production deployment:

1. Check service logs first
2. Verify environment configuration
3. Ensure no mqtt-simulator containers are running
4. Review this documentation
5. File issue on GitHub with logs and configuration (redact passwords)

## Security Checklist

Before going live:

- [ ] All placeholder passwords changed
- [ ] mqtt-simulator is not running
- [ ] Firewall configured
- [ ] Real sensors configured
- [ ] Health checks passing
- [ ] Logs are clean
- [ ] Backup strategy in place
- [ ] Monitoring configured