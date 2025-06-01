# Ruuvi Home Backend Makefile - Single Source of Truth for Code Quality
# This Makefile is the ONLY way to run clippy and formatting checks
# Identical behavior for local development and CI pipeline

CARGO := cargo

.PHONY: all dev build release test test-with-db lint clippy-app clippy-test fmt fmt-check clean install help db-start db-stop db-status db-logs db-clean

# === PRIMARY TARGETS ===

# Default target - full quality check
all: lint test

# Development workflow - the main target developers should use
dev: lint test

# === CODE QUALITY - SINGLE SOURCE OF TRUTH ===

# Primary lint target - runs all quality checks
lint: fmt-check clippy-app clippy-test

# Application code clippy (strict error handling - no expect/unwrap)
clippy-app:
	@echo "🔍 Running clippy on application code (strict error handling)..."
	$(CARGO) clippy --workspace --lib --bins -- \
    	-D warnings \
    	-D clippy::pedantic \
    	-D clippy::correctness \
    	-D clippy::suspicious \
    	-D clippy::complexity \
    	-D clippy::perf \
    	-D clippy::unwrap_used \
    	-D clippy::expect_used \
    	-D clippy::panic \
    	-D clippy::unimplemented \
    	-D clippy::todo \
    	-D clippy::unreachable \
    	-D clippy::indexing_slicing \
        -A clippy::missing_errors_doc \
        -A clippy::must_use_candidate \
    	-A clippy::missing_panics_doc

# Test code clippy (allows expect/unwrap for early panic)
clippy-test:
	@echo "🔍 Running clippy on test code (allows expect/unwrap)..."
	$(CARGO) clippy --workspace --tests -- \
		-D warnings \
		-D clippy::pedantic \
		-A clippy::missing_errors_doc \
		-A clippy::must_use_candidate \
		-A clippy::expect_used \
		-A clippy::unwrap_used

# Format all code
fmt:
	@echo "🎨 Formatting all code..."
	$(CARGO) fmt --all

# Check formatting without making changes (used in CI)
fmt-check:
	@echo "🔍 Checking code formatting..."
	$(CARGO) fmt --all -- --check

# === BUILD TARGETS ===

# Development build
build:
	@echo "🔨 Building workspace..."
	$(CARGO) build --workspace

# Release build with optimizations
release:
	@echo "🚀 Building release..."
	$(CARGO) build --release --workspace

# === DATABASE MANAGEMENT ===

# Database configuration
DB_CONTAINER_NAME := ruuvi-test-timescaledb
DB_IMAGE := timescale/timescaledb:latest-pg15
DB_PORT := 5432
DB_NAME := ruuvi_home
DB_USER := ruuvi
DB_PASSWORD := ruuvi_secret
DB_URL := postgresql://$(DB_USER):$(DB_PASSWORD)@localhost:$(DB_PORT)/$(DB_NAME)

# Start TimescaleDB container for integration tests
db-start:
	@echo "🗃️  Starting TimescaleDB container..."
	@if docker ps -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		echo "📦 Container $(DB_CONTAINER_NAME) is already running"; \
	elif docker ps -a -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		echo "🔄 Starting existing container $(DB_CONTAINER_NAME)..."; \
		docker start $(DB_CONTAINER_NAME); \
	else \
		echo "🆕 Creating new container $(DB_CONTAINER_NAME)..."; \
		docker run -d \
			--name $(DB_CONTAINER_NAME) \
			-e POSTGRES_DB=$(DB_NAME) \
			-e POSTGRES_USER=$(DB_USER) \
			-e POSTGRES_PASSWORD=$(DB_PASSWORD) \
			-e POSTGRES_HOST_AUTH_METHOD=trust \
			-e TIMESCALEDB_TELEMETRY=off \
			-p $(DB_PORT):5432 \
			$(DB_IMAGE); \
	fi
	@echo "⏳ Waiting for database to be ready..."
	@for i in $$(seq 1 15); do \
		if docker exec $(DB_CONTAINER_NAME) pg_isready -U $(DB_USER) -d $(DB_NAME) > /dev/null 2>&1; then \
			break; \
		elif [ $$i -eq 15 ]; then \
			echo "❌ Database failed to start within 30 seconds"; \
			exit 1; \
		else \
			sleep 2; \
		fi; \
	done
	@echo "✅ TimescaleDB is ready at localhost:$(DB_PORT)"
	@echo "🔗 Connection URL: $(DB_URL)"

