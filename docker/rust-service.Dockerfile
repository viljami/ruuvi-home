FROM rust:1.87-slim-bullseye AS builder

ARG SERVICE_NAME
ARG BINARY_NAME=${SERVICE_NAME}

WORKDIR /usr/src/ruuvi-home

RUN apt-get update && apt-get install -y pkg-config libssl-dev binutils && rm -rf /var/lib/apt/lists/*

COPY backend/Cargo.toml ./Cargo.toml
COPY backend/packages/ ./packages/

# Build with size optimizations
ENV CARGO_PROFILE_RELEASE_LTO=true
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
ENV CARGO_PROFILE_RELEASE_PANIC=abort
RUN cargo build --release --bin ${BINARY_NAME}

# Strip debug symbols to reduce binary size
RUN strip target/release/${BINARY_NAME}

FROM gcr.io/distroless/cc-debian12

ARG SERVICE_NAME
ARG BINARY_NAME=${SERVICE_NAME}
ARG EXPOSE_PORT

WORKDIR /app

COPY --from=builder /usr/src/ruuvi-home/target/release/${BINARY_NAME} /app/

# Conditionally expose port if provided
RUN if [ -n "${EXPOSE_PORT}" ]; then echo "EXPOSE ${EXPOSE_PORT}" > /tmp/expose; fi

USER nonroot:nonroot

CMD ["./${BINARY_NAME}"]