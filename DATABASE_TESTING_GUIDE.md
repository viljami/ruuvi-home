# Database Testing Guide for Ruuvi Home

## Overview

This guide explains how to set up PostgreSQL databases for integration testing in different environments: local development, CI/CD pipelines, and Docker containers.

## Table of Contents

- [Local Development Setup](#local-development-setup)
- [CI/CD Pipeline Configuration](#cicd-pipeline-configuration)
- [Docker Testing Environment](#docker-testing-environment)
- [Environment Variables](#environment-variables)
- [Running Tests](#running-tests)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Local Development Setup

### Option 1: Local PostgreSQL Installation

1. **Install PostgreSQL with TimescaleDB**:
   ```bash
   # macOS with Homebrew
   brew install postgresql timescaledb
   
   # Ubuntu/Debian
   sudo apt-get install postgresql postgresql-contrib
   # Follow TimescaleDB installation guide for your OS
   ```

2. **Create Test Database**:
   ```bash
   createdb ruuvi_home
   psql ruuvi_home -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"
   ```

3. **Set Environment Variable**:
   ```bash
   export TEST_DATABASE_URL="postgresql://username:password@localhost:5432/ruuvi_home"
   ```

### Option 2: Docker PostgreSQL

1. **Start PostgreSQL Container**:
   ```bash
   docker run -d \
     --name ruuvi-test-postgres \
     -e POSTGRES_DB=ruuvi_home \
     -e POSTGRES_USER=ruuvi \
     -e POSTGRES_PASSWORD=ruuvi_secret \
     -p 5432:5432 \
     timescale/timescaledb:latest-pg15
   ```

2. **Set Environment Variable**:
   ```bash
   export TEST_DATABASE_URL="postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home"
   ```

## CI/CD Pipeline Configuration

### GitHub Actions Setup

The CI/CD pipeline uses PostgreSQL service containers to provide databases for integration tests. This is configured in `.github/workflows/ci-cd.yml`:

```yaml
services:
  postgres:
    image: timescale/timescaledb:latest-pg15
    env:
      POSTGRES_DB: ruuvi_home
      POSTGRES_USER: ruuvi
      POSTGRES_PASSWORD: ruuvi_secret
      POSTGRES_HOST_AUTH_METHOD: trust
      TIMESCALEDB_TELEMETRY: 'off'
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5
    ports:
      - 5432:5432
```

### Environment Variables in CI

The pipeline sets the `TEST_DATABASE_URL` environment variable:

```yaml
env:
  TEST_DATABASE_URL: postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home
```

### Service Health Checks

The PostgreSQL service includes health checks to ensure the database is ready before tests run:
- Health command: `pg_isready`
- Check interval: 10 seconds
- Timeout: 5 seconds
- Retries: 5 attempts

## Docker Testing Environment

### Using Docker Compose for Testing

The project includes `docker-compose-test.yaml` for running tests with all dependencies:

```bash
# Start test environment
docker-compose -f docker-compose-test.yaml up -d

# Run tests
docker-compose -f docker-compose-test.yaml run --rm mqtt-simulator-tests

# Cleanup
docker-compose -f docker-compose-test.yaml down -v
```

### Manual Database Container

For standalone testing:

```bash
# Start TimescaleDB container
docker run -d \
  --name ruuvi-timescaledb-test \
  -e POSTGRES_DB=ruuvi_home \
  -e POSTGRES_USER=ruuvi \
  -e POSTGRES_PASSWORD=ruuvi_secret \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -p 5432:5432 \
  timescale/timescaledb:latest-pg15

# Wait for startup
sleep 10

# Run backend tests
cd backend && make test

# Cleanup
docker stop ruuvi-timescaledb-test
docker rm ruuvi-timescaledb-test
```

## Environment Variables

### Supported Variables

The test system checks for database URLs in this order:

1. `TEST_DATABASE_URL` - Explicitly for testing
2. `DATABASE_URL` - General database connection
3. Default fallback: `postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home`

### Setting Variables

**Local Development**:
```bash
# Temporary (current session)
export TEST_DATABASE_URL="postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home"

# Permanent (add to ~/.bashrc, ~/.zshrc, etc.)
echo 'export TEST_DATABASE_URL="postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home"' >> ~/.bashrc
```

**CI/CD Pipeline**:
Set in workflow file or repository secrets.

**Docker**:
```bash
docker run -e TEST_DATABASE_URL="postgresql://..." your-test-container
```

## Running Tests

### Backend Integration Tests

Using the Makefile (recommended):
```bash
cd backend
make test
```

Direct cargo command:
```bash
cd backend
cargo test --workspace
```

Specific integration tests only:
```bash
cd backend
cargo test --package postgres-store --test integration_tests
```

### Test Behavior

**With Database Available**:
- All integration tests run
- Database schema is created automatically
- Each test gets a unique temporary database
- Automatic cleanup after each test

**Without Database Available**:
- Integration tests are skipped gracefully
- Unit tests continue to run normally
- No failures due to missing database

### Test Output Examples

**Successful Integration Test**:
```
Running tests/integration_tests.rs
running 12 tests
test test_database_connection ... ok
test test_insert_and_retrieve_event ... ok
test test_get_active_sensors ... ok
...
test result: ok. 12 passed; 0 failed; 0 ignored
```

**Skipped Integration Tests**:
```
Running tests/integration_tests.rs
running 12 tests
Skipping test: No database available
Skipping test: No database available
...
test result: ok. 0 passed; 0 failed; 12 ignored
```

## Troubleshooting

### Common Issues

**1. Connection Refused**
```
Error: Failed to connect to test database: Connection refused
```
Solutions:
- Ensure PostgreSQL is running
- Check port 5432 is not blocked
- Verify connection string is correct

**2. Database Does Not Exist**
```
Error: database "ruuvi_home" does not exist
```
Solutions:
- Create the database: `createdb ruuvi_home`
- Use correct database name in connection string
- Check PostgreSQL user permissions

**3. Authentication Failed**
```
Error: authentication failed for user "ruuvi"
```
Solutions:
- Verify username and password
- Check PostgreSQL authentication settings
- For local development, consider using `trust` authentication

**4. TimescaleDB Extension Missing**
```
Error: extension "timescaledb" is not available
```
Solutions:
- Install TimescaleDB extension
- Use `timescale/timescaledb` Docker image
- Extension will be created automatically by test setup

### Debug Commands

**Check PostgreSQL Status**:
```bash
# macOS
brew services list | grep postgresql

# Linux
systemctl status postgresql

# Docker
docker ps | grep postgres
```

**Test Database Connection**:
```bash
psql "postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home" -c "SELECT 1;"
```

**View PostgreSQL Logs**:
```bash
# Docker container
docker logs ruuvi-test-postgres

# Local installation (varies by OS)
tail -f /usr/local/var/log/postgres.log
```

### Performance Issues

**Slow Test Startup**:
- Use connection pooling
- Reduce health check intervals
- Use faster disk storage for Docker volumes

**Memory Issues**:
- Limit PostgreSQL memory usage
- Use smaller test datasets
- Clean up test databases promptly

## Best Practices

### Test Database Management

1. **Isolation**: Each test uses a unique database name
2. **Cleanup**: Databases are automatically dropped after tests
3. **Schema**: Tables and extensions are created per test
4. **Data**: Use minimal test data for faster execution

### CI/CD Optimization

1. **Caching**: Use Rust dependency caching
2. **Parallelization**: Run different test suites in parallel
3. **Health Checks**: Wait for database readiness
4. **Timeouts**: Set appropriate timeouts for database operations

### Local Development

1. **Environment**: Use `.env` files for local configuration
2. **Docker**: Prefer Docker for consistent environments
3. **Persistence**: Use volumes for development databases
4. **Cleanup**: Regular cleanup of test databases

### Security Considerations

1. **Credentials**: Use environment variables, never hardcode
2. **Network**: Limit database access to necessary services
3. **Cleanup**: Ensure test databases are cleaned up
4. **Secrets**: Use GitHub secrets for CI/CD credentials

## Database Schema

### Automatic Schema Creation

The test system automatically creates:

1. **TimescaleDB Extension**: `CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE`
2. **Main Table**: `sensor_data` with all required columns
3. **Hypertable**: TimescaleDB hypertable for time-series data
4. **Indexes**: Optimized indexes for query performance
5. **Constraints**: Data validation constraints

### Schema Details

```sql
CREATE TABLE sensor_data (
    sensor_mac VARCHAR(17) NOT NULL,
    gateway_mac VARCHAR(17) NOT NULL,
    temperature DOUBLE PRECISION NOT NULL,
    humidity DOUBLE PRECISION NOT NULL,
    pressure DOUBLE PRECISION NOT NULL,
    battery BIGINT NOT NULL,
    tx_power BIGINT NOT NULL,
    movement_counter BIGINT NOT NULL,
    measurement_sequence_number BIGINT NOT NULL,
    acceleration DOUBLE PRECISION NOT NULL,
    acceleration_x BIGINT NOT NULL,
    acceleration_y BIGINT NOT NULL,
    acceleration_z BIGINT NOT NULL,
    rssi BIGINT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## Support and Resources

### Documentation Links

- [TimescaleDB Documentation](https://docs.timescale.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [GitHub Actions Services](https://docs.github.com/en/actions/using-containerized-services)

### Project-Specific Files

- `backend/packages/postgres-store/src/lib.rs` - Database implementation
- `backend/packages/postgres-store/tests/utils/mod.rs` - Test utilities
- `backend/packages/postgres-store/tests/integration_tests.rs` - Integration tests
- `.github/workflows/ci-cd.yml` - CI/CD configuration

### Getting Help

1. Check the troubleshooting section above
2. Review test logs for specific error messages
3. Verify environment variables are set correctly
4. Ensure PostgreSQL service is running and accessible
5. Check network connectivity and firewall settings

For project-specific issues, refer to the main README.md and project documentation.