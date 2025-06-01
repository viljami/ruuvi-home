# Ruuvi Home Backend Makefile - Single Source of Truth for Code Quality
# This Makefile is the ONLY way to run clippy and formatting checks
# Identical behavior for local development and CI pipeline

CARGO := cargo

.PHONY: all dev build release test lint clippy-app clippy-test fmt fmt-check clean install help

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

# === TESTING ===

# Run all tests
test:
	@echo "🧪 Running all tests..."
	$(CARGO) test --workspace

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
	@echo "  test             - Run all tests"
	@echo ""
	@echo "🛠️  UTILITIES:"
	@echo "  clean            - Clean build artifacts"
	@echo "  audit            - Security audit"
	@echo "  install          - Install binaries"
	@echo "  help             - Show this help"
	@echo ""
	@echo "⚠️  IMPORTANT: Use 'make lint' for all quality checks!"
	@echo "   This ensures consistent behavior between local and CI."
