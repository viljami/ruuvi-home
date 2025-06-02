# Build stage
FROM rust:1.75 as builder

WORKDIR /app

# Copy workspace files
COPY backend/Cargo.toml backend/Cargo.lock ./
COPY backend/packages ./packages

# Build only the user-service package
RUN cargo build --release --package user-service

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd --create-home --shell /bin/bash app

# Create app directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/target/release/user-service ./user-service

# Change ownership to app user
RUN chown -R app:app /app
USER app

# Expose port
EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3001/healthz || exit 1

# Run the service
CMD ["./user-service"]
