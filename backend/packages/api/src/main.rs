//! Ruuvi Home API Server
//!
//! Main entry point for the REST API server that provides access to Ruuvi
//! sensor data.

use anyhow::Result;
// Import our modular API library
use api::{
    create_router,
    AppState,
    Config,
};
use tokio::net::TcpListener;
use tracing::info;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let config = Config::from_env()?;
    info!("Starting API server on port {}", config.api_port);
    info!("Database URL: {}", config.database_url);

    let state = AppState::new(config.clone()).await?;
    info!("Connected to PostgreSQL database with TimescaleDB");

    let app = create_router(state);

    let listener = TcpListener::bind(format!("0.0.0.0:{}", config.api_port)).await?;
    info!("API server listening on {}", listener.local_addr()?);

    axum::serve(listener, app).await?;

    Ok(())
}
