#!/bin/bash

set -euo pipefail

# Test script for database migration system
# This script tests the migration functionality end-to-end

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
DB_CONTAINER="ruuvi-timescaledb"
DB_USER="ruuvi"
DB_NAME="ruuvi_home"
COMPOSE_FILE="docker-compose.production.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

test_passed=0
test_failed=0

log_test() {
    local status="$1"
    local message="$2"

    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}[PASS]${NC} $message"
        ((test_passed++))
    elif [[ "$status" == "FAIL" ]]; then
        echo -e "${RED}[FAIL]${NC} $message"
        ((test_failed++))
    elif [[ "$status" == "INFO" ]]; then
        echo -e "${BLUE}[INFO]${NC} $message"
    else
        echo -e "${YELLOW}[WARN]${NC} $message"
    fi
}

# Test database connectivity
test_database_connection() {
    log_test "INFO" "Testing database connectivity..."

    if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
        log_test "PASS" "Database connection successful"
    else
        log_test "FAIL" "Database connection failed"
        return 1
    fi
}

# Test migration table exists
test_migration_table() {
    log_test "INFO" "Testing schema_migrations table..."

    if docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) FROM schema_migrations;" >/dev/null 2>&1; then
        log_test "PASS" "schema_migrations table exists and accessible"
    else
        log_test "FAIL" "schema_migrations table not found or not accessible"
        return 1
    fi
}

# Test migration script exists
test_migration_script() {
    log_test "INFO" "Testing migration script..."

    if docker exec "$DB_CONTAINER" test -f /migrations/migrate.sh; then
        log_test "PASS" "Migration script found in container"
    else
        log_test "FAIL" "Migration script not found in container"
        return 1
    fi

    if docker exec "$DB_CONTAINER" test -x /migrations/migrate.sh; then
        log_test "PASS" "Migration script is executable"
    else
        log_test "FAIL" "Migration script is not executable"
        return 1
    fi
}

# Test migrations directory
test_migrations_directory() {
    log_test "INFO" "Testing migrations directory..."

    if docker exec "$DB_CONTAINER" test -d /migrations; then
        log_test "PASS" "Migrations directory exists in container"
    else
        log_test "FAIL" "Migrations directory not found in container"
        return 1
    fi

    local migration_count
    migration_count=$(docker exec "$DB_CONTAINER" find /migrations -name "*.sql" | wc -l)

    if [[ $migration_count -gt 0 ]]; then
        log_test "PASS" "Found $migration_count migration file(s)"
    else
        log_test "WARN" "No migration files found"
    fi
}

# Test running migrations
test_run_migrations() {
    log_test "INFO" "Testing migration execution..."

    local before_count
    before_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM schema_migrations;" | tr -d ' ')

    if docker exec "$DB_CONTAINER" /migrations/migrate.sh >/dev/null 2>&1; then
        log_test "PASS" "Migration script executed successfully"
    else
        log_test "FAIL" "Migration script execution failed"
        return 1
    fi

    local after_count
    after_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM schema_migrations;" | tr -d ' ')

    if [[ $after_count -ge $before_count ]]; then
        log_test "PASS" "Migration count increased or stayed same ($before_count -> $after_count)"
    else
        log_test "FAIL" "Migration count decreased unexpectedly ($before_count -> $after_count)"
        return 1
    fi
}

# Test idempotent migrations
test_idempotent_migrations() {
    log_test "INFO" "Testing migration idempotency..."

    local first_count
    first_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM schema_migrations;" | tr -d ' ')

    # Run migrations again
    if docker exec "$DB_CONTAINER" /migrations/migrate.sh >/dev/null 2>&1; then
        log_test "PASS" "Second migration run successful"
    else
        log_test "FAIL" "Second migration run failed"
        return 1
    fi

    local second_count
    second_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM schema_migrations;" | tr -d ' ')

    if [[ $first_count -eq $second_count ]]; then
        log_test "PASS" "Migration count unchanged on second run (idempotent)"
    else
        log_test "FAIL" "Migration count changed on second run ($first_count -> $second_count)"
        return 1
    fi
}

