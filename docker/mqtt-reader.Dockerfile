FROM rust:1.87-slim-bookworm AS builder

WORKDIR /usr/src/ruuvi-home

RUN for i in 1 2 3; do \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            pkg-config \
            libssl-dev \
            binutils \
            ca-certificates && \
        rm -rf /var/lib/apt/lists/* && \
        break || { \
            echo "Attempt $i failed, retrying in 5 seconds..."; \
            sleep 5; \
        } \
    done

COPY backend/Cargo.toml ./Cargo.toml
COPY backend/packages/ ./packages/

# Build with size optimizations
ENV CARGO_PROFILE_RELEASE_LTO=true
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
ENV CARGO_PROFILE_RELEASE_PANIC=abort
RUN cargo build --release --bin mqtt_reader

# Strip debug symbols to reduce binary size
RUN strip target/release/mqtt_reader

FROM gcr.io/distroless/cc-debian12

WORKDIR /app

COPY --from=builder /usr/src/ruuvi-home/target/release/mqtt_reader /app/

USER nonroot:nonroot

CMD ["./mqtt_reader"]