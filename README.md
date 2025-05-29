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
- InfluxDB (for time-series data storage)

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
- InfluxDB connection settings
- Sensor location mapping (which sensor is in which room)
- Data retention policies

## Technology Stack

- **Rust** - Backend services
- **MQTT** - Communication protocol for IoT devices
- **InfluxDB** - Time-series database for sensor data
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