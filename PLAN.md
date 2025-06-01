# Ruuvi Home: Architecture & Development Plan

## Current Architecture Assessment

The project is already structured as a Rust workspace with several packages:

- `mqtt-reader`: Connects to MQTT and reads Ruuvi Gateway data
- `ruuvi-decoder`: Decodes the Ruuvi Tag data formats
- `orchestrator`: Coordinates the components
- `api`: Presumably provides data access

This workspace approach is a good start, but we can refine it further to match the project milestones.

## Proposed Architecture

Here's a simplified architecture that aligns with the milestones:

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  Ruuvi Gateway  │ ──MQTT──►  Data Collector │ ───────►│   Data Storage  │
└─────────────────┘         │    (Rust)       │         │                 │
                            └─────────────────┘         └────────┬────────┘
                                                                 │
                                                                 │
                            ┌─────────────────┐         ┌────────▼────────┐
                            │    Web UI       │◄────────│   API Server    │
                            │  (TypeScript)   │         │     (Rust)      │
                            └─────────────────┘         └─────────────────┘
                                     ▲                          │
                                     │                          │
                                     └──────────WebSocket───────┘
```

### Components

1. **Data Collector** (Milestone 1)

   - MQTT client connecting to Mosquitto
   - Ruuvi data decoder
   - Simple configuration for MQTT connection

2. **Data Storage** (Milestone 2)

   - Efficient data storage solution
   - Query capabilities for historical data
   - Time-series optimization

3. **API Server** (Milestone 3)

   - REST API for querying historical data
   - WebSocket server for real-time updates
   - Data aggregation and processing

4. **Web UI** (Milestone 3)
   - Simple dashboard for displaying sensor data
   - Real-time updates via WebSocket
   - Historical data viewing capabilities

## Milestones

1. Subscribe to Ruuvi Gateway data from MQTT server
2. Save the data in a resource-friendly way that could be queried or further processed
3. Build simple Web UI to display the collected data, with WebSocket and REST server for queries and real-time updates

## Technical Decisions

### 1. Data Storage

For time-series sensor data:

- **TimeseriesDB** is ideal for time-series data and has good Rust support
- Lightweight enough for a Raspberry Pi
- Provides good query capabilities for time-series data
- Has retention policies for managing data growth

### 2. API and Web Communication

For the API and WebSockets:

- **axum** or **warp** for the Rust web framework (both are lightweight and async)
- **tokio** for async runtime (already in use)
- **WebSockets** for real-time data pushing to the frontend

### 3. Web UI

For a simple but effective frontend:

- **React** or **Svelte** (both are lightweight)
- **Chart.js** or **D3.js** for data visualization
- **TypeScript** for type safety

### 4. Project Organization

For the monorepo approach:

- Keep the Rust workspace for backend components
- Add a frontend directory for the web UI
- Use a unified build system (e.g., Makefile or just scripts)

## Development Workflow

### 1. Local Development

- Use Docker for local development to simulate the Raspberry Pi environment
- Docker Compose to run all services (TimeseriesDB, Mosquitto, your Rust app)
- Hot reloading for faster development

### 2. Testing

- Unit tests for individual components
- Integration tests for the full system
- Mock MQTT server for testing without real hardware

### 3. CI/CD with GitHub Actions

- Automatic testing on push
- Build artifacts for Raspberry Pi (cross-compilation)
- Deployment scripts for pushing to your Raspberry Pi

## Implementation Plan by Milestone

### Milestone 1: MQTT Subscription

1. Refine the existing mqtt-reader package
2. Create a simple configuration system
3. Implement comprehensive error handling and logging
4. Add unit tests with mock MQTT server

### Milestone 2: Data Storage

1. Implement TimescaleDb client in Rust
2. Create data models and storage schemas
3. Implement data retention and optimization policies
4. Add query capabilities for historical data

### Milestone 3: Web UI and API

1. Implement REST API endpoints
2. Add WebSocket server for real-time updates
3. Create a simple React/Svelte frontend
4. Implement data visualization components

## Directory Structure

Proposed directory structure for the monorepo:

```
ruuvi-home/
├── README.md
├── .github/              # GitHub Actions workflows
├── docker/               # Docker files for development
├── backend/              # Rust workspace
│   ├── Cargo.toml        # Workspace definition
│   ├── packages/
│   │   ├── mqtt-client/  # MQTT subscription (formerly mqtt-reader)
│   │   ├── data-store/   # Database interactions
│   │   ├── api-server/   # REST and WebSocket API
│   │   ├── ruuvi-decoder/# Decoding Ruuvi formats
│   │   └── common/       # Shared code and utilities
│   └── config/           # Configuration files
├── frontend/             # Web UI
│   ├── package.json
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

## Next Steps

1. **Refactor Existing Code**

   - Review and clean up the existing packages
   - Update naming for clarity
   - Add missing documentation

2. **Set Up Development Environment**

   - Create Docker Compose file for local development
   - Set up TimescaleDb container
   - Configure Mosquitto for testing

3. **Start with Milestone 1**
   - Enhance the MQTT client functionality
   - Implement proper error handling
   - Add configuration options

## Key Considerations

1. **Raspberry Pi Resource Constraints**

   - Optimize for memory and CPU usage
   - Consider data retention strategies to manage storage
   - Use efficient serialization formats (Cap'n Proto already selected)

2. **Development Experience**

   - Create a seamless local development environment
   - Make deployment to Raspberry Pi simple and reliable
   - Ensure good logging and error reporting

3. **Maintainability**
   - Document code and architecture decisions
   - Use consistent coding patterns across components
   - Implement comprehensive tests
