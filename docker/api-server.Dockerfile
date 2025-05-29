FROM rust:1.87-slim-bullseye AS builder

WORKDIR /usr/src/ruuvi-home

RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

COPY backend/Cargo.toml ./Cargo.toml
COPY backend/packages/ ./packages/

RUN cargo build --release --bin api

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /usr/src/ruuvi-home/target/release/api /app/

EXPOSE 8080

CMD ["./api"]
