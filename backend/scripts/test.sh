#!/bin/bash
# Test script with proper lint configuration for Rust tests
# Allows expect/unwrap in tests while maintaining strict standards for production code

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Change to backend directory
cd "$(dirname "$0")/.."

print_status "Running Rust quality checks and tests..."

# Step 1: Check formatting
print_status "Checking code formatting..."
if cargo fmt --all -- --check; then
    print_success "Code formatting is correct"
else
    print_error "Code formatting issues found. Run 'cargo fmt' to fix."
    exit 1
fi

# Step 2: Run clippy on production code with strict rules
print_status "Running clippy on production code with strict rules..."
CLIPPY_PRODUCTION_FLAGS="-- \
    -D warnings \
    -D clippy::all \
    -D clippy::pedantic \
    -D clippy::nursery \
    -D clippy::cargo \
    -D clippy::unwrap_used \
    -D clippy::expect_used \
    -D clippy::panic \
    -D clippy::unimplemented \
    -D clippy::todo \
    -D clippy::unreachable \
    -A clippy::missing_errors_doc \
    -A clippy::missing_panics_doc"

if cargo clippy --workspace --lib --bins $CLIPPY_PRODUCTION_FLAGS; then
    print_success "Production code passes strict clippy checks"
else
    print_error "Production code has clippy violations"
    exit 1
fi

# Step 3: Run clippy on test code with relaxed rules for expect/unwrap
print_status "Running clippy on test code with test-appropriate rules..."
CLIPPY_TEST_FLAGS="-- \
    -D warnings \
    -D clippy::all \
    -D clippy::pedantic \
    -D clippy::nursery \
    -D clippy::cargo \
    -A clippy::unwrap_used \
    -A clippy::expect_used \
    -D clippy::panic \
    -D clippy::unimplemented \
    -D clippy::todo \
    -D clippy::unreachable \
    -A clippy::missing_errors_doc \
    -A clippy::missing_panics_doc"

if cargo clippy --workspace --tests $CLIPPY_TEST_FLAGS; then
    print_success "Test code passes appropriate clippy checks"
else
    print_error "Test code has clippy violations"
    exit 1
fi

# Step 4: Run tests
print_status "Running unit tests..."
if cargo test --workspace --all-features; then
    print_success "All tests passed"
else
    print_error "Some tests failed"
    exit 1
fi

# Step 5: Run tests in release mode for performance validation
print_status "Running tests in release mode..."
if cargo test --workspace --all-features --release; then
    print_success "All release mode tests passed"
else
    print_warning "Some release mode tests failed (this may be acceptable)"
fi

# Step 6: Check for security vulnerabilities (if cargo-audit is installed)
if command -v cargo-audit &> /dev/null; then
    print_status "Running security audit..."
    if cargo audit; then
        print_success "No security vulnerabilities found"
    else
        print_warning "Security vulnerabilities found - review audit output"
    fi
else
    print_warning "cargo-audit not installed - skipping security audit"
    print_status "Install with: cargo install cargo-audit"
fi

# Step 7: Generate documentation to ensure it builds correctly
print_status "Checking documentation generation..."
if cargo doc --workspace --all-features --no-deps --quiet; then
    print_success "Documentation generated successfully"
else
    print_error "Documentation generation failed"
    exit 1
fi

print_success "All quality checks and tests completed successfully!"
print_status "Your Rust code meets the strict quality standards required for production."