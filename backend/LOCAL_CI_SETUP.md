# Local CI Strictness Setup Guide

This guide helps you configure your local development environment to match the GitHub CI pipeline's strictness, preventing CI failures and ensuring code quality.

## Quick Setup

### 1. Install Nightly Rust Toolchain (Matches CI)

```bash
# Install nightly toolchain (same as CI)
rustup toolchain install nightly

# Install required components
rustup component add rustfmt clippy --toolchain nightly

# Set nightly as default for this project (optional)
cd backend
rustup override set nightly
```

### 2. Verify Installation

```bash
cd backend
rustc --version  # Should show nightly
cargo clippy --version  # Should show nightly clippy
```

## Running CI-Level Checks Locally

### Method 1: Use the Local Clippy Script (Recommended)

```bash
cd backend
./run-local-clippy.sh
```

This script runs the exact same checks as the CI pipeline.

### Method 2: Use Makefile Targets

```bash
cd backend

# Run CI-level clippy checks
make clippy-ci

# Full development workflow with CI strictness
make dev

# Comprehensive check (format + clippy + build + test)
make check
```

### Method 3: Manual Commands

```bash
cd backend

# 1. Format check (exactly like CI)
cargo fmt --check

# 2. Standard clippy with warnings as errors (exactly like CI)
cargo clippy --workspace --all-targets --all-features -- -D warnings

# 3. Strict error handling checks (no expect/unwrap in app code)
cargo clippy --workspace --all-targets --all-features -- \
    -D clippy::expect_used \
    -D clippy::unwrap_used \
    -D clippy::panic \
    -D clippy::unimplemented \
    -D clippy::todo \
    -A clippy::expect_used_in_tests \
    -A clippy::unwrap_used_in_tests

# 4. Test code checks (allowing expect/unwrap in tests)
cargo clippy --workspace --tests --all-features -- \
    -A clippy::expect_used \
    -A clippy::unwrap_used \
    -D warnings
```

## Pre-Commit Hook Setup

### Install Git Hook

```bash
cd ruuvi-home

# Copy the pre-commit hook
cp scripts/check-lints.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Or create a custom pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
cd backend
./run-local-clippy.sh
EOF
chmod +x .git/hooks/pre-commit
```

### Alternative: Use pre-commit Framework

```bash
# Install pre-commit
pip install pre-commit

# Install hooks (if .pre-commit-config.yaml exists)
pre-commit install
```

## IDE Configuration

### VS Code Settings

Add to `.vscode/settings.json`:

```json
{
    "rust-analyzer.check.command": "clippy",
    "rust-analyzer.check.extraArgs": [
        "--",
        "-D", "warnings",
        "-D", "clippy::expect_used",
        "-D", "clippy::unwrap_used",
        "-D", "clippy::panic",
        "-D", "clippy::unimplemented",
        "-D", "clippy::todo"
    ],
    "rust-analyzer.rustfmt.extraArgs": ["--check"],
    "rust-analyzer.cargo.features": "all"
}
```

### CLion/IntelliJ IDEA

1. Go to Settings → Languages & Frameworks → Rust
2. Set Toolchain to `nightly`
3. Enable "Run clippy instead of check"
4. Add clippy arguments: `-D warnings -D clippy::expect_used -D clippy::unwrap_used`

### Vim/Neovim with rust-tools

```lua
require('rust-tools').setup({
    tools = {
        runnables = {
            use_telescope = true,
        },
    },
    server = {
        settings = {
            ["rust-analyzer"] = {
                checkOnSave = {
                    command = "clippy",
                    extraArgs = { "--", "-D", "warnings" },
                },
            },
        },
    },
})
```

## Troubleshooting Common Issues

### Issue: "Clippy passes locally but fails in CI"

**Solutions:**
1. Ensure you're using nightly toolchain: `rustup show`
2. Update your toolchain: `rustup update`
3. Run the exact CI commands: `./run-local-clippy.sh`

### Issue: "expect_used errors in application code"

**Problem:** Using `.expect()` or `.unwrap()` in non-test code.

**Solution:** Replace with proper error handling:

