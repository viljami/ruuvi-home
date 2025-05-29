# Ruuvi Home: Implementation Milestones

This document outlines our implementation roadmap for the Ruuvi Home project, focusing on delivering value early through vertical slices of functionality rather than building horizontal layers.

## Phase 1: Minimum Viable Full-Stack Implementation

### Milestone 1.1: Local Development Environment

**Goal**: Set up a complete local development environment with simulated data flow.

- [x] Create docker-compose.yaml with all required services
- [x] Implement MQTT simulator to generate mock Ruuvi data
- [x] Configure Mosquitto MQTT broker
- [x] Set up InfluxDB container
- [x] Create development documentation
- [x] Implement comprehensive tests for MQTT simulator
- [x] Create test runner scripts and Docker test setup
- [x] Fix MQTT simulator to match actual Ruuvi Gateway message format
- [x] Set up Python virtual environment for local development

**Acceptance Criteria**:

- Can start all services with a single command
- Simulated MQTT messages visible in Mosquitto logs
- InfluxDB UI accessible and ready for data
- Tests verify correctness of simulated data
- Simulator produces messages in the exact format used by real Ruuvi Gateways

### Milestone 1.2: Data Ingestion Slice

**Goal**: Implement basic MQTT subscription and data storage.

- [*] Implement minimal MQTT client that connects to broker
- [*] Create basic Ruuvi data decoder for essential metrics
- [*] Implement InfluxDB writer for time-series storage
- [*] Add logging and error handling
- [*] Write unit tests for MQTT decoding
- [*] Write unit tests for MQTT subscription

**Acceptance Criteria**:

- MQTT client successfully connects to broker
- Ruuvi data formats correctly decoded
- Data successfully stored in InfluxDB

### Milestone 1.3: API Slice

**Goal**: Create minimal API for data retrieval.

- [x] Implement REST API server with basic endpoints
- [x] Create endpoint for active sensors list
- [x] Create endpoint for latest sensor readings
- [x] Create endpoint for historical data (simple time range)
- [x] Add basic error handling and validation
- [x] Create comprehensive API integration tests
- [x] Add API testing and validation tools

**Acceptance Criteria**:

- ✅ API endpoints accessible via HTTP
- ✅ Returns correctly formatted JSON
- ✅ Can retrieve sensor list and latest readings
- ✅ Basic error cases handled appropriately

**Testing**:
- Integration test suite: `tests/api_integration_test.py`
- Quick validation: `scripts/test-api.sh`
- Full test runner: `tests/run_tests.sh`

### Milestone 1.4: Frontend Slice

**Goal**: Create simple UI to display sensor data.

- [x] Set up basic React application
- [x] Implement data fetching from API
- [x] Create simple dashboard with current readings
- [x] Add basic sensor selection
- [x] Implement automatic refresh
- [x] Create comprehensive UI components (SensorCard, LoadingSpinner, ErrorMessage)
- [x] Add responsive design with Material-UI
- [x] Implement sensor detail view with charts
- [x] Add real-time data updates with React Query

**Acceptance Criteria**:

- ✅ UI displays current sensor readings
- ✅ Updates automatically at regular intervals
- ✅ Basic navigation between sensors
- ✅ Properly handles loading and error states

**Additional Features Implemented**:
- Real-time dashboard with auto-refresh every 30 seconds
- Detailed sensor view with historical charts
- Responsive design for mobile and desktop
- Error handling with retry functionality
- TypeScript for type safety
- Material-UI components for consistent design
- PWA support with manifest.json

## Phase 2: Deployment Pipeline

### Milestone 2.1: Raspberry Pi Setup

**Goal**: Prepare Raspberry Pi environment for application deployment.

- [ ] Create Pi setup script for OS preparation

  - [ ] Install Docker and Docker Compose on Pi
  - [ ] Configure network and security settings
  - [ ] Set up data persistence volumes
  - [ ] Ensure no secrets are exposed or stored insecurely
  - [ ] Implement secure key management
        [ ] Test Pi environment with basic containers (Human needs to setup the actual PI)
  - [ ] Is there a way to setup Raspberry PI with one command to have all prerequisites installed and configured?

        **Acceptance Criteria**:

- Pi successfully runs Docker containers
- Network properly configured for local access
- Data persistence confirmed across restarts
- Resource usage within acceptable limits
- Pi can be easily provisioned with a single command

### Milestone 2.2: GitHub Actions CI Pipeline

**Goal**: Implement continuous integration with automated testing.

