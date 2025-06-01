use std::env;

use anyhow::Result;
use postgres_store::PostgresStore;
use sqlx::{
    postgres::PgPoolOptions,
    Executor,
    PgPool,
};
use uuid::Uuid;

#[derive(Debug)]
pub enum TestDatabaseError {
    DatabaseUnavailable(String),
    Other(anyhow::Error),
}

impl From<anyhow::Error> for TestDatabaseError {
    fn from(err: anyhow::Error) -> Self {
        TestDatabaseError::Other(err)
    }
}

impl From<url::ParseError> for TestDatabaseError {
    fn from(err: url::ParseError) -> Self {
        TestDatabaseError::Other(anyhow::anyhow!("URL parse error: {err}"))
    }
}

impl From<sqlx::Error> for TestDatabaseError {
    fn from(err: sqlx::Error) -> Self {
        TestDatabaseError::Other(anyhow::anyhow!("Database error: {err}"))
    }
}

impl std::fmt::Display for TestDatabaseError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TestDatabaseError::DatabaseUnavailable(msg) => {
                write!(formatter, "Database unavailable: {msg}")
            }
            TestDatabaseError::Other(err) => write!(formatter, "{err}"),
        }
    }
}

impl std::error::Error for TestDatabaseError {}

// Test database manager that handles creation and cleanup
pub struct TestDatabase {
    pub store: PostgresStore,
    pub db_name: String,
    admin_pool: PgPool,
}

impl TestDatabase {
    /// Check if a `PostgreSQL` database is available for testing
    pub async fn is_database_available() -> bool {
        let base_url = env::var("TEST_DATABASE_URL")
            .or_else(|_| env::var("DATABASE_URL"))
            .unwrap_or_else(|_| {
                "postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home".to_string()
            });

        match PgPoolOptions::new()
            .max_connections(1)
            .acquire_timeout(std::time::Duration::from_secs(5))
            .connect(&base_url)
            .await
        {
            Ok(pool) => {
                // Test with a simple query
                if sqlx::query("SELECT 1").fetch_one(&pool).await.is_ok() {
                    pool.close().await;
                    true
                } else {
                    false
                }
            }
            Err(_) => false,
        }
    }

    pub async fn new() -> Result<Self, TestDatabaseError> {
        // Get database URL from environment, with fallback for CI
        let base_url = env::var("TEST_DATABASE_URL")
            .or_else(|_| env::var("DATABASE_URL"))
            .unwrap_or_else(|_| {
                "postgresql://ruuvi:ruuvi_secret@localhost:5432/ruuvi_home".to_string()
            });

        // Parse the URL to extract components
        let url = url::Url::parse(&base_url)?;
        let host = url.host_str().unwrap_or("localhost");
        let port = url.port().unwrap_or(5432);
        let username = url.username();
        let password = url.password().unwrap_or("");

        // First check if database is available
        if !Self::is_database_available().await {
            return Err(TestDatabaseError::DatabaseUnavailable(
                "No PostgreSQL database available for testing. Please ensure PostgreSQL is \
                 running or set TEST_DATABASE_URL environment variable."
                    .to_string(),
            ));
        }

        // Connect to admin database (postgres) for creating new databases
        let admin_pool = PgPoolOptions::new()
            .max_connections(5)
            .acquire_timeout(std::time::Duration::from_secs(30))
            .connect(&base_url)
            .await
            .map_err(|e| {
                TestDatabaseError::DatabaseUnavailable(format!(
                    "Failed to connect to test database: {e}"
                ))
            })?;

        // Generate unique database name for this test
        let test_id = Uuid::new_v4();
        let db_name = format!("test_ruuvi_{}", test_id.simple());

        // Create the test database
        let create_db_query = format!("CREATE DATABASE \"{db_name}\"");
        admin_pool.execute(create_db_query.as_str()).await?;

        // Connect to the new test database
        let test_db_url = format!("postgresql://{username}:{password}@{host}:{port}/{db_name}");

        let store = PostgresStore::new(&test_db_url).await?;

        // Run migrations
        Self::run_migrations(&store.pool).await?;

        Ok(Self {
            store,
            db_name,
            admin_pool,
        })
    }

