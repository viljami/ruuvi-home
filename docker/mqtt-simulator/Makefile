# MQTT Simulator Makefile - Single Source of Truth for Python Code Quality
# This Makefile is the ONLY way to run Python linting and formatting checks
# Identical behavior for local development and CI pipeline

PYTHON := python3
PIP := pip3

.PHONY: all dev build test lint fmt fmt-check flake8 isort-check isort-fix black-check black-fix clean install deps help

# === PRIMARY TARGETS ===

# Default target - full quality check
all: lint test

# Development workflow - the main target developers should use
dev: lint test

# === CODE QUALITY - SINGLE SOURCE OF TRUTH ===

# Primary lint target - runs all quality checks
lint: fmt-check flake8

# Format all Python code
fmt: black-fix isort-fix

# Check formatting without making changes (used in CI)
fmt-check: black-check isort-check

# Black formatting check
black-check:
	@echo "🔍 Checking Python code formatting with black..."
	$(PYTHON) -m black --check simulator.py tests/

# Black formatting fix
black-fix:
	@echo "🎨 Formatting Python code with black..."
	$(PYTHON) -m black simulator.py tests/

# Import sorting check
isort-check:
	@echo "🔍 Checking import sorting with isort..."
	$(PYTHON) -m isort --check-only --profile black simulator.py tests/

# Import sorting fix
isort-fix:
	@echo "🎨 Sorting imports with isort..."
	$(PYTHON) -m isort --profile black simulator.py tests/

# Flake8 linting
flake8:
	@echo "🔍 Running flake8 linting..."
	$(PYTHON) -m flake8 simulator.py tests/ --max-line-length=88 --extend-ignore=E203,W503

# === TESTING ===

# Run all tests
test:
	@echo "🧪 Running pytest tests..."
	$(PYTHON) -m pytest tests/ -v --cov=simulator --cov-report=term

# Run tests with coverage report
test-cov:
	@echo "🧪 Running pytest tests with coverage..."
	$(PYTHON) -m pytest tests/ -v --cov=simulator --cov-report=term --cov-report=xml

# === DEPENDENCIES ===

# Install development dependencies
deps:
	@echo "📦 Installing Python dependencies..."
	$(PIP) install -r requirements.txt
	$(PIP) install pytest pytest-cov black isort flake8

# === UTILITIES ===

# Build Docker image
build:
	@echo "🐳 Building Docker image..."
	docker build -t ruuvi-mqtt-simulator .

# Run simulator locally
run:
	@echo "🚀 Running MQTT simulator..."
	$(PYTHON) simulator.py

# Clean Python cache files
clean:
	@echo "🧹 Cleaning Python cache files..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	rm -f .coverage coverage.xml 2>/dev/null || true

# === HELP ===

help:
	@echo "MQTT Simulator Makefile - Single Source of Truth"
	@echo "==============================================="
	@echo ""
	@echo "🎯 PRIMARY TARGETS:"
	@echo "  all              - Full quality check (lint + test)"
	@echo "  dev              - Development workflow (same as 'all')"
	@echo "  lint             - Run all code quality checks"
	@echo ""
	@echo "🔍 CODE QUALITY:"
	@echo "  fmt              - Format all Python code (black + isort)"
	@echo "  fmt-check        - Check code formatting"
	@echo "  black-check      - Check Python formatting with black"
	@echo "  black-fix        - Fix Python formatting with black"
	@echo "  isort-check      - Check import sorting"
	@echo "  isort-fix        - Fix import sorting"
	@echo "  flake8           - Run flake8 linting"
	@echo ""
	@echo "🧪 TESTING:"
	@echo "  test             - Run all tests with coverage"
	@echo "  test-cov         - Run tests with detailed coverage report"
	@echo ""
	@echo "🛠️  UTILITIES:"
	@echo "  deps             - Install Python dependencies"
	@echo "  build            - Build Docker image"
	@echo "  run              - Run simulator locally"
	@echo "  clean            - Clean Python cache files"
	@echo "  help             - Show this help"
	@echo ""
	@echo "⚠️  IMPORTANT: Use 'make lint' for all quality checks!"
	@echo "   This ensures consistent behavior between local and CI."
	@echo ""
	@echo "💡 TIP: Use 'make dev' for the full development workflow!"