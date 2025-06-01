#!/bin/bash
# Build script for Rust services using consolidated Dockerfile
# Usage: ./build-service.sh <service-name> [tag]

set -e

SERVICE_NAME="$1"
TAG="${2:-latest}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> [tag]"
    echo "Available services: api-server, mqtt-reader"
    exit 1
fi

case "$SERVICE_NAME" in
    "api-server")
        BINARY_NAME="api"
        EXPOSE_PORT="8080"
        ;;
    "mqtt-reader")
        BINARY_NAME="mqtt_reader"
        EXPOSE_PORT=""
        ;;
    *)
        echo "Unknown service: $SERVICE_NAME"
        echo "Available services: api-server, mqtt-reader"
        exit 1
        ;;
esac

echo "Building $SERVICE_NAME (binary: $BINARY_NAME) with tag: $TAG"

docker build \
    --build-arg SERVICE_NAME="$SERVICE_NAME" \
    --build-arg BINARY_NAME="$BINARY_NAME" \
    --build-arg EXPOSE_PORT="$EXPOSE_PORT" \
    -f docker/rust-service.Dockerfile \
    -t "ruuvi-home/$SERVICE_NAME:$TAG" \
    .

echo "Successfully built ruuvi-home/$SERVICE_NAME:$TAG"