# Test migration validation
test_migration_validation() {
    log_test "INFO" "Testing migration validation..."

    if docker exec "$DB_CONTAINER" /migrations/migrate.sh validate >/dev/null 2>&1; then
        log_test "PASS" "Migration validation successful"
    else
        log_test "WARN" "Migration validation found issues (non-critical)"
    fi
}

# Test migration status command
test_migration_status() {
    log_test "INFO" "Testing migration status command..."

    if docker exec "$DB_CONTAINER" /migrations/migrate.sh status >/dev/null 2>&1; then
        log_test "PASS" "Migration status command works"
    else
        log_test "FAIL" "Migration status command failed"
        return 1
    fi
}

# Test sample migration
test_sample_migration() {
    log_test "INFO" "Testing sample migration (sensor_metadata)..."

    # Check if sensor_metadata table exists (from sample migration)
    if docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) FROM sensor_metadata;" >/dev/null 2>&1; then
        log_test "PASS" "Sample migration created sensor_metadata table"
    else
        log_test "WARN" "sensor_metadata table not found (migration may not have run)"
    fi
}

# Test database functions
test_database_functions() {
    log_test "INFO" "Testing database functions..."

    # Test storage stats function
    if docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT * FROM get_storage_stats();" >/dev/null 2>&1; then
        log_test "PASS" "get_storage_stats() function works"
    else
        log_test "FAIL" "get_storage_stats() function failed"
    fi

    # Test sensor summary function
    if docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT * FROM get_sensor_summary();" >/dev/null 2>&1; then
        log_test "PASS" "get_sensor_summary() function works"
    else
        log_test "FAIL" "get_sensor_summary() function failed"
    fi
}

# Test update script
test_update_script() {
    log_test "INFO" "Testing database update script..."

    if [[ -f "$PROJECT_ROOT/scripts/update-database.sh" ]]; then
        log_test "PASS" "Database update script exists"
    else
        log_test "FAIL" "Database update script not found"
        return 1
    fi

    if [[ -x "$PROJECT_ROOT/scripts/update-database.sh" ]]; then
        log_test "PASS" "Database update script is executable"
    else
        log_test "FAIL" "Database update script is not executable"
        return 1
    fi

    # Test dry run
    if "$PROJECT_ROOT/scripts/update-database.sh" --status >/dev/null 2>&1; then
        log_test "PASS" "Database update script --status works"
    else
        log_test "FAIL" "Database update script --status failed"
    fi
}

# Main test runner
main() {
    echo "=========================================="
    echo "     Database Migration System Tests"
    echo "=========================================="
    echo ""

    cd "$PROJECT_ROOT"

    # Check if database container is running
    if ! docker ps | grep -q "$DB_CONTAINER"; then
        log_test "FAIL" "Database container '$DB_CONTAINER' is not running"
        echo ""
        echo "Start the database with:"
        echo "  docker compose -f $COMPOSE_FILE up -d timescaledb"
        exit 1
    fi

    # Run tests
    test_database_connection || true
    test_migration_table || true
    test_migration_script || true
    test_migrations_directory || true
    test_run_migrations || true
    test_idempotent_migrations || true
    test_migration_validation || true
    test_migration_status || true
    test_sample_migration || true
    test_database_functions || true
    test_update_script || true

    # Summary
    echo ""
    echo "=========================================="
    echo "              Test Summary"
    echo "=========================================="
    echo -e "Passed: ${GREEN}$test_passed${NC}"
    echo -e "Failed: ${RED}$test_failed${NC}"
    echo -e "Total:  $((test_passed + test_failed))"
    echo ""

    if [[ $test_failed -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! Migration system is working correctly.${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please check the migration system configuration.${NC}"
        exit 1
    fi
}

main "$@"
