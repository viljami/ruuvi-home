# Rust Development Makefile with Strict Quality Standards
# Designed for Raspberry Pi development with cross-compilation support

CARGO := cargo
CROSS := cross
TARGET_AARCH64 := aarch64-unknown-linux-gnu
TARGET_X86_64 := x86_64-unknown-linux-gnu

# Strict clippy flags - deny all warnings and enable all lint groups
CLIPPY_FLAGS := -- \
	-D warnings \
	-D clippy::all \
	-D clippy::pedantic \
	-D clippy::nursery \
	-D clippy::cargo \
	-D clippy::correctness \
	-D clippy::suspicious \
	-D clippy::style \
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
	-A clippy::missing_panics_doc

# Test flags for comprehensive testing
TEST_FLAGS := --all-features --workspace

.PHONY: all dev build release test test-release clippy clippy-fix fmt fmt-check \
        clean clean-all check audit security-audit cross-aarch64 cross-x86_64 \
        install install-tools help doc doc-open

# Default target for development
all: check

# Development workflow - comprehensive checks
dev: fmt-check clippy test

# Quick development build
build:
	$(CARGO) build --workspace

# Release build with optimizations
release:
	$(CARGO) build --release --workspace

# Run tests with comprehensive flags
test:
	$(CARGO) test $(TEST_FLAGS)

# Run tests in release mode for performance validation
test-release:
	$(CARGO) test $(TEST_FLAGS) --release

# Run clippy with strict linting
clippy:
	$(CARGO) clippy --workspace --all-targets --all-features $(CLIPPY_FLAGS)

# Auto-fix clippy issues where possible
clippy-fix:
	$(CARGO) clippy --workspace --all-targets --all-features --fix --allow-dirty

# Format code
fmt:
	$(CARGO) fmt --all

# Check formatting without making changes
fmt-check:
	$(CARGO) fmt --all -- --check

# Clean build artifacts
clean:
	$(CARGO) clean

# Clean everything including target directory
clean-all:
	rm -rf target/
	$(CARGO) clean

# Comprehensive check: format, clippy, build, test
check: fmt-check clippy build test

# Audit dependencies for security vulnerabilities
audit:
	$(CARGO) audit

# Security audit with detailed output
security-audit:
	$(CARGO) audit --deny warnings

# Cross-compile for Raspberry Pi (ARM64)
cross-aarch64:
	$(CROSS) build --release --target $(TARGET_AARCH64) --workspace

# Cross-compile for x86_64 Linux
cross-x86_64:
	$(CROSS) build --release --target $(TARGET_X86_64) --workspace

# Install the binaries
install:
	$(CARGO) install --path packages/mqtt-reader --force
	$(CARGO) install --path packages/api --force

# Install development tools
install-tools:
	$(CARGO) install cargo-audit
	$(CARGO) install cross
	$(CARGO) install cargo-watch
	$(CARGO) install cargo-expand
	$(CARGO) install cargo-outdated

# Generate documentation
doc:
	$(CARGO) doc --workspace --all-features --no-deps

# Generate and open documentation
doc-open:
	$(CARGO) doc --workspace --all-features --no-deps --open

# Watch for changes and run checks
watch:
	$(CARGO) watch -x "fmt" -x "clippy --workspace --all-targets --all-features $(CLIPPY_FLAGS)" -x "test $(TEST_FLAGS)"

# Help target
help:
	@echo "Rust Development Makefile - Strict Quality Standards"
	@echo ""
	@echo "Development Commands:"
	@echo "  dev              - Run development workflow (fmt-check + clippy + test)"
	@echo "  check            - Comprehensive check (fmt-check + clippy + build + test)"
	@echo "  build            - Build all workspace packages"
	@echo "  release          - Build with release optimizations"
	@echo ""
	@echo "Quality Assurance:"
	@echo "  clippy           - Run clippy with strict linting"
	@echo "  clippy-fix       - Auto-fix clippy issues"
	@echo "  fmt              - Format code"
	@echo "  fmt-check        - Check code formatting"
	@echo "  test             - Run all tests"
	@echo "  test-release     - Run tests in release mode"
	@echo ""
	@echo "Security & Maintenance:"
	@echo "  audit            - Audit dependencies"
	@echo "  security-audit   - Security audit with strict checks"
	@echo ""
	@echo "Cross-compilation:"
	@echo "  cross-aarch64    - Cross-compile for Raspberry Pi (ARM64)"
	@echo "  cross-x86_64     - Cross-compile for x86_64 Linux"
	@echo ""
	@echo "Documentation:"
	@echo "  doc              - Generate documentation"
	@echo "  doc-open         - Generate and open documentation"
	@echo ""
	@echo "Utilities:"
	@echo "  clean            - Clean build artifacts"
	@echo "  clean-all        - Clean everything including target/"
	@echo "  install          - Install binaries"
	@echo "  install-tools    - Install development tools"
	@echo "  watch            - Watch for changes and run checks"
	@echo "  help             - Show this help message"
