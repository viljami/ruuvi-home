# Rust Coding Standards for Ruuvi Home Backend

This document defines the strict coding standards for all Rust code in the Ruuvi Home backend project. These standards are designed to ensure maximum reliability, performance, and maintainability for production deployment on Raspberry Pi hardware.

## Table of Contents

- [Core Principles](#core-principles)
- [Code Quality Requirements](#code-quality-requirements)
- [Error Handling](#error-handling)
- [Testing Standards](#testing-standards)
- [Documentation Requirements](#documentation-requirements)
- [Performance Guidelines](#performance-guidelines)
- [Dependencies and Security](#dependencies-and-security)
- [Cross-Compilation for Raspberry Pi](#cross-compilation-for-raspberry-pi)
- [Development Workflow](#development-workflow)
- [Code Review Checklist](#code-review-checklist)

## Core Principles

### 1. Reliability First

- **Zero tolerance for panics in production code**
- All error conditions must be handled explicitly
- No `unwrap()`, `expect()`, `panic!()`, `unimplemented!()`, `todo!()`, or `unreachable!()` in production code
- Exception: Tests may use `expect()` and `unwrap()` for clarity and simplicity

### 2. Performance Oriented

- Optimize for Raspberry Pi hardware constraints
- Minimize memory allocations in hot paths
- Use zero-cost abstractions where possible
- Profile and benchmark critical code paths

### 3. Maintainability

- Code must be self-documenting
- Comprehensive documentation for all public APIs
- Consistent formatting and style
- Clear separation of concerns

## Code Quality Requirements

### Clippy Configuration

All production code must pass the following clippy lints without warnings:

```toml
# Mandatory lint groups
all = "deny"
correctness = "deny"
suspicious = "deny"
style = "warn"
complexity = "warn"
perf = "warn"
pedantic = "deny"

# Specific strict lints
unwrap_used = "deny"              # Use proper error handling
expect_used = "deny"              # Use proper error handling
panic = "deny"                    # No panics in production
unimplemented = "deny"            # No placeholder code
todo = "deny"                     # No TODO items in production
unreachable = "deny"              # All paths must be reachable
indexing_slicing = "warn"         # Prefer safe alternatives
integer_arithmetic = "warn"       # Check for overflow
float_arithmetic = "warn"         # Handle floating point carefully
```

### Unsafe Code

- **Unsafe code is forbidden** (`unsafe_code = "forbid"`)
- All operations must use safe Rust
- If unsafe is absolutely necessary, it requires explicit approval and comprehensive safety documentation

### Memory Safety

- No raw pointers in application code
- Use `Box`, `Rc`, `Arc` for heap allocation when needed
- Prefer stack allocation for small, short-lived data
- Use `Vec` instead of arrays when size is dynamic

## Error Handling

### Error Types

All functions that can fail must return a `Result` type:

```rust
use anyhow::{Context, Result};
use thiserror::Error;

// For application errors, define custom error types
#[derive(Error, Debug)]
pub enum MqttReaderError {
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),
    #[error("Invalid configuration: {field}")]
    InvalidConfig { field: String },
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

// For simple error propagation, use anyhow
fn read_config() -> Result<Config> {
    std::fs::read_to_string("config.toml")
        .context("Failed to read configuration file")?;
    // ... parsing logic
}
```

### Error Propagation

- Use `?` operator for error propagation
- Add context to errors using `.context()` or `.with_context()`
- Never ignore errors - handle them explicitly or propagate them

### Logging Errors

```rust
use tracing::{error, warn, info, debug};

// Log errors before propagating
match risky_operation() {
    Ok(result) => result,
    Err(e) => {
        error!("Risky operation failed: {}", e);
        return Err(e.into());
    }
}
```

## Testing Standards

### Test Organization

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_function_name_should_describe_what_is_tested() {
        // Arrange
        let input = create_test_input();

        // Act
        let result = function_under_test(input);

        // Assert
        assert_eq!(result.expect("function should succeed"), expected_value);
    }
}
```

### Test Exception Rules

Tests are the **only place** where the following are allowed:

- `unwrap()` - for test data where failure indicates a test setup error
- `expect()` - preferred over unwrap, with descriptive messages
- `panic!()` - for test assertions where failure should stop the test

```rust
#[test]
fn test_mqtt_connection() {
    let config = Config::default();
    let client = MqttClient::new(config).expect("should create client");

    // This is acceptable in tests
    let message = client.receive().unwrap();
    assert_eq!(message.topic, "test/topic");
}
```

### Integration Tests

- Place integration tests in `tests/` directory
- Test real-world scenarios end-to-end
- Use test containers for external dependencies when possible

### Property-Based Testing

For complex logic, consider property-based testing:

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_decode_ruuvi_data(data in any::<Vec<u8>>()) {
        // Property: decoder should never panic
        let result = decode_ruuvi_data(&data);
        // Test passes if no panic occurs
    }
}
```

## Documentation Requirements

### Public API Documentation

All public items must have comprehensive documentation:

````rust
/// Reads MQTT messages from a Ruuvi Gateway and decodes sensor data.
///
/// This function establishes a connection to the MQTT broker, subscribes to
/// the specified topic, and continuously processes incoming messages.
///
/// # Arguments
///
/// * `config` - Configuration containing MQTT broker details and topic
///
/// # Returns
///
/// Returns `Ok(())` on successful completion, or an error if the connection
/// fails or message processing encounters an unrecoverable error.
///
/// # Errors
///
/// This function will return an error if:
/// - Cannot connect to MQTT broker
/// - Invalid configuration provided
/// - Network connection is lost and cannot be reestablished
///
/// # Example
///
/// ```rust
/// let config = Config::new("broker.example.com", 1883, "ruuvi/data");
/// mqtt_reader::run(config).await?;
/// ```
pub async fn run(config: Config) -> Result<()> {
    // Implementation
}
````

### Private Function Documentation

Private functions should have documentation for complex logic:

```rust
/// Decodes the hex-encoded Ruuvi data format 5.
///
/// Format 5 contains temperature, humidity, pressure, and acceleration data
/// in a specific byte layout. See Ruuvi specification for details.
fn decode_format_5(data: &[u8]) -> Result<SensorReading> {
    // Implementation
}
```

## Performance Guidelines

### Memory Allocation

- Avoid allocations in hot paths
- Reuse buffers when possible
- Use `Vec::with_capacity()` when size is known
- Consider using `smallvec` for small collections

```rust
// Good: Pre-allocate with known capacity
let mut readings = Vec::with_capacity(expected_count);

// Good: Reuse buffer
let mut buffer = Vec::new();
loop {
    buffer.clear();
    read_into_buffer(&mut buffer)?;
    process_buffer(&buffer)?;
}
```

### Async Programming

- Use `tokio` for async runtime
- Prefer `async/await` over manual `Future` implementation
- Use `tokio::spawn` for concurrent tasks
- Be careful with blocking operations in async context

```rust
use tokio::time::{sleep, Duration};

async fn process_messages() -> Result<()> {
    loop {
        let message = receive_message().await?;

        // Spawn concurrent processing
        tokio::spawn(async move {
            if let Err(e) = process_message(message).await {
                error!("Failed to process message: {}", e);
            }
        });

        // Prevent tight loop
        sleep(Duration::from_millis(10)).await;
    }
}
```

### Resource Management

- Use RAII for resource cleanup
- Implement `Drop` when necessary
- Close connections explicitly when possible

## Dependencies and Security

### Dependency Selection Criteria

- Prefer widely-used, well-maintained crates
- Check security advisories regularly
- Minimize dependency tree size
- Avoid dependencies with C bindings when possible

### Security Practices

- Run `cargo audit` regularly
- Keep dependencies updated
- Use specific version constraints
- Review dependency licenses

```toml
# Good: Specific version constraints
serde = "1.0.150"
tokio = { version = "1.35", features = ["rt-multi-thread", "net", "time"] }

# Avoid: Overly broad constraints
# serde = "*"
# tokio = "1"
```

## Cross-Compilation for Raspberry Pi

### Target Configuration

- Primary target: `aarch64-unknown-linux-gnu` (64-bit Raspberry Pi)
- Secondary target: `armv7-unknown-linux-gnueabihf` (32-bit Raspberry Pi)

### Performance Considerations

- Test on actual hardware, not just cross-compilation
- Monitor CPU and memory usage
- Consider using `jemalloc` for better memory performance
- Profile with `perf` on target hardware

### Build Configuration

```toml
# Cargo.toml optimization for Raspberry Pi
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
panic = "abort"
strip = true
```

## Development Workflow

### Before Committing

1. Run `cargo fmt` to format code
2. Run `cargo clippy --workspace --all-targets --all-features` with strict flags
3. Run `cargo test --workspace --all-features`
4. Run `cargo doc --workspace --all-features --no-deps`
5. Run `cargo audit` for security check

### Continuous Integration

- All checks must pass in CI
- Cross-compilation tests for ARM64
- Integration tests with real MQTT broker
- Performance regression tests

### Code Review Requirements

- All code must be reviewed by at least one other developer
- Focus on error handling correctness
- Verify no unwrap/expect in production code
- Check performance implications
- Ensure documentation completeness

## Code Review Checklist

### Functionality

- [ ] Code solves the intended problem
- [ ] All edge cases are handled
- [ ] Error conditions are properly managed
- [ ] No panics possible in production code paths

### Quality

- [ ] No `unwrap()`, `expect()`, `panic!()` in production code
- [ ] All `Result` types are handled appropriately
- [ ] Error messages are descriptive and actionable
- [ ] Logging is appropriate for the operation level

### Performance

- [ ] No unnecessary allocations in hot paths
- [ ] Async code doesn't block inappropriately
- [ ] Resource usage is reasonable for Raspberry Pi

### Documentation

- [ ] Public APIs are fully documented
- [ ] Complex algorithms have explanatory comments
- [ ] Examples are provided for non-trivial functions
- [ ] Error conditions are documented

### Testing

- [ ] Unit tests cover main functionality
- [ ] Edge cases are tested
- [ ] Error conditions are tested
- [ ] Integration tests exist for public APIs

### Security

- [ ] No hardcoded secrets or credentials
- [ ] Input validation is performed
- [ ] Dependencies are justified and secure
- [ ] No unsafe code without explicit approval

## Enforcement

These standards are enforced through:

1. **Automated tooling**: Clippy, rustfmt, and custom CI checks
2. **Code review process**: Mandatory review before merging
3. **Testing requirements**: All tests must pass
4. **Documentation checks**: Missing documentation fails CI

Non-compliance with these standards will result in rejected pull requests and required remediation before code can be merged.

---

**Remember**: These standards exist to ensure the reliability and performance required for production deployment on Raspberry Pi hardware. When in doubt, err on the side of being more strict rather than more permissive.