    #[allow(clippy::too_many_lines)]
    async fn run_migrations(pool: &PgPool) -> Result<()> {
        // Create TimescaleDB extension if available (ignore errors for regular
        // PostgreSQL)
        let _ = pool
            .execute("CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE")
            .await;

        // Create the table matching the migration schema
        pool.execute(
            r"
            CREATE TABLE IF NOT EXISTS sensor_data (
                sensor_mac VARCHAR(17) NOT NULL,
                gateway_mac VARCHAR(17) NOT NULL,
                temperature DOUBLE PRECISION NOT NULL,
                humidity DOUBLE PRECISION NOT NULL,
                pressure DOUBLE PRECISION NOT NULL,
                battery BIGINT NOT NULL,
                tx_power BIGINT NOT NULL,
                movement_counter BIGINT NOT NULL,
                measurement_sequence_number BIGINT NOT NULL,
                acceleration DOUBLE PRECISION NOT NULL,
                acceleration_x BIGINT NOT NULL,
                acceleration_y BIGINT NOT NULL,
                acceleration_z BIGINT NOT NULL,
                rssi BIGINT NOT NULL,
                timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        ",
        )
        .await?;

        // Try to create hypertable if TimescaleDB is available
        let hypertable_result = pool
            .execute("SELECT create_hypertable('sensor_data', 'timestamp', if_not_exists => TRUE)")
            .await;

        if hypertable_result.is_err() {
            // If TimescaleDB is not available, just create a regular index
            let _ = pool
                .execute(
                    "CREATE INDEX IF NOT EXISTS sensor_data_timestamp_idx ON sensor_data \
                     (timestamp DESC)",
                )
                .await;
        }

        // Create other useful indexes matching the migration
        pool.execute(
            "CREATE INDEX IF NOT EXISTS idx_sensor_data_sensor_mac ON sensor_data(sensor_mac, \
             timestamp DESC)",
        )
        .await?;

        pool.execute(
            "CREATE INDEX IF NOT EXISTS idx_sensor_data_gateway_mac ON sensor_data(gateway_mac, \
             timestamp DESC)",
        )
        .await?;

        pool.execute(
            "CREATE INDEX IF NOT EXISTS idx_sensor_data_active ON sensor_data(sensor_mac, \
             gateway_mac, timestamp DESC)",
        )
        .await?;

        // Add constraints for reasonable sensor values
        let _ = pool
            .execute(
                "ALTER TABLE sensor_data ADD CONSTRAINT chk_temperature CHECK (temperature \
                 BETWEEN -100 AND 100)",
            )
            .await;
        let _ = pool
            .execute(
                "ALTER TABLE sensor_data ADD CONSTRAINT chk_humidity CHECK (humidity BETWEEN 0 \
                 AND 100)",
            )
            .await;
        let _ = pool
            .execute(
                "ALTER TABLE sensor_data ADD CONSTRAINT chk_pressure CHECK (pressure BETWEEN 300 \
                 AND 1300)",
            )
            .await;
        let _ = pool
            .execute(
                "ALTER TABLE sensor_data ADD CONSTRAINT chk_battery CHECK (battery BETWEEN 0 AND \
                 4000)",
            )
            .await;

        Ok(())
    }

    pub async fn cleanup(self) -> Result<()> {
        let db_name = self.db_name.clone();
        let admin_pool = self.admin_pool.clone();

        // Close the test database connection first
        self.store.pool.close().await;

        // Terminate any active connections to the test database
        let terminate_connections = format!(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{db_name}' \
             AND pid <> pg_backend_pid()"
        );
        let _ = admin_pool.execute(terminate_connections.as_str()).await;

        // Drop the test database
        let drop_db_query = format!("DROP DATABASE IF EXISTS \"{db_name}\"");
        let _ = admin_pool.execute(drop_db_query.as_str()).await;

        admin_pool.close().await;
        Ok(())
    }
}

impl Drop for TestDatabase {
    fn drop(&mut self) {
        // Best effort cleanup in case explicit cleanup wasn't called
        let db_name = self.db_name.clone();
        let admin_pool = self.admin_pool.clone();

        tokio::spawn(async move {
            // Terminate connections and drop database
            let terminate_connections = format!(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = \
                 '{db_name}' AND pid <> pg_backend_pid()"
            );
            let _ = admin_pool.execute(terminate_connections.as_str()).await;

            let drop_db_query = format!("DROP DATABASE IF EXISTS \"{db_name}\"");
            let _ = admin_pool.execute(drop_db_query.as_str()).await;
        });
    }
}

/// Macro to skip integration tests when database is not available
#[macro_export]
macro_rules! skip_if_no_db {
    () => {
        if !TestDatabase::is_database_available().await {
            println!("Skipping test: No database available");
            return;
        }
    };
}