- [ ] Set up GitHub Actions workflow
- [ ] Implement automated build process
- [ ] Add automated testing
- [ ] Configure multi-architecture image building
- [ ] Push images to GitHub Container Registry

**Acceptance Criteria**:

- CI pipeline runs on each commit
- Tests execute successfully
- Docker images built for ARM architecture
- Images available in GitHub Container Registry

### Milestone 2.3: Automated Deployment

**Goal**: Create automated deployment from GitHub to Raspberry Pi.

- [ ] Implement deployment script for Pi
- [ ] Configure secure SSH access from GitHub Actions
- [ ] Set up secure environment variable management
- [ ] Implement deployment verification
- [ ] Add rollback capability

**Acceptance Criteria**:

- Changes automatically deploy to Pi after successful build
- Deployment logs available for debugging
- Failed deployments don't break existing functionality
- Can roll back to previous version if needed
- No sensitive information is exposed in repositories or logs

**Environment Variable Security**:

- [ ] Create a comprehensive .env.example file with dummy values for all required variables
- [ ] Set up GitHub Secrets for storing sensitive information (like GATEWAY_MAC, API keys, etc.)
- [ ] Implement secure transfer of secrets from GitHub to Raspberry Pi during deployment
- [ ] Configure .gitignore to prevent .env files from being committed
- [ ] Add environment variable validation at startup to ensure all required variables are set
- [ ] Implement proper error messages that don't expose sensitive information
- [ ] Create documentation for local development environment setup without exposing real values
- [ ] Set up rotation schedule for sensitive credentials

**Acceptance Criteria for Environment Variable Security**:

- GitHub Actions workflow uses GitHub Secrets for all sensitive values
- Raspberry Pi has a secure method to store environment variables that persists across restarts
- Local development works with dummy values without requiring real credentials
- System validates environment variables on startup with helpful error messages
- No sensitive values appear in logs or error messages
- Documentation clearly explains environment variable management without exposing real values

## Phase 3: Feature Enhancements

### Milestone 3.1: Real-time Updates

**Goal**: Add WebSocket support for real-time data updates.

- [ ] Implement WebSocket server
- [ ] Add real-time data broadcasting
- [ ] Enhance frontend for live updates
- [ ] Implement reconnection handling

**Acceptance Criteria**:

- Data updates in UI without manual refresh
- Reconnects automatically when connection lost
- Performance impact is minimal

### Milestone 3.2: Data Visualization

**Goal**: Enhance UI with charts and graphs.

- [ ] Implement time-series charts for historical data
- [ ] Add sensor comparison views
- [ ] Create customizable date ranges
- [ ] Implement data export functionality

**Acceptance Criteria**:

- Charts render correctly with time-series data
- Can compare multiple sensors simultaneously
- Date range selection works correctly
- Can export data in CSV or JSON format

### Milestone 3.3: Sensor Management

**Goal**: Add sensor configuration and management.

- [ ] Create sensor naming and room assignment
- [ ] Implement alert thresholds
- [ ] Add sensor battery monitoring
- [ ] Create sensor history and statistics

**Acceptance Criteria**:

- Can assign names and locations to sensors
- Alerts trigger when thresholds exceeded
- Battery levels monitored and warnings displayed
- Historical statistics available per sensor

## Phase 4: Production Readiness

### Milestone 4.1: Security Enhancements

**Goal**: Improve application security.

- [ ] Implement proper authentication
- [ ] Add HTTPS support
- [ ] Secure sensitive configuration data
- [ ] Implement proper MQTT authentication

**Acceptance Criteria**:

- All communications properly secured
- Authentication required for sensitive operations
- Credentials stored securely
- Security scan passes with no critical issues

### Milestone 4.2: Performance Optimization

**Goal**: Optimize for Raspberry Pi resources.

- [ ] Implement data retention policies
- [ ] Optimize Docker image sizes
- [ ] Tune database performance
- [ ] Add resource usage monitoring

**Acceptance Criteria**:

- Application runs smoothly on Pi with minimal resource usage
- Database size remains manageable over time
- No memory leaks or excessive CPU usage
- Performance metrics available for monitoring

### Milestone 4.3: Documentation and Packaging

**Goal**: Finalize documentation and make deployment user-friendly.

- [ ] Complete user documentation
- [ ] Create developer documentation
- [ ] Implement easy configuration system
- [ ] Create one-command installation script

**Acceptance Criteria**:

- Documentation covers all major features
- New developers can set up environment easily
- Configuration changes don't require code edits
- Installation process documented and automated
