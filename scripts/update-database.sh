#!/bin/bash

set -euo pipefail

# Production Database Update Script for Ruuvi Home
# Safely applies database migrations during deployments
# Version: 1.0.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_ROOT/backups/database"
LOG_FILE="$PROJECT_ROOT/logs/database-update.log"

# Configuration
DB_CONTAINER="ruuvi-timescaledb"
DB_USER="ruuvi"
DB_NAME="ruuvi_home"
COMPOSE_FILE="docker-compose.production.yaml"
MAX_BACKUP_AGE_DAYS=30
MIGRATION_TIMEOUT=300
BACKUP_TIMEOUT=600

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${PURPLE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"

    log "=== Database Update Started ==="
    log "Project: $PROJECT_ROOT"
    log "Compose file: $COMPOSE_FILE"
    log "Container: $DB_CONTAINER"
    log "Database: $DB_NAME"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if running as correct user
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi

    # Check if docker compose is available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        exit 1
    fi

    # Check if compose file exists
    if [[ ! -f "$PROJECT_ROOT/$COMPOSE_FILE" ]]; then
        log_error "Compose file not found: $PROJECT_ROOT/$COMPOSE_FILE"
        exit 1
    fi

    # Check if database container is running
    if ! docker ps | grep -q "$DB_CONTAINER"; then
        log_error "Database container '$DB_CONTAINER' is not running"
        log_info "Start the database with: docker compose -f $COMPOSE_FILE up -d timescaledb"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Test database connectivity
test_database_connection() {
    log "Testing database connectivity..."

    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            log_success "Database connection successful"
            return 0
        fi

        log_info "Database not ready, attempt $attempt/$max_attempts"
        sleep 2
        ((attempt++))
    done

    log_error "Database connection failed after $max_attempts attempts"
    return 1
}

# Get current database size
get_database_size() {
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" | tr -d ' '
}

# Get current migration status
get_migration_status() {
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COALESCE(
            (SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1),
            'No migrations applied'
        );" | tr -d ' '
}

# Count pending migrations
count_pending_migrations() {
    local migration_files
    migration_files=$(find "$PROJECT_ROOT/docker/timescaledb/migrations" -name "*.sql" -type f 2>/dev/null | wc -l)

    local applied_migrations
    applied_migrations=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM schema_migrations;" 2>/dev/null | tr -d ' ' || echo "0")

    echo $((migration_files - applied_migrations))
}

# Show database status
show_database_status() {
    log "Current database status:"

    local db_size
    db_size=$(get_database_size)

    local current_migration
    current_migration=$(get_migration_status)

    local pending_count
    pending_count=$(count_pending_migrations)

    local record_count
    record_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM sensor_data;" | tr -d ' ')

    log_info "  Database size: $db_size"
    log_info "  Current migration: $current_migration"
    log_info "  Pending migrations: $pending_count"
    log_info "  Sensor records: $record_count"
}

# Create database backup
create_backup() {
    local backup_name="ruuvi_home_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="$BACKUP_DIR/${backup_name}.sql"

    log "Creating database backup: $backup_name"

    # Create backup with timeout
    if timeout "$BACKUP_TIMEOUT" docker exec "$DB_CONTAINER" pg_dump \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --verbose \
        --no-owner \
        --no-privileges \
        --create \
        --clean > "$backup_file" 2>>"$LOG_FILE"; then

        # Compress backup
        gzip "$backup_file"
        backup_file="${backup_file}.gz"

        local backup_size
        backup_size=$(du -h "$backup_file" | cut -f1)

        log_success "Backup created: $backup_file ($backup_size)"
        echo "$backup_file"
    else
        log_error "Backup creation failed"
        rm -f "$backup_file" "$backup_file.gz"
        return 1
    fi
}

# Clean old backups
cleanup_old_backups() {
    log "Cleaning up old backups (older than $MAX_BACKUP_AGE_DAYS days)..."

    local deleted_count=0

    if [[ -d "$BACKUP_DIR" ]]; then
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((deleted_count++))
        done < <(find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$MAX_BACKUP_AGE_DAYS -print0)
    fi

    if [[ $deleted_count -gt 0 ]]; then
        log_info "Deleted $deleted_count old backup(s)"
    else
        log_info "No old backups to clean up"
    fi
}

# Validate migrations before applying
validate_migrations() {
    log "Validating migration files..."

    if [[ ! -d "$PROJECT_ROOT/docker/timescaledb/migrations" ]]; then
        log_info "No migrations directory found, skipping validation"
        return 0
    fi

    local validation_errors=0

    for file in "$PROJECT_ROOT/docker/timescaledb/migrations"/*.sql; do
        [[ -f "$file" ]] || continue

        local filename
        filename=$(basename "$file")

        # Check naming convention
        if [[ ! "$filename" =~ ^[0-9]{14}_[a-zA-Z0-9_]+\.sql$ ]]; then
            log_warning "Migration file doesn't follow naming convention: $filename"
            ((validation_errors++))
        fi

        # Check for required elements
        if ! grep -q "BEGIN;" "$file"; then
            log_warning "Migration file missing transaction BEGIN: $filename"
            ((validation_errors++))
        fi

        if ! grep -q "COMMIT;" "$file"; then
            log_warning "Migration file missing transaction COMMIT: $filename"
            ((validation_errors++))
        fi
    done

    if [[ $validation_errors -eq 0 ]]; then
        log_success "All migration files validated"
    else
        log_warning "Found $validation_errors validation issue(s)"
    fi

    return $validation_errors
}

# Apply migrations
apply_migrations() {
    log "Applying database migrations..."

    local migration_start_time
    migration_start_time=$(date +%s)

    # Run migrations with timeout
    if timeout "$MIGRATION_TIMEOUT" docker exec "$DB_CONTAINER" /migrations/migrate.sh 2>>"$LOG_FILE"; then
        local migration_end_time
        migration_end_time=$(date +%s)
        local duration=$((migration_end_time - migration_start_time))

        log_success "Migrations applied successfully in ${duration}s"
        return 0
    else
        log_error "Migration process failed or timed out"
        return 1
    fi
}

# Verify database health after migration
verify_database_health() {
    log "Verifying database health after migration..."

    # Check basic connectivity
    if ! test_database_connection; then
        log_error "Database connectivity check failed"
        return 1
    fi

    # Check if sensor_data table is accessible
    if ! docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) FROM sensor_data LIMIT 1;" >/dev/null 2>&1; then
        log_error "sensor_data table is not accessible"
        return 1
    fi

    # Check if TimescaleDB extension is working
    if ! docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT * FROM timescaledb_information.hypertables LIMIT 1;" >/dev/null 2>&1; then
        log_error "TimescaleDB extension check failed"
        return 1
    fi

    # Verify migration tracking table
    if ! docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) FROM schema_migrations;" >/dev/null 2>&1; then
        log_error "Schema migrations table check failed"
        return 1
    fi

    log_success "Database health verification passed"
    return 0
}

# Restore from backup
restore_from_backup() {
    local backup_file="$1"

    log "Restoring database from backup: $backup_file"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    # Stop services that might be using the database
    log "Stopping dependent services..."
    docker compose -f "$PROJECT_ROOT/$COMPOSE_FILE" stop api-server mqtt-reader frontend

    # Restore database
    if [[ "$backup_file" == *.gz ]]; then
        if gunzip -c "$backup_file" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d postgres; then
            log_success "Database restored from backup"
        else
            log_error "Database restore failed"
            return 1
        fi
    else
        if docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d postgres < "$backup_file"; then
            log_success "Database restored from backup"
        else
            log_error "Database restore failed"
            return 1
        fi
    fi

    # Restart services
    log "Restarting services..."
    docker compose -f "$PROJECT_ROOT/$COMPOSE_FILE" up -d

    return 0
}

# Show usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run          Show what would be done without making changes"
    echo "  --backup-only      Create backup without applying migrations"
    echo "  --migrate-only     Apply migrations without creating backup"
    echo "  --status           Show current database status"
    echo "  --restore FILE     Restore database from backup file"
    echo "  --force            Skip confirmation prompts"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Full update with backup and migrations"
    echo "  $0 --status                  # Show database status"
    echo "  $0 --dry-run                 # Preview what would be done"
    echo "  $0 --backup-only             # Create backup only"
    echo "  $0 --restore backup.sql.gz   # Restore from backup"
}

# Main function
main() {
    local dry_run=false
    local backup_only=false
    local migrate_only=false
    local force=false
    local restore_file=""
    local show_status=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --backup-only)
                backup_only=true
                shift
                ;;
            --migrate-only)
                migrate_only=true
                shift
                ;;
            --status)
                show_status=true
                shift
                ;;
            --restore)
                restore_file="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Initialize
    init_logging
    check_prerequisites
    test_database_connection

    # Handle specific actions
    if [[ "$show_status" == "true" ]]; then
        show_database_status
        exit 0
    fi

    if [[ -n "$restore_file" ]]; then
        if [[ "$force" != "true" ]]; then
            echo -n "This will replace the current database. Are you sure? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log "Restore cancelled by user"
                exit 0
            fi
        fi

        restore_from_backup "$restore_file"
        exit $?
    fi

    # Show current status
    show_database_status

    # Check if migrations are needed
    local pending_migrations
    pending_migrations=$(count_pending_migrations)

    if [[ $pending_migrations -eq 0 ]]; then
        log_success "No pending migrations found"
        if [[ "$backup_only" != "true" ]]; then
            exit 0
        fi
    fi

    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        log "DRY RUN MODE - No changes will be made"

        if [[ "$backup_only" != "true" ]] && [[ "$migrate_only" != "true" ]]; then
            log "Would create database backup"
        fi

        if [[ "$migrate_only" == "true" ]] || [[ "$backup_only" != "true" ]]; then
            if [[ $pending_migrations -gt 0 ]]; then
                log "Would apply $pending_migrations pending migration(s)"
            fi
        fi

        if [[ "$backup_only" != "true" ]] && [[ "$migrate_only" != "true" ]]; then
            log "Would clean up old backups"
        fi

        exit 0
    fi

    # Confirmation prompt
    if [[ "$force" != "true" ]] && [[ $pending_migrations -gt 0 ]]; then
        echo ""
        log_warning "This will apply $pending_migrations migration(s) to the production database"
        echo -n "Continue? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "Update cancelled by user"
            exit 0
        fi
    fi

    # Create backup (unless migrate-only)
    local backup_file=""
    if [[ "$migrate_only" != "true" ]]; then
        backup_file=$(create_backup)
        if [[ $? -ne 0 ]]; then
            log_error "Backup creation failed, aborting update"
            exit 1
        fi
    fi

    # Apply migrations (unless backup-only)
    if [[ "$backup_only" != "true" ]]; then
        if [[ $pending_migrations -gt 0 ]]; then
            validate_migrations

            if apply_migrations; then
                if verify_database_health; then
                    log_success "Database update completed successfully"
                else
                    log_error "Database health check failed after migration"
                    if [[ -n "$backup_file" ]]; then
                        log_warning "Consider restoring from backup: $backup_file"
                    fi
                    exit 1
                fi
            else
                log_error "Migration failed"
                if [[ -n "$backup_file" ]]; then
                    log_warning "Consider restoring from backup: $backup_file"
                fi
                exit 1
            fi
        else
            log_info "No migrations to apply"
        fi
    fi

    # Clean up old backups
    if [[ "$migrate_only" != "true" ]]; then
        cleanup_old_backups
    fi

    # Final status
    log "=== Final Status ==="
    show_database_status

    if [[ -n "$backup_file" ]]; then
        log_info "Backup available at: $backup_file"
    fi

    log_success "Database update process completed"
}

# Change to project directory
cd "$PROJECT_ROOT"

# Run main function
main "$@"
