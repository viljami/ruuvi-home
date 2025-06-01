# Ruuvi Home

A Rust-based application for collecting, processing, and monitoring home environment data from Ruuvi Tags via Ruuvi Gateway on a Raspberry Pi.

## Overview

Ruuvi Home allows you to monitor your home's environmental conditions (temperature, humidity, air pressure, etc.) using [Ruuvi Tags](https://ruuvi.com/ruuvitag/) connected through a [Ruuvi Gateway](https://ruuvi.com/gateway/). The data is collected locally on a Raspberry Pi, stored efficiently, and made available through a simple web interface for real-time monitoring and historical analysis.

Originally implemented in Python, this project has been ported to Rust for improved performance and reliability, particularly on Raspberry Pi hardware.

## Features

- Receives data from Ruuvi Gateway via MQTT
- Decodes Ruuvi Tag data formats
- Processes and stores sensor readings in a time-series database
- Provides real-time monitoring through a web interface
- Visualizes historical data with customizable time ranges
- Optimized for Raspberry Pi deployment

## Requirements

- Raspberry Pi (3 or newer recommended)
- Ruuvi Gateway configured to send data to MQTT
- Ruuvi Tags placed around your home
- Mosquitto MQTT broker
- TimescaleDB (for time-series data storage)

## Development

### AI Code Validation

This project includes comprehensive code validation to ensure all changes meet quality standards. AI contributors must validate all code before submission.

**Quick Validation:**

```bash
./scripts/ai-validate.sh
```

**Language-Specific Validation:**

```bash
./scripts/ai-validate.sh --rust       # Rust code
./scripts/ai-validate.sh --typescript # TypeScript/React
./scripts/ai-validate.sh --python     # Python scripts
```

**Documentation:**

- [AI Coding Guidelines](AI_CODING_GUIDELINES.md) - Complete development rules
- [AI Validation Guide](docs/AI_VALIDATION_GUIDE.md) - Step-by-step validation instructions

All code must pass validation checks including:

- Syntax validation
- Linting (zero warnings)
- Code formatting
- Test execution
- Pattern validation (orphaned tags, bracket matching)

### Automatic Code Formatting

This project includes automatic code formatting to maintain consistent code style across all languages. The formatting is enforced through pre-commit hooks and CI/CD pipelines.

**One-time setup:**

```bash
./scripts/setup-dev.sh
```

This script installs pre-commit hooks and sets up all development dependencies.

**Manual formatting commands:**

```bash
# Rust (backend)
cd backend && make fmt

# Python (MQTT simulator)
cd docker/mqtt-simulator && make fmt

# All files via pre-commit
pre-commit run --all-files
```

**Pre-commit hooks automatically:**
- Format code on every commit
- Run linting checks
- Validate file structure
- Sort imports
- Fix trailing whitespace

**Important:** Use Makefile targets (not direct tool commands) to ensure consistency between local development and CI environments.

### Docker Build Troubleshooting

If you encounter Docker build failures (especially network connectivity issues), use the troubleshooting script:

```bash
# Check system and network status
./scripts/docker-build-fix.sh check

# Clean Docker cache and retry
./scripts/docker-build-fix.sh clean

# Build specific service with retry logic
./scripts/docker-build-fix.sh build mqtt-reader
./scripts/docker-build-fix.sh build api-server

# Build all services
./scripts/docker-build-fix.sh build-all

# Get detailed diagnostics
./scripts/docker-build-fix.sh diagnose
```

**Common issues and solutions:**

- **Network timeouts**: The script includes automatic retry logic with backoff
- **Package download failures**: Updated Dockerfiles use Debian Bookworm with retry logic
- **Cache corruption**: Use `clean` command to clear Docker build cache
- **Multi-platform issues**: Final CI retry uses amd64-only as fallback

**Manual troubleshooting:**

```bash
# Clear all Docker cache
docker builder prune -f
docker system prune -f

# Build locally for testing
docker build -f docker/mqtt-reader.Dockerfile -t ruuvi-mqtt-reader .
docker build -f docker/api-server.Dockerfile -t ruuvi-api-server .
```

## Project Structure

```
ruuvi-home/
├── README.md             # This file
├── PLAN.md               # Architectural and development plan
├── .github/              # GitHub Actions workflows
├── docker/               # Docker files for development
├── docker-compose.yaml   # Local development environment
├── backend/              # Rust workspace
│   ├── packages/
│   │   ├── mqtt-client/  # MQTT subscription
│   │   ├── data-store/   # Database interactions
│   │   ├── api-server/   # REST and WebSocket API
│   │   ├── ruuvi-decoder/# Decoding Ruuvi Tag data formats
│   │   └── common/       # Shared code and utilities
│   └── config/           # Configuration files
├── frontend/             # Web UI
│   ├── src/
│   │   ├── components/   # UI components
│   │   ├── services/     # API client code
│   │   └── views/        # Page layouts
│   └── public/           # Static assets
└── scripts/              # Development and deployment scripts
    ├── deploy.sh         # Deploy to Raspberry Pi
    ├── dev.sh            # Start development environment
    └── setup-pi.sh       # Set up Raspberry Pi
```

## Installation

1. Clone this repository to your computer:

   ```
   git clone https://github.com/yourusername/ruuvi-home.git
   cd ruuvi-home
   ```

2. For local development, use Docker Compose:

   ```
   docker-compose up
   ```

3. For Raspberry Pi deployment:
   ```
   ./scripts/deploy.sh your-pi-hostname
   ```

## Configuration

Configuration files are located in the `backend/config` directory. You'll need to set:

- MQTT broker connection details
- Ruuvi Gateway information
- TimescaleDB connection settings
- Sensor location mapping (which sensor is in which room)
- Data retention policies

## Technology Stack

- **Rust** - Backend services
- **MQTT** - Communication protocol for IoT devices
- **TimescaleDB** - Time-series database for sensor data
- **Cap'n Proto** - Efficient serialization format
- **Tokio** - Asynchronous runtime for Rust
- **React/TypeScript** - Frontend web interface
- **Chart.js** - Data visualization

## Development

To set up a development environment:

1. Install Docker and Docker Compose
2. Run `docker-compose up` to start all required services
3. Frontend will be available at http://localhost:3000
4. API will be available at http://localhost:8080

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
