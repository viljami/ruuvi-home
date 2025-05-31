# AI Validation Usage Guide

## Overview
This guide provides step-by-step instructions for AI systems to validate code changes in the Ruuvi Home project. All code MUST pass validation before submission.

**IMPORTANT**: Validation only covers application source code, tests, and configuration files. Build artifacts, dependencies, and generated files are automatically excluded.

## Quick Start

### 1. Basic Validation Command
```bash
./scripts/ai-validate.sh
```
This runs comprehensive validation across all application source code and configuration files, automatically excluding:
- `node_modules/`, `target/`, `build/`, `dist/`, `__pycache__/`
- Package lock files, build artifacts, compiled binaries
- Third-party dependencies and vendor code

### 2. Language-Specific Validation
```bash
./scripts/ai-validate.sh --rust       # Rust only
./scripts/ai-validate.sh --typescript # TypeScript only
./scripts/ai-validate.sh --python     # Python only
./scripts/ai-validate.sh --shell      # Shell scripts only
```

### 3. Configuration File Validation
```bash
./scripts/ai-validate.sh --yaml       # YAML files
./scripts/ai-validate.sh --json       # JSON files
```

## Validation Workflow for AI

### Before Any Code Changes
1. Understand current project state
2. Read milestone documentation
3. Plan validation strategy

### After Every File Edit
1. **MANDATORY**: Run appropriate validation
2. **MANDATORY**: Fix all errors before proceeding
3. **MANDATORY**: Verify with diagnostics tool

### Example Workflow: Editing Rust Code

```bash
# 1. Edit Rust file
edit_file("backend/packages/api/src/handlers.rs")

# 2. Validate immediately (excludes target/ directory automatically)
./scripts/ai-validate.sh --rust

# 3. If validation fails, fix and repeat
# 4. Only proceed when validation passes
```

**Files Validated**: Only `.rs` files in source directories, excluding `target/`, `.cargo/`, `build/`, `deps/`

## Language-Specific Commands

### Rust Projects
```bash
cd backend
cargo check --workspace --all-targets --all-features
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo fmt --check
cargo test --workspace
```

**Source Files Only**: Validates `.rs` files excluding `target/`, `.cargo/`, build artifacts

### TypeScript/React Projects
```bash
cd frontend
npx tsc --noEmit
npx eslint src --ext .js,.jsx,.ts,.tsx --max-warnings 0
npx prettier --check "src/**/*.{js,jsx,ts,tsx,json,css,scss,md}"
npm test -- --watchAll=false --coverage
```

**Source Files Only**: Validates `.ts`, `.tsx`, `.js`, `.jsx` files excluding `node_modules/`, `build/`, `dist/`, `.next/`, `coverage/`

### Python Projects
```bash
# Note: AI validation script automatically handles file filtering
./scripts/ai-validate.sh --python

# Manual commands (if needed):
python -m py_compile *.py
flake8 --max-line-length=88 --extend-ignore=E203,W503 .
black --check --diff .
isort --check-only --diff .
pytest -v
```

**Source Files Only**: Validates `.py` files excluding `__pycache__/`, `venv/`, `.venv/`, `build/`, `dist/`, `.pytest_cache/`

### Shell Scripts
```bash
# Recommended: Use validation script for automatic filtering
./scripts/ai-validate.sh --shell

# Manual commands (if needed):
bash -n script.sh
shellcheck script.sh
```

**Source Files Only**: Validates `.sh` files excluding `node_modules/`, `target/`, `build/`, `dist/`

## Common Error Patterns AI Must Detect

### Syntax Errors (In Source Code Only)
- **Orphaned XML/HTML tags**: `<div>` without `</div>` in `.tsx`, `.jsx` files
- **Mismatched brackets**: `{`, `[`, `(` without proper closing in source files
- **Invalid syntax**: Typos, missing semicolons, incorrect indentation in application code

### Logical Errors (In Application Code)
- **Duplicate functions**: Same function defined multiple times in source files
- **Circular imports**: A imports B, B imports A in application modules
- **Type mismatches**: Wrong variable types in source code
- **Missing dependencies**: Imports that don't exist in application code

### Style Violations (Application Code Standards)
- **Linting failures**: Source code doesn't meet style guidelines
- **Formatting issues**: Inconsistent spacing, indentation in source files
- **Unused variables**: Variables declared but never used in application code

