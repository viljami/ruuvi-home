# Ruuvi Home Setup System

This directory contains the modular, first-class setup system for Ruuvi Home on Raspberry Pi. It replaces the previous monolithic script with a clean, testable, and maintainable architecture.

## Quick Start

### Interactive Setup
```bash
# Clone repository
git clone https://github.com/viljami/ruuvi-home.git
cd ruuvi-home

# Run setup (will prompt for deployment mode choice)
sudo ./scripts/setup-pi/setup-pi.sh
```

### Non-Interactive Setup
```bash
# GitHub Registry mode (recommended for production)
export DEPLOYMENT_MODE=registry
export GITHUB_REPO=username/ruuvi-home
sudo ./scripts/setup-pi/setup-pi.sh

# Local build mode (for development)
export DEPLOYMENT_MODE=local
sudo ./scripts/setup-pi/setup-pi.sh
```

## Deployment Modes

The setup system supports two deployment modes to accommodate different use cases:

### 1. GitHub Registry Mode (Recommended)
- **Purpose**: Production deployments using pre-built images
- **How it works**: Pulls Docker images from GitHub Container Registry (ghcr.io)
- **Benefits**:
  - Faster deployment (no local building)
  - Consistent images across environments
  - Reduced Pi resource usage
  - CI/CD pipeline integration
- **Requirements**: Network access to ghcr.io and valid GitHub repository

### 2. Local Build Mode
- **Purpose**: Development and standalone deployments
- **How it works**: Builds all Docker images locally from source code
- **Benefits**:
  - Full control over build process
  - No external dependencies
  - Ability to modify source before building
- **Requirements**: Sufficient Pi resources for building (4GB+ RAM recommended)

### Mode Selection
```bash
# Interactive mode - will prompt for choice
sudo ./scripts/setup-pi/setup-pi.sh

# Non-interactive via environment variables
export DEPLOYMENT_MODE=registry  # or 'local', '1', '2'
export GITHUB_REPO=username/ruuvi-home  # required for registry mode
sudo ./scripts/setup-pi/setup-pi.sh
```

## HTTPS Webhook Configuration

The setup system includes built-in HTTPS support for secure webhook communication with GitHub.

### HTTPS Options

#### 1. Self-Signed Certificate (Default)
- **Best for**: Development and internal networks
- **Setup**: Automatic during installation
- **Security**: Encrypted traffic, but browsers will show warnings
- **Configuration**: No additional setup required

#### 2. Let's Encrypt Certificate (Recommended for Production)
- **Best for**: Production deployments with public domain
- **Setup**: Automatic with valid domain name
- **Security**: Trusted by all browsers and GitHub
- **Requirements**: Public domain name pointing to your Pi

### HTTPS Configuration

#### Interactive Setup
The setup script will prompt for HTTPS configuration:
```bash
sudo ./scripts/setup-pi/setup-pi.sh
# Will ask: "Choose HTTPS method: 1) Self-signed 2) Let's Encrypt"
```

#### Non-Interactive Setup

**Self-Signed Certificate:**
```bash
export DEPLOYMENT_MODE=registry
export GITHUB_REPO=username/ruuvi-home
export ENABLE_HTTPS=true
export ENABLE_LETS_ENCRYPT=false
sudo ./scripts/setup-pi/setup-pi.sh
```

**Let's Encrypt Certificate:**
```bash
export DEPLOYMENT_MODE=registry
export GITHUB_REPO=username/ruuvi-home
export ENABLE_HTTPS=true
export ENABLE_LETS_ENCRYPT=true
export WEBHOOK_DOMAIN=webhook.yourdomain.com
export WEBHOOK_EMAIL=admin@yourdomain.com
export LETS_ENCRYPT_STAGING=false  # Use 'true' for testing
sudo ./scripts/setup-pi/setup-pi.sh
```

### GitHub Webhook Configuration with HTTPS

#### For Self-Signed Certificates:
1. **GitHub Repository → Settings → Webhooks → Add webhook**
2. **Configuration:**
   - Payload URL: `https://YOUR_PI_IP:9000`
   - Content type: `application/json`
   - Secret: [from `/home/pi/ruuvi-home/.env`]
   - SSL verification: ❌ **Disable** (required for self-signed)
   - Events: ✅ Just the push event

#### For Let's Encrypt Certificates:
1. **GitHub Repository → Settings → Webhooks → Add webhook**
2. **Configuration:**
   - Payload URL: `https://webhook.yourdomain.com:9000`
   - Content type: `application/json`
   - Secret: [from `/home/pi/ruuvi-home/.env`]
   - SSL verification: ✅ **Enable** (trusted certificate)
   - Events: ✅ Just the push event

