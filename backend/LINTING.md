# Rust Linting Rules and Guidelines

## Overview

This document outlines the linting rules and code quality standards for the Ruuvi Home backend Rust code. Our linting strategy enforces strict error handling in application code while allowing flexibility in test code.

## Core Principles

### 🚫 Forbidden in Application Code
- `unwrap()` - Can cause panics in production
- `expect()` - Can cause panics in production  
- `panic!()` - Should never happen in production
- `unimplemented!()` - Indicates incomplete code
- `todo!()` - Indicates incomplete code

### ✅ Allowed in Test Code
- `unwrap()` - Tests should fail fast and clearly
- `expect()` - Tests can use descriptive panic messages
- `panic!()` - Sometimes useful for test assertions

## Configuration

### Workspace Level (Cargo.toml)
```toml
[workspace.lints.clippy]
# These are "warn" at workspace level to allow in tests
unwrap_used = "warn"
expect_used = "warn"
panic = "deny"
unimplemented = "deny"
todo = "deny"
```

### Crate Level (lib.rs/main.rs)
```rust
// Enforce strict rules in application code, allow in tests
#![cfg_attr(not(test), deny(clippy::expect_used, clippy::unwrap_used))]
#![cfg_attr(not(test), deny(clippy::panic))]
```

## Running Lint Checks

### Full Lint Check
```bash
./scripts/check-lints.sh
```

This comprehensive script checks:
- Code formatting with `cargo fmt`
- Standard clippy lints
- Application code for forbidden patterns
- Test code permissions
- Provides detailed violation reports

### Quick Local Check
```bash
cd backend
cargo clippy --workspace --all-targets --all-features -- -D warnings
```

### Format Check
```bash
cd backend
cargo fmt --check
```

### Auto-fix Formatting
```bash
cd backend
cargo fmt
```

## Pre-commit Hooks

Set up pre-commit hooks to catch issues early:

```bash
# Copy the pre-commit hook
cp scripts/pre-commit-hook.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

The pre-commit hook will:
- Check formatting on staged Rust files
- Run basic clippy checks
- Scan for forbidden patterns in staged code
- Provide quick feedback before commits

## Examples

### ❌ Bad: Application Code
```rust
// DON'T: These will fail CI
fn process_data(input: &str) -> String {
    let parsed = input.parse::<i32>().unwrap();  // ❌ Panic risk
    let result = calculate(parsed).expect("calculation failed");  // ❌ Panic risk
    result.to_string()
}
```

### ✅ Good: Application Code
```rust
use anyhow::{Context, Result};

// DO: Proper error handling
fn process_data(input: &str) -> Result<String> {
    let parsed = input.parse::<i32>()
        .context("Failed to parse input as integer")?;
    let result = calculate(parsed)
        .context("Calculation failed")?;
    Ok(result.to_string())
}
```

### ✅ Good: Test Code
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_data() {
        // OK: Tests can use unwrap/expect
        let result = process_data("42").unwrap();
        assert_eq!(result, "84");
        
        // OK: Descriptive expects in tests
        let config = Config::from_env().expect("Test config should be valid");
    }
}
```

## Error Handling Patterns

### Recommended Error Types
- `anyhow::Result<T>` for application errors
- `thiserror::Error` for custom error types
- `Result<T, E>` with specific error types for library APIs

### Recommended Patterns
```rust
// Pattern 1: Context for better error messages
fn read_config() -> Result<Config> {
    std::fs::read_to_string("config.toml")
        .context("Failed to read config file")?;
    // ...
}

// Pattern 2: Map errors appropriately
fn parse_value(s: &str) -> Result<i32, ValueError> {
    s.parse()
        .map_err(|_| ValueError::InvalidFormat(s.to_string()))
}

// Pattern 3: Early returns with ?
fn complex_operation() -> Result<Output> {
    let step1 = first_step()?;
    let step2 = second_step(step1)?;
    finalize(step2)
}
```

## CI/CD Integration

The CI pipeline runs comprehensive lint checks:

1. **Format Check**: Ensures consistent code style
2. **Standard Clippy**: Catches common issues and performance problems
3. **Application Code Scan**: Ensures no forbidden patterns
4. **Test Code Validation**: Verifies tests can use expect/unwrap

### Pipeline Failure Scenarios
- Any clippy warnings in application code
- Formatting inconsistencies
- Use of `unwrap()`/`expect()` in non-test code
- Use of `panic!()`/`todo!()`/`unimplemented!()` anywhere

## Troubleshooting

### Common Issues

**"Found .unwrap() in application code"**
- Solution: Replace with proper error handling using `?`, `map_err()`, or `context()`

**"Clippy warnings in CI but not locally"**
- Solution: Ensure you're running the same clippy version (`cargo clippy --version`)
- Update Rust toolchain: `rustup update`

**"Code formatting failure"**
- Solution: Run `cargo fmt` before committing

### Overrides (Use Sparingly)
If you absolutely must use `unwrap()` in application code:
```rust
// Only for cases where panic is actually desired
let value = some_operation()
    .unwrap(); // Allow: This operation cannot fail due to X, Y, Z
```

Add a comment explaining why the panic is safe and use `#[allow(clippy::unwrap_used)]` for the specific line.

## Benefits

### Why These Rules Matter
- **Reliability**: Prevent runtime panics in production
- **Maintainability**: Force explicit error handling
- **Debugging**: Better error messages with context
- **Testing**: Allow fast failure in tests for quick feedback

### Performance Considerations
- `Result<T, E>` has zero-cost abstractions
- `?` operator is optimized by the compiler
- Error handling doesn't impact happy-path performance

## Resources

- [Rust Error Handling Book](https://doc.rust-lang.org/book/ch09-00-error-handling.html)
- [anyhow Documentation](https://docs.rs/anyhow/)
- [thiserror Documentation](https://docs.rs/thiserror/)
- [Clippy Lints Reference](https://rust-lang.github.io/rust-clippy/master/)

---

**Remember**: These rules help us build robust, maintainable software. When in doubt, prefer explicit error handling over shortcuts!