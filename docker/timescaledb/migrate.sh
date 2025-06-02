#!/bin/bash

set -euo pipefail

# Migration runner for TimescaleDB
# This script runs all pending database migrations

# Configuration
PGUSER="${POSTGRES_USER:-ruuvi}"
PGDATABASE="${POSTGRES_DB:-ruuvi_home}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
MIGRATIONS_DIR="/migrations"
MAX_RETRIES=30
RETRY_DELAY=2

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[MIGRATE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[MIGRATE]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[MIGRATE]${NC} $1"
}

log_error() {
    echo -e "${RED}[MIGRATE]${NC} $1"
}

# Wait for database to be ready
wait_for_database() {
    local attempt=1

    log_info "Waiting for database to be ready..."

    while [[ $attempt -le $MAX_RETRIES ]]; do
        if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; then
            log_success "Database is ready"
            return 0
        fi

        log_info "Database not ready, attempt $attempt/$MAX_RETRIES (waiting ${RETRY_DELAY}s)"
        sleep $RETRY_DELAY
        ((attempt++))
    done

    log_error "Database failed to become ready after $MAX_RETRIES attempts"
    return 1
}

# Check if database connection works
test_database_connection() {
    log_info "Testing database connection..."

    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "Database connection successful"
        return 0
    else
        log_error "Database connection failed"
        return 1
    fi
}

# Create schema_migrations table if it doesn't exist
ensure_migrations_table() {
    log_info "Ensuring schema_migrations table exists..."

    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 << 'EOF'
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(20) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_schema_migrations_applied_at ON schema_migrations(applied_at);

INSERT INTO schema_migrations (version, description, applied_at)
SELECT '00000000000000', 'Initialize migration system', NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM schema_migrations WHERE version = '00000000000000'
);
EOF

    log_success "Schema migrations table ready"
}

# Get list of applied migrations
get_applied_migrations() {
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SELECT version FROM schema_migrations ORDER BY version;" | tr -d ' '
}

# Get list of available migration files
get_available_migrations() {
    if [[ -d "$MIGRATIONS_DIR" ]]; then
        find "$MIGRATIONS_DIR" -name "*.sql" -type f | sort | while read -r file; do
            basename "$file" .sql | cut -d'_' -f1
        done
    fi
}

# Check if migration is already applied
is_migration_applied() {
    local version="$1"
    local applied_migrations
    applied_migrations=$(get_applied_migrations)

    echo "$applied_migrations" | grep -q "^${version}$"
}

# Apply a single migration
apply_migration() {
    local migration_file="$1"
    local version
    version=$(basename "$migration_file" .sql | cut -d'_' -f1)
    local description
    description=$(basename "$migration_file" .sql | cut -d'_' -f2- | tr '_' ' ')

    log_info "Applying migration: $version ($description)"

    # Run the migration in a transaction
    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -f "$migration_file"; then
        log_success "Migration $version applied successfully"
        return 0
    else
        log_error "Migration $version failed"
        return 1
    fi
}

# Run all pending migrations
run_migrations() {
    local migrations_applied=0
    local migrations_skipped=0
    local migration_files

    log_info "Starting migration process..."

    if [[ ! -d "$MIGRATIONS_DIR" ]]; then
        log_warning "Migrations directory not found: $MIGRATIONS_DIR"
        return 0
    fi

    # Get all migration files sorted by version
    mapfile -t migration_files < <(find "$MIGRATIONS_DIR" -name "*.sql" -type f | sort)

    if [[ ${#migration_files[@]} -eq 0 ]]; then
        log_info "No migration files found"
        return 0
    fi

    log_info "Found ${#migration_files[@]} migration file(s)"

    for migration_file in "${migration_files[@]}"; do
        local version
        version=$(basename "$migration_file" .sql | cut -d'_' -f1)

        if is_migration_applied "$version"; then
            log_info "Migration $version already applied, skipping"
            ((migrations_skipped++))
        else
            if apply_migration "$migration_file"; then
                ((migrations_applied++))
            else
                log_error "Failed to apply migration $version, stopping"
                return 1
            fi
        fi
    done

    log_success "Migration process completed"
    log_info "Applied: $migrations_applied, Skipped: $migrations_skipped"

    # Show current migration status
    show_migration_status
}

# Show current migration status
show_migration_status() {
    log_info "Current migration status:"

    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "
SELECT
    version,
    description,
    applied_at
FROM schema_migrations
ORDER BY version DESC
LIMIT 10;
"
}

# Validate migrations (check for naming issues, etc.)
validate_migrations() {
    local validation_errors=0

    log_info "Validating migration files..."

    if [[ ! -d "$MIGRATIONS_DIR" ]]; then
        return 0
    fi

    # Check for naming convention
    for file in "$MIGRATIONS_DIR"/*.sql; do
        [[ -f "$file" ]] || continue

        local filename
        filename=$(basename "$file")

        # Check if filename follows YYYYMMDDHHMMSS_description.sql pattern
        if [[ ! "$filename" =~ ^[0-9]{14}_[a-zA-Z0-9_]+\.sql$ ]]; then
            log_warning "Migration file doesn't follow naming convention: $filename"
            log_warning "Expected format: YYYYMMDDHHMMSS_description.sql"
            ((validation_errors++))
        fi
    done

    if [[ $validation_errors -eq 0 ]]; then
        log_success "All migration files validated successfully"
    else
        log_warning "Found $validation_errors validation issue(s)"
    fi

    return $validation_errors
}

# Main function
main() {
    local start_time
    start_time=$(date +%s)

    log_info "TimescaleDB Migration Runner starting..."
    log_info "Database: $PGDATABASE"
    log_info "User: $PGUSER"
    log_info "Host: $PGHOST:$PGPORT"
    log_info "Migrations directory: $MIGRATIONS_DIR"

    # Wait for database
    if ! wait_for_database; then
        exit 1
    fi

    # Test connection
    if ! test_database_connection; then
        exit 1
    fi

    # Validate migrations
    validate_migrations

    # Ensure migrations table exists
    if ! ensure_migrations_table; then
        log_error "Failed to create schema_migrations table"
        exit 1
    fi

    # Run migrations
    if ! run_migrations; then
        log_error "Migration process failed"
        exit 1
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_success "Migration runner completed successfully in ${duration}s"
}

# Handle script arguments
case "${1:-}" in
    "validate")
        validate_migrations
        exit $?
        ;;
    "status")
        wait_for_database && test_database_connection && show_migration_status
        exit $?
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  Run all pending migrations"
        echo "  validate   Validate migration files"
        echo "  status     Show current migration status"
        echo "  help       Show this help message"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