### Certificate Management

#### Automatic Renewal (Let's Encrypt)
- Certificates auto-renew every 12 hours via cron
- Webhook service automatically restarts after renewal
- Logs available at: `/var/log/ruuvi-home/ssl-renewal.log`

#### Manual Certificate Operations
```bash
# Check certificate status
openssl x509 -in /home/pi/ruuvi-home/ssl/webhook.crt -noout -dates

# Force Let's Encrypt renewal
sudo certbot renew --force-renewal

# View webhook logs
journalctl -u ruuvi-webhook -f

# Restart webhook service
sudo systemctl restart ruuvi-webhook
```

### Security Considerations

#### Production Security Checklist:
- ✅ Use Let's Encrypt for trusted certificates
- ✅ Keep webhook secret secure (32+ character random string)
- ✅ Enable firewall (UFW configured automatically)
- ✅ Regular certificate monitoring
- ✅ Restrict webhook access to GitHub IP ranges

#### Network Security:
```bash
# Restrict webhook to GitHub IPs only (optional)
sudo ufw delete allow 9000/tcp
sudo ufw allow from 140.82.112.0/20 to any port 9000
sudo ufw allow from 185.199.108.0/22 to any port 9000
sudo ufw allow from 192.30.252.0/22 to any port 9000
```

### Troubleshooting HTTPS

#### Common Issues:

**Certificate Generation Failed:**
```bash
# Check OpenSSL installation
openssl version

# Regenerate self-signed certificate
sudo rm -f /home/pi/ruuvi-home/ssl/*
sudo systemctl restart ruuvi-webhook
```

**Let's Encrypt Validation Failed:**
```bash
# Check domain DNS resolution
nslookup webhook.yourdomain.com

# Check port 80 accessibility (required for validation)
sudo ufw allow 80/tcp
curl -I http://webhook.yourdomain.com/.well-known/acme-challenge/test

# Use staging server for testing
export LETS_ENCRYPT_STAGING=true
```

**GitHub Webhook SSL Errors:**
- Self-signed: Disable SSL verification in GitHub webhook settings
- Let's Encrypt: Ensure certificate is valid and not staging
- Check certificate expiry: `openssl x509 -in cert.crt -noout -dates`

**Service Not Starting:**
```bash
# Check webhook service logs
journalctl -u ruuvi-webhook -f

# Validate certificate files
openssl x509 -in /home/pi/ruuvi-home/ssl/webhook.crt -text -noout
openssl rsa -in /home/pi/ruuvi-home/ssl/webhook.key -check
```

### Environment Variables Reference

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `ENABLE_HTTPS` | Enable HTTPS for webhook | `true` | `true`, `false` |
| `ENABLE_LETS_ENCRYPT` | Use Let's Encrypt certificate | `false` | `true`, `false` |
| `WEBHOOK_DOMAIN` | Domain for Let's Encrypt | none | `webhook.domain.com` |
| `WEBHOOK_EMAIL` | Email for Let's Encrypt | none | `admin@domain.com` |
| `WEBHOOK_PORT` | Webhook server port | `9000` | `9000`, `8443` |
| `LETS_ENCRYPT_STAGING` | Use staging server | `true` | `true`, `false` |

## Architecture

The setup system follows clean separation of concerns:

- **Bash**: System operations (apt, systemctl, docker, file operations)
- **Python**: File generation and templating (Jinja2)
- **YAML**: Configuration (replacing bash env files)
- **Templates**: Clean, reusable file templates

### Complete Setup
```bash
sudo ./scripts/setup-pi.sh
```

### Directory Structure

```
scripts/
├── setup-pi.sh              # Main entry point
└── setup-pi/                # Modular setup system
    ├── README.md            # This file
    ├── setup-pi.sh          # Orchestrator script
    ├── generator.py         # Python file generator
    ├── config.yaml          # Configuration template
    ├── config/
    │   └── setup.env        # Legacy env (deprecated)
    ├── lib/
    │   ├── logging.sh       # Logging utilities
    │   └── validation.sh    # Validation functions
    ├── modules/
    │   ├── 00-validation.sh      # Pre-flight checks
    │   ├── 01-system-setup.sh    # Base system prep
    │   ├── 02-docker-setup.sh    # Docker installation
    │   ├── 03-directories.sh     # Directory structure
    │   ├── 04-file-generation.sh # File generation (Python)
    │   ├── 05-systemd-services.sh # Service setup
    │   ├── 06-backup-system.sh   # Backup configuration
    │   └── 07-monitoring.sh      # Monitoring setup
    └── templates/
        ├── webhook.py.j2         # Python script template
        ├── ruuvi-webhook.service.j2 # Systemd service template
        └── *.j2                  # Other Jinja2 templates
```

