use config::Config;

pub mod config;
pub mod db;

/// # Errors
/// This function can fail if the `PostgreSQL` connection fails.
pub async fn create(config: Config) -> Result<db::PostgresWriter, Box<dyn std::error::Error>> {
    db::PostgresWriter::new(&config.database_url).await
}
