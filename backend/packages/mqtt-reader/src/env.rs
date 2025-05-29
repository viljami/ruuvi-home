pub fn from_env(key: &str) -> String {
    #[allow(clippy::expect_used)] // Break early if env var is not set
    std::env::var(key).expect("Environment variable '{key}' not set")
}

pub fn try_from_env(key: &str) -> Option<String> {
    std::env::var(key).ok()
}