## Design Principles

### 1. Clean Separation of Concerns
- **Bash modules**: Handle system operations only
- **Python generator**: Handle file generation and templating
- **YAML config**: Centralized configuration
- **Jinja2 templates**: Clean, logic-free templates

### 2. Modular Components
- Each module has single responsibility
- Modules are independently testable
- Loose coupling between components
- Configuration-driven behavior

### 3. First-Class Setup Script
- Treats setup as a primary application concern
- Professional logging and error handling
- Comprehensive validation
- Clear progress tracking

## Module Descriptions

### Core System Modules

**00-validation.sh**
- Pre-flight system checks
- User and permission validation
- Network connectivity tests
- Dependency verification

**01-system-setup.sh**
- Package installation
- System configuration
- Shell setup (Fish)
- Locale and timezone

**02-docker-setup.sh**
- Docker Engine installation
- Docker Compose setup
- User permissions
- Daemon configuration

**03-directories.sh**
- Project structure creation
- Repository cloning/updating
- Permission setup
- Environment file initialization

### File Generation

**04-file-generation.sh**
- Uses Python generator for templating
- Generates scripts from Jinja2 templates
- Creates systemd services
- Produces configuration files
- Sets proper permissions

**generator.py**
- Python-based file generator
- Jinja2 templating engine
- Type-safe configuration
- Validation and error handling

### Service Setup

**05-systemd-services.sh**
- Systemd service installation
- Service enablement
- Dependency configuration
- Health validation

**06-backup-system.sh**
- Automated backup scripts
- Cron job configuration
- Retention policies
- Database backup setup

**07-monitoring.sh**
- Health monitoring setup
- Log rotation configuration
- Alert thresholds
- Performance monitoring

## Configuration

### Environment Variables

The setup script supports these environment variables for non-interactive deployment:

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `DEPLOYMENT_MODE` | Deployment mode selection | Yes | `registry`, `local`, `1`, `2` |
| `GITHUB_REPO` | GitHub repository for registry mode | Registry mode only | `username/ruuvi-home` |
| `GITHUB_REGISTRY` | Container registry URL | No | `ghcr.io` (default) |
| `IMAGE_TAG` | Docker image tag to use | No | `latest` (default) |

### YAML Configuration (config.yaml)

Replace bash environment variables with structured YAML:

```yaml
user:
  name: "{{ SUDO_USER | default('pi') }}"
  home: "/home/{{ user.name }}"

project:
  directory: "{{ user.home }}/ruuvi-home"
  repository: "https://github.com/viljami/ruuvi-home.git"

deployment:
  mode: "{{ DEPLOYMENT_MODE | default('local') }}"
  github_repo: "{{ GITHUB_REPO | default('') }}"
  registry: "{{ GITHUB_REGISTRY | default('ghcr.io') }}"
  image_tag: "{{ IMAGE_TAG | default('latest') }}"

ports:
  webhook: 9000
  frontend: 80
  api: 8080

features:
  fish_shell: true
  backup_cron: true
  monitoring: true
```

### Template Variables

Templates receive configuration as variables:

```python
# In Python templates
config.webhook.port
config.user.name
config.project.directory
```

```bash
# In shell templates
{{ webhook.port }}
{{ user.name }}
{{ project.directory }}
```

## Usage Patterns

### Complete Setup
```bash
sudo ./scripts/setup-pi.sh
```

### Individual Modules
```bash
# Run specific module
sudo ./scripts/setup-pi/modules/02-docker-setup.sh

# Generate files only
sudo ./scripts/setup-pi/modules/04-file-generation.sh
```

### File Generation Only
```bash
# Generate specific file types
python3 ./scripts/setup-pi/generator.py config.yaml --type python
python3 ./scripts/setup-pi/generator.py config.yaml --type systemd
```

### Validation Only
```bash
sudo ./scripts/setup-pi/modules/00-validation.sh
```

## Migration from Legacy Script

### Key Improvements

| Legacy Script | New Modular System |
|--------------|-------------------|
| 800+ line monolith | Multiple focused modules |
| Mixed concerns | Clean separation |
| Hardcoded values | Configuration-driven |
| Embedded code generation | Clean templates |
| Limited testing | Unit testable |
| Bash-only | Bash + Python hybrid |