```rust
// ❌ Bad (will fail CI)
let value = some_operation().unwrap();

// ✅ Good (CI-friendly)
let value = some_operation()
    .context("Failed to perform operation")?;
```

### Issue: "Format check failures"

**Solution:**
```bash
cd backend
cargo fmt  # Fix formatting
cargo fmt --check  # Verify it's fixed
```

### Issue: "Missing documentation warnings"

**Solution:** Add documentation to public items:

```rust
/// Processes sensor data and returns formatted output.
/// 
/// # Arguments
/// 
/// * `data` - Raw sensor data to process
/// 
/// # Errors
/// 
/// Returns error if data is malformed or processing fails.
pub fn process_data(data: &str) -> Result<String> {
    // implementation
}
```

## Environment Variables

### Optional: Set stricter defaults

Add to your shell profile (`.bashrc`, `.zshrc`, etc.):

```bash
# Make clippy stricter by default for this project
export CLIPPY_ARGS="-D warnings"

# Use nightly for this project
export RUSTUP_TOOLCHAIN=nightly
```

## Daily Workflow

### Before Starting Work

```bash
cd backend
rustup update  # Keep toolchain updated
./run-local-clippy.sh  # Verify current state
```

### Before Committing

```bash
cd backend
make dev  # Format + clippy + test
# or
./run-local-clippy.sh && cargo test
```

### Before Pushing

```bash
cd backend
make check  # Full verification
```

## Understanding CI vs Local Differences

### What CI Does That You Should Do Locally

1. **Uses nightly Rust:** More lints, matches CI exactly
2. **Treats warnings as errors:** `-D warnings` flag
3. **Runs comprehensive checks:** All targets, all features
4. **Checks formatting:** `cargo fmt --check`
5. **Validates error handling:** No unwrap/expect in app code

### Key Differences to Watch

| Aspect | Local Default | CI Pipeline | Solution |
|--------|---------------|-------------|-----------|
| Rust version | Stable | Nightly | Use nightly locally |
| Warnings | Warnings | Errors | Use `-D warnings` |
| Lint coverage | Basic | Comprehensive | Use `--all-targets --all-features` |
| Error handling | Permissive | Strict | Follow error handling rules |

## Performance Tips

### Speed Up Local Checks

```bash
# Use cargo-watch for continuous checking
cargo install cargo-watch
cargo watch -x "clippy --workspace --all-targets --all-features -- -D warnings"

# Use shared target directory
export CARGO_TARGET_DIR=/tmp/cargo-target

# Use parallel jobs
export CARGO_BUILD_JOBS=8
```

### Cache Dependencies

```bash
# Use sccache for faster builds
cargo install sccache
export RUSTC_WRAPPER=sccache
```

## Emergency Fixes

### Quick Fix Common Issues

```bash
# Auto-fix formatting
cargo fmt

# Auto-fix some clippy issues
cargo clippy --fix --allow-dirty

# Check specific package only
cargo clippy -p api -- -D warnings
```

### Temporary Overrides (Use Sparingly)

```rust
// For truly exceptional cases
#[allow(clippy::unwrap_used)]
let value = operation_that_cannot_fail().unwrap();
```

## Validation Checklist

Before pushing code, ensure:

- [ ] `cargo fmt --check` passes
- [ ] `cargo clippy --workspace --all-targets --all-features -- -D warnings` passes
- [ ] No `.unwrap()` or `.expect()` in application code
- [ ] All tests pass: `cargo test --workspace --all-features`
- [ ] Documentation is complete for public APIs
- [ ] Error handling follows project patterns

## Getting Help

### Check CI Logs

1. Go to GitHub Actions
2. Find your failed build
3. Look at "Test Backend" job
4. Compare error with local run

### Common Commands Reference

```bash
# Quick format fix
cargo fmt

# Full CI-matching check
./run-local-clippy.sh

# Check specific workspace member
cargo clippy -p mqtt-reader -- -D warnings

# Run tests with same flags as CI
cargo test --workspace --all-features

# See all available targets
cargo metadata --format-version 1 | jq '.workspace_members'
```

Remember: The goal is to catch issues early and maintain high code quality. These strict checks help prevent bugs and maintain consistency across the codebase.