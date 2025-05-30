//! Ruuvi Home API Library
//!
//! This library provides the REST API for the Ruuvi Home monitoring system.
//! It includes modular handlers, configuration, and utilities for testing.

pub mod config;
pub mod handlers;
pub mod queries;
pub mod state;
pub mod utils;

// Re-export main types for convenience

use axum::{
    http::HeaderValue,
    routing::get,
    Router,
};
pub use config::Config;
pub use handlers::*;
pub use queries::*;
pub use state::AppState;
use tower_http::cors::{
    AllowOrigin,
    Any,
    CorsLayer,
};

/// Create the main application router with all routes configured
pub fn create_router(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(|origin: &HeaderValue, _| {
            origin
                .to_str()
                .map(|s| s.starts_with("http://localhost:") || s.starts_with("https://localhost:"))
                .unwrap_or(false)
        }))
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/health", get(handlers::health_check))
        .route("/api/sensors", get(handlers::get_sensors))
        .route(
            "/api/sensors/{sensor_mac}/latest",
            get(handlers::get_sensor_latest),
        )
        .route(
            "/api/sensors/{sensor_mac}/history",
            get(handlers::get_sensor_history),
        )
        .route(
            "/api/sensors/{sensor_mac}/aggregates",
            get(handlers::get_sensor_aggregates),
        )
        .route(
            "/api/sensors/{sensor_mac}/hourly",
            get(handlers::get_sensor_hourly_aggregates),
        )
        .route(
            "/api/sensors/{sensor_mac}/daily",
            get(handlers::get_sensor_daily_aggregates),
        )
        .route("/api/storage/stats", get(handlers::get_storage_stats))
        .route("/api/storage/estimate", get(handlers::get_storage_estimate))
        .layer(cors)
        .with_state(state)
}