# Stop TimescaleDB container
db-stop:
	@echo "🛑 Stopping TimescaleDB container..."
	@if docker ps -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		docker stop $(DB_CONTAINER_NAME); \
		echo "✅ Container $(DB_CONTAINER_NAME) stopped"; \
	else \
		echo "📦 Container $(DB_CONTAINER_NAME) is not running"; \
	fi

# Check database container status
db-status:
	@echo "📊 Database container status:"
	@if docker ps -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		echo "✅ Container $(DB_CONTAINER_NAME) is running"; \
		docker exec $(DB_CONTAINER_NAME) pg_isready -U $(DB_USER) -d $(DB_NAME) && echo "✅ Database is accepting connections" || echo "❌ Database is not ready"; \
	elif docker ps -a -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		echo "⏹️  Container $(DB_CONTAINER_NAME) exists but is stopped"; \
	else \
		echo "❌ Container $(DB_CONTAINER_NAME) does not exist"; \
	fi

# Show database container logs
db-logs:
	@echo "📄 Database container logs:"
	@if docker ps -a -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		docker logs $(DB_CONTAINER_NAME); \
	else \
		echo "❌ Container $(DB_CONTAINER_NAME) does not exist"; \
	fi

# Clean up database container and data
db-clean:
	@echo "🧹 Cleaning up database container..."
	@if docker ps -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		docker stop $(DB_CONTAINER_NAME); \
	fi
	@if docker ps -a -q -f name=$(DB_CONTAINER_NAME) | grep -q .; then \
		docker rm $(DB_CONTAINER_NAME); \
		echo "✅ Container $(DB_CONTAINER_NAME) removed"; \
	else \
		echo "📦 Container $(DB_CONTAINER_NAME) does not exist"; \
	fi

# === TESTING ===

# Run all tests (unit tests + integration tests if database available)
test:
	@echo "🧪 Running all tests..."
	$(CARGO) test --workspace

# Run all tests with database (starts database automatically)
test-with-db: db-start
	@echo "🧪 Running all tests with TimescaleDB..."
	TEST_DATABASE_URL=$(DB_URL) $(CARGO) test --workspace
	@echo "✅ All tests completed with database"

# === MAINTENANCE ===

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	$(CARGO) clean

# Security audit
audit:
	@echo "🔒 Running security audit..."
	$(CARGO) audit

# Install binaries
install:
	@echo "📦 Installing binaries..."
	$(CARGO) install --path packages/mqtt-reader --force
	$(CARGO) install --path packages/api --force

# === HELP ===

help:
	@echo "Ruuvi Home Backend Makefile - Single Source of Truth"
	@echo "===================================================="
	@echo ""
	@echo "🎯 PRIMARY TARGETS:"
	@echo "  all              - Full quality check (lint + test)"
	@echo "  dev              - Development workflow (same as 'all')"
	@echo "  lint             - Run all code quality checks"
	@echo ""
	@echo "🔍 CODE QUALITY:"
	@echo "  clippy-app       - Clippy for application code (strict)"
	@echo "  clippy-test      - Clippy for test code (allows expect/unwrap)"
	@echo "  fmt              - Format all code"
	@echo "  fmt-check        - Check code formatting"
	@echo ""
	@echo "🔨 BUILD & TEST:"
	@echo "  build            - Development build"
	@echo "  release          - Release build"
	@echo "  test             - Run all tests (integration tests skip if no DB)"
	@echo "  test-with-db     - Run all tests with TimescaleDB (auto-starts DB)"
	@echo ""
	@echo "🗃️  DATABASE MANAGEMENT:"
	@echo "  db-start         - Start TimescaleDB container for integration tests"
	@echo "  db-stop          - Stop TimescaleDB container"
	@echo "  db-status        - Check database container status"
	@echo "  db-logs          - Show database container logs"
	@echo "  db-clean         - Remove database container and data"
	@echo ""
	@echo "🛠️  UTILITIES:"
	@echo "  clean            - Clean build artifacts"
	@echo "  audit            - Security audit"
	@echo "  install          - Install binaries"
	@echo "  help             - Show this help"
	@echo ""
	@echo "⚠️  IMPORTANT: Use 'make lint' for all quality checks!"
	@echo "   This ensures consistent behavior between local and CI."
	@echo ""
	@echo "💡 TIP: Use 'make test-with-db' for full integration testing!"
	@echo "   This automatically starts TimescaleDB and runs all tests."
