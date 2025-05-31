# Ruuvi Home Setup System

This directory contains the modular, first-class setup system for Ruuvi Home on Raspberry Pi. It replaces the previous monolithic script with a clean, testable, and maintainable architecture.

## Quick Start

```bash
# Clone repository
git clone https://github.com/viljami/ruuvi-home.git
cd ruuvi-home

# Run setup (will auto-detect user from sudo)
sudo ./scripts/setup-pi.sh
```

## Architecture

The setup system follows clean separation of concerns:

- **Bash**: System operations (apt, systemctl, docker, file operations)
- **Python**: File generation and templating (Jinja2)
- **YAML**: Configuration (replacing bash env files)
- **Templates**: Clean, reusable file templates

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

### YAML Configuration (config.yaml)

Replace bash environment variables with structured YAML:

```yaml
user:
  name: "{{ SUDO_USER | default('pi') }}"
  home: "/home/{{ user.name }}"

project:
  directory: "{{ user.home }}/ruuvi-home"
  repository: "https://github.com/viljami/ruuvi-home.git"

ports:
  webhook: 9000
  frontend: 80
  api: 3000

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
# Full setup test
sudo ./setup-pi.sh
```

## Troubleshooting

### Common Issues

**Module execution fails**
```bash
# Check permissions
chmod +x scripts/setup-pi/modules/*.sh
chmod +x scripts/setup-pi/lib/*.sh
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