use std::sync::Arc;

use postgres_store::{
    Event,
    PostgresStore,
};

pub struct PostgresWriter {
    store: Arc<PostgresStore>,
}

impl PostgresWriter {
    /// # Errors
    /// This function can fail if the `PostgreSQL` connection fails.
    pub async fn new(database_url: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let store = Arc::new(PostgresStore::new(database_url).await?);
        Ok(Self { store })
    }

    /// # Errors
    /// This function can fail if the `PostgreSQL` write operation fails.
    pub async fn write_sensor_data(
        &self,
        events: Vec<Event>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        for event in events {
            self.store.insert_event(&event).await?;
        }
        Ok(())
    }
}
