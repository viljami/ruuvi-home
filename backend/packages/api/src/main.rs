use std::sync::Arc;

use anyhow::Result;
use axum::{
    extract::{
        Path,
        Query,
        State,
    },
    http::{
        HeaderValue,
        StatusCode,
    },
    response::Json,
    routing::get,
    Router,
};
use chrono::{DateTime, Utc};
use postgres_store::{Event, PostgresStore, TimeInterval, TimeBucketedData, StorageStats, StorageEstimate};
use serde::Deserialize;
use tower_http::cors::{
    AllowOrigin,
    Any,
    CorsLayer,
};
use tracing::{
    error,
    info,
};

#[derive(Clone)]
struct Config {
    database_url: String,
    api_port: u16,
}

impl Config {
    fn from_env() -> Result<Self> {
        Ok(Self {
            database_url: std::env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home".to_string()),
            api_port: std::env::var("API_PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()?,
        })
    }
}

#[derive(Debug, Deserialize)]
struct HistoricalQuery {
    start: Option<String>,
    end: Option<String>,
    limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct TimeBucketQuery {
    start: Option<String>,
    end: Option<String>,
    interval: Option<String>,
}

#[derive(Clone)]
struct AppState {
    store: Arc<PostgresStore>,
}

impl AppState {
    async fn new(config: Config) -> Result<Self> {
        let store = Arc::new(PostgresStore::new(&config.database_url).await?);
        Ok(Self { store })
    }