### Migration Steps

1. **Backup existing setup**
   ```bash
   cp scripts/setup-pi.sh scripts/setup-pi.sh.legacy
   ```

2. **Test new system**
   ```bash
   sudo ./scripts/setup-pi.sh --dry-run  # When implemented
   ```

3. **Run new setup**
   ```bash
   sudo ./scripts/setup-pi.sh
   ```

## Development

### Adding New Modules

1. Create module file: `modules/XX-feature.sh`
2. Follow naming convention: Sequential numbering
3. Include proper logging and validation
4. Add to orchestrator's `SETUP_MODULES` array
5. Update this README

### Module Template

```bash
#!/bin/bash
# Module: Feature Description
# Dependencies: List prerequisites

set -e

readonly MODULE_CONTEXT="FEATURE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/lib/logging.sh"

setup_feature() {
    local context="$MODULE_CONTEXT"
    log_info "$context" "Setting up feature"

    # Implementation here

    log_success "$context" "Feature setup completed"
}

export -f setup_feature
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_feature
fi
```

### Adding Templates

1. Create Jinja2 template: `templates/filename.j2`
2. Add to generator.py configuration
3. Test template rendering
4. Update documentation

### Template Example

```jinja2
#!/bin/bash
# Generated script for {{ user.name }}

PROJECT_DIR="{{ project.directory }}"
LOG_FILE="{{ directories.logs }}/script.log"

# Script implementation
echo "Running for user: {{ user.name }}"
```

## Testing

### Module Testing
```bash
# Syntax check
bash -n modules/01-system-setup.sh

# Execution test (dry run when available)
sudo modules/00-validation.sh
```

### Template Testing
```bash
# Test file generation
python3 generator.py config.yaml --type python --verbose
```

### Integration Testing
```bash
# Full setup test - registry mode
export DEPLOYMENT_MODE=registry
export GITHUB_REPO=username/ruuvi-home
sudo ./scripts/setup-pi/setup-pi.sh

# Full setup test - local build mode
export DEPLOYMENT_MODE=local
sudo ./scripts/setup-pi/setup-pi.sh
```

## Troubleshooting

### Common Issues

**Module execution fails**
```bash
# Check permissions
chmod +x scripts/setup-pi/modules/*.sh
chmod +x scripts/setup-pi/lib/*.sh
```

**Registry mode image pull fails**
```bash
# Check network connectivity
ping ghcr.io

# Verify repository exists
export GITHUB_REPO=username/ruuvi-home
docker pull ghcr.io/${GITHUB_REPO}/frontend:latest

# Check repository permissions (if private)
docker login ghcr.io
```

**Local build mode fails**
```bash
# Check available disk space (need 2GB+)
df -h

# Check available memory (need 2GB+ free)
free -h

# Monitor build process
docker system df
```

**Template generation fails**
```bash
# Install Python dependencies
pip3 install pyyaml jinja2

# Check template syntax
python3 -c "from jinja2 import Template; Template(open('template.j2').read())"
```

**Configuration errors**
```bash
# Validate YAML
python3 -c "import yaml; yaml.safe_load(open('config.yaml'))"

# Check deployment mode settings
echo "DEPLOYMENT_MODE=$DEPLOYMENT_MODE"
echo "GITHUB_REPO=$GITHUB_REPO"
```

### Log Locations

- Setup logs: `/var/log/ruuvi-home/setup.log`
- Module logs: Console output during setup
- Service logs: `journalctl -u ruuvi-home -f`
- Generator logs: Console output with `--verbose`

## Complete Setup Result

After successful setup, you'll have:

1. **Running Services**
   - `ruuvi-home.service` - Main application
   - `ruuvi-webhook.service` - GitHub deployment webhook

2. **Directory Structure**
   - `/home/user/ruuvi-home/` - Project directory
   - `/var/log/ruuvi-home/` - Log files
   - `/home/user/ruuvi-home/backups/` - Database backups

3. **Generated Files**
   - Python scripts (webhook, health check, database manager)
   - Shell scripts (deploy, backup, maintenance)
   - Configuration files (.env, docker-compose.yml)
   - Systemd service files

4. **Automated Tasks**
   - Daily database backups
   - Log rotation
   - Health monitoring
   - GitHub deployment webhook

5. **User Environment**
   - Fish shell configuration
   - Docker group membership
   - Ruuvi-specific aliases and tools

The system will be ready to accept GitHub deployments and serve the Ruuvi Home application.
