// Enforce strict error handling in application code, but allow expect/unwrap in tests
#![cfg_attr(not(test), deny(clippy::expect_used, clippy::unwrap_used))]
#![cfg_attr(not(test), deny(clippy::panic))]

mod env;
pub mod read;
pub mod write;
