use crate::env::from_env;

pub struct Config {
    pub database_url: String,
}

impl Config {
    #[must_use]
    pub fn new(database_url: String) -> Self {
        Self { database_url }
    }

    /// # Panics
    #[must_use]
    pub fn from_env() -> Self {
        Self {
            database_url: from_env("DATABASE_URL"),
        }
    }
}