    fn parse_datetime(datetime_str: &str) -> Result<DateTime<Utc>, chrono::ParseError> {
        datetime_str.parse::<DateTime<Utc>>()
    }
}

async fn get_sensors(State(state): State<AppState>) -> Result<Json<Vec<Event>>, StatusCode> {
    match state.store.get_active_sensors().await {
        Ok(sensors) => Ok(Json(sensors)),
        Err(e) => {
            error!("Failed to get active sensors: {}", e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_sensor_latest(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
) -> Result<Json<Event>, StatusCode> {
    match state.store.get_latest_reading(&sensor_mac).await {
        Ok(Some(reading)) => Ok(Json(reading)),
        Ok(None) => Err(StatusCode::NOT_FOUND),
        Err(e) => {
            error!(
                "Failed to get latest reading for sensor {}: {}",
                sensor_mac, e
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_sensor_history(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<HistoricalQuery>,
) -> Result<Json<Vec<Event>>, StatusCode> {
    let start = match params.start.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => Some(dt),
            Err(_) => {
                error!("Invalid start date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Some(Utc::now() - chrono::Duration::hours(1)),
    };

    let end = match params.end.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => Some(dt),
            Err(_) => {
                error!("Invalid end date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Some(Utc::now()),
    };

    match state.store.get_historical_data(&sensor_mac, start, end, params.limit).await {
        Ok(readings) => Ok(Json(readings)),
        Err(e) => {
            error!(
                "Failed to get historical data for sensor {}: {}",
                sensor_mac, e
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_sensor_aggregates(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<TimeBucketQuery>,
) -> Result<Json<Vec<TimeBucketedData>>, StatusCode> {
    let start = match params.start.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => dt,
            Err(_) => {
                error!("Invalid start date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Utc::now() - chrono::Duration::hours(24),
    };

    let end = match params.end.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => dt,
            Err(_) => {
                error!("Invalid end date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Utc::now(),
    };

    let interval = match params.interval.as_deref() {
        Some("15m") => TimeInterval::Minutes(15),
        Some("1h") => TimeInterval::Hours(1),
        Some("1d") => TimeInterval::Days(1),
        Some("1w") => TimeInterval::Weeks(1),
        Some(custom) => {
            error!("Unsupported interval: {}", custom);
            return Err(StatusCode::BAD_REQUEST);
        },
        None => TimeInterval::Hours(1),
    };

    match state.store.get_time_bucketed_data(&sensor_mac, &interval, start, end).await {
        Ok(data) => Ok(Json(data)),
        Err(e) => {
            error!(
                "Failed to get aggregated data for sensor {}: {}",
                sensor_mac, e
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_sensor_hourly_aggregates(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<TimeBucketQuery>,
) -> Result<Json<Vec<TimeBucketedData>>, StatusCode> {
    let start = match params.start.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => dt,
            Err(_) => {
                error!("Invalid start date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Utc::now() - chrono::Duration::hours(72),
    };

    let end = match params.end.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => dt,
            Err(_) => {
                error!("Invalid end date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Utc::now(),
    };

    match state.store.get_hourly_aggregates(&sensor_mac, start, end).await {
        Ok(data) => Ok(Json(data)),
        Err(e) => {
            error!(
                "Failed to get hourly aggregates for sensor {}: {}",
                sensor_mac, e
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_sensor_daily_aggregates(
    State(state): State<AppState>,
    Path(sensor_mac): Path<String>,
    Query(params): Query<TimeBucketQuery>,
) -> Result<Json<Vec<TimeBucketedData>>, StatusCode> {
    let start = match params.start.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => dt,
            Err(_) => {
                error!("Invalid start date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Utc::now() - chrono::Duration::days(30),
    };

    let end = match params.end.as_ref() {
        Some(s) => match AppState::parse_datetime(s) {
            Ok(dt) => dt,
            Err(_) => {
                error!("Invalid end date format: {}", s);
                return Err(StatusCode::BAD_REQUEST);
            }
        },
        None => Utc::now(),
    };

    match state.store.get_daily_aggregates(&sensor_mac, start, end).await {
        Ok(data) => Ok(Json(data)),
        Err(e) => {
            error!(
                "Failed to get daily aggregates for sensor {}: {}",
                sensor_mac, e
            );
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_storage_stats(State(state): State<AppState>) -> Result<Json<StorageStats>, StatusCode> {
    match state.store.get_storage_stats().await {
        Ok(stats) => Ok(Json(stats)),
        Err(e) => {
            error!("Failed to get storage stats: {}", e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn get_storage_estimate(
    State(state): State<AppState>,
    Query(params): Query<StorageEstimateQuery>,
) -> Result<Json<StorageEstimate>, StatusCode> {
    let sensor_count = params.sensor_count.unwrap_or(10);
    let interval_seconds = params.interval_seconds.unwrap_or(10);
    let retention_years = params.retention_years.unwrap_or(5);

    match state.store.estimate_storage_requirements(sensor_count, interval_seconds, retention_years).await {
        Ok(estimate) => Ok(Json(estimate)),
        Err(e) => {
            error!("Failed to get storage estimate: {}", e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

#[derive(Debug, Deserialize)]
struct StorageEstimateQuery {
    sensor_count: Option<i32>,
    interval_seconds: Option<i32>,
    retention_years: Option<i32>,
}

async fn health_check() -> &'static str {
    "OK"
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let config = Config::from_env()?;
    info!("Starting API server on port {}", config.api_port);
    info!("Database URL: {}", config.database_url);

    let state = AppState::new(config.clone()).await?;
    info!("Connected to PostgreSQL database with TimescaleDB");

    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(|origin: &HeaderValue, _| {
            origin
                .to_str()
                .map(|s| s.starts_with("http://localhost:") || s.starts_with("https://localhost:"))
                .unwrap_or(false)
        }))
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health_check))
        .route("/api/sensors", get(get_sensors))
        .route("/api/sensors/{sensor_mac}/latest", get(get_sensor_latest))
        .route("/api/sensors/{sensor_mac}/history", get(get_sensor_history))
        .route("/api/sensors/{sensor_mac}/aggregates", get(get_sensor_aggregates))
        .route("/api/sensors/{sensor_mac}/hourly", get(get_sensor_hourly_aggregates))
        .route("/api/sensors/{sensor_mac}/daily", get(get_sensor_daily_aggregates))
        .route("/api/storage/stats", get(get_storage_stats))
        .route("/api/storage/estimate", get(get_storage_estimate))
        .layer(cors)
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", config.api_port)).await?;
    info!("API server listening on {}", listener.local_addr()?);

    axum::serve(listener, app).await?;

    Ok(())
}