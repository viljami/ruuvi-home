use std::env;

use anyhow::Result;
use postgres_store::PostgresStore;
use sqlx::{
    postgres::PgPoolOptions,
    Executor,
    PgPool,
};
use uuid::Uuid;

// Configuration for test database setup
#[derive(Clone)]
pub struct TestDbConfig {
    pub admin_db_url: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
}

impl TestDbConfig {
    pub fn from_env() -> Self {
        let base_url = env::var("TEST_DATABASE_URL").unwrap_or_else(|_| {
            "postgresql://ruuvi:ruuvi_secret@localhost:5432/postgres".to_string()
        });

        // Parse the URL to extract components
        let url = url::Url::parse(&base_url).expect("Invalid database URL");

        Self {
            admin_db_url: base_url,
            host: url.host_str().unwrap().to_string(),
            port: url.port().unwrap_or(5432),
            username: url.username().to_string(),
            password: url.password().unwrap_or("").to_string(),
        }
    }

    pub fn database_url(&self, db_name: &str) -> String {
        format!(
            "postgresql://{}:{}@{}:{}/{}",
            self.username, self.password, self.host, self.port, db_name
        )
    }
}

// Test database manager that handles creation and cleanup
pub struct TestDatabase {
    pub store: PostgresStore,
    pub db_name: String,
    admin_pool: PgPool,
}

impl TestDatabase {
    pub async fn new() -> Result<Self> {
        let config = TestDbConfig::from_env();

        // Connect to admin database (postgres) for creating new databases
        let admin_pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(&config.admin_db_url)
            .await?;

        // Generate unique database name
        let test_id = Uuid::new_v4();
        let db_name = format!("test_ruuvi_{}", test_id.to_string().replace('-', "_"));

        // Create the test database
        let create_db_query = format!("CREATE DATABASE \"{}\"", db_name);
        admin_pool.execute(create_db_query.as_str()).await?;

        // Connect to the new test database
        let test_db_url = config.database_url(&db_name);
        let store = PostgresStore::new(&test_db_url).await?;

        // Run migrations on the new database
        Self::run_migrations(&store.pool).await?;

        Ok(Self {
            store,
            db_name,
            admin_pool,
        })
    }

    async fn run_migrations(pool: &PgPool) -> Result<()> {
        // For tests, only run the basic migration without continuous aggregates
        // which cause issues in transaction-based test environments
        let migration_sql = include_str!("../../migrations/001_initial.sql");
        pool.execute(migration_sql).await?;
        Ok(())
    }

    pub async fn cleanup(self) -> Result<()> {
        let db_name = self.db_name.clone();
        let admin_pool = self.admin_pool.clone();

        // Close the test database connection first
        self.store.pool.close().await;

        // Now cleanup the database
        Self::cleanup_database(&admin_pool, &db_name).await?;
        admin_pool.close().await;
        Ok(())
    }

    async fn cleanup_database(admin_pool: &PgPool, db_name: &str) -> Result<(), sqlx::Error> {
        // Terminate any active connections to the test database
        let terminate_connections = format!(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{}' AND pid \
             <> pg_backend_pid()",
            db_name
        );
        let _ = admin_pool.execute(terminate_connections.as_str()).await;

        // Drop the test database
        let drop_db_query = format!("DROP DATABASE IF EXISTS \"{}\"", db_name);
        admin_pool.execute(drop_db_query.as_str()).await?;
        Ok(())
    }
}

impl Drop for TestDatabase {
    fn drop(&mut self) {
        // Best effort cleanup in case explicit cleanup wasn't called
        let db_name = self.db_name.clone();
        let admin_pool = self.admin_pool.clone();

        tokio::spawn(async move {
            let _ = Self::cleanup_database(&admin_pool, &db_name).await;
        });
    }
}