**Note**: Validation ignores build artifacts, dependencies, and generated files

## Error Response Protocol

### When Validation Fails

1. **STOP**: Do not make additional changes
2. **IDENTIFY**: Read error messages carefully
3. **ISOLATE**: Determine which specific change caused the error
4. **FIX**: Address only the validation error
5. **REVALIDATE**: Run validation again
6. **REPEAT**: Until all validations pass

### Example Error Resolution

```bash
# Validation fails with linting error
./scripts/ai-validate.sh --rust
# Output: cargo clippy failed

# Check specific clippy errors
cd backend && cargo clippy

# Fix the specific issues identified
edit_file("backend/src/file.rs")

# Revalidate
./scripts/ai-validate.sh --rust
# Must pass before proceeding
```

## Integration with Development Tools

### Using diagnostics Tool
After any edit, run:
```
diagnostics("path/to/edited/file")
```
This provides IDE-level error checking.

### Pre-commit Validation
Before any commit suggestion:
```bash
./scripts/ai-validate.sh
# Must exit with code 0
```

### Continuous Validation
For multiple file changes:
1. Edit one file
2. Validate that file
3. Fix any issues
4. Proceed to next file
5. Run full validation at the end

## Validation Exit Codes

- **0**: All validations passed - safe to proceed
- **1**: Validation failed - must fix before proceeding
- **2**: Tool not available - install required tools
- **3**: File not found - check file paths

## Required Tools by Language

### Rust
- `cargo` (with clippy and rustfmt)
- Available by default in Rust projects

### TypeScript/React
- `npm` or `yarn`
- `typescript`
- `eslint`
- `prettier`

### Python
- `python3`
- `flake8`
- `black`
- `isort`
- `pytest`

### Shell
- `bash`
- `shellcheck` (recommended)

### Configuration Files
- `python3` (for YAML/JSON parsing)
- `docker-compose` (for Docker validation)

## Performance Considerations

### Fast Validation (Single File)
Use language-specific commands for individual source files:
```bash
# Rust single file (source only)
cargo check --package package-name

# TypeScript single file (source only)
npx tsc --noEmit path/to/file.ts

# Python single file (source only)
python -m py_compile path/to/file.py

# Note: AI validation script handles file filtering automatically
./scripts/ai-validate.sh --rust      # Only source .rs files
./scripts/ai-validate.sh --typescript # Only source .ts/.tsx files
./scripts/ai-validate.sh --python    # Only source .py files
```

### Full Validation (All Source Files)
Use the comprehensive script for all application source code:
```bash
./scripts/ai-validate.sh  # Validates only source code, excludes build artifacts
```

**Automatically Excluded:**
- Build directories: `target/`, `build/`, `dist/`, `out/`
- Dependencies: `node_modules/`, `__pycache__/`, `venv/`, `.venv/`
- Generated files: Coverage reports, cache directories, lock files
- IDE files: `.git/`, editor configurations

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x scripts/ai-validate.sh
   ```

2. **Tool Not Found**
   - Check if required tools are installed
   - Use project-specific tool locations
   - Install missing dependencies

3. **Path Issues**
   - Always run from project root
   - Use relative paths
   - Check current working directory

4. **Environment Issues**
   - Ensure virtual environments are activated
   - Check PATH variables
   - Verify tool versions

### Debug Mode
For detailed output:
```bash
bash -x scripts/ai-validate.sh
```

## Best Practices for AI

1. **Validate Early**: After every significant change to source code
2. **Validate Often**: Don't accumulate errors in application code
3. **Fix Immediately**: Don't proceed with broken source code
4. **Use Specific Tools**: Target validation to changed source files only
5. **Check Exit Codes**: Always verify command success (exit code 0)
6. **Read Error Messages**: Understand what failed in source validation
7. **Test Incrementally**: Small changes to source code, frequent validation
8. **Trust File Filtering**: Let `./scripts/ai-validate.sh` handle exclusions automatically

## Emergency Protocols

### If Validation Cannot Pass
1. Document the specific error
2. Attempt one more focused fix
3. If still failing, escalate to human
4. Do not submit broken code
5. Provide clear error description

### If Tools Are Missing
1. Attempt to install via package manager
2. Use alternative validation methods
3. Document missing dependencies
4. Request human assistance for setup

This guide ensures consistent, reliable code validation for AI-assisted development in the Ruuvi Home project.