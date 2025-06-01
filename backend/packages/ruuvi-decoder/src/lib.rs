// Enforce strict error handling in application code, but allow expect/unwrap in
// tests
#![cfg_attr(not(test), deny(clippy::expect_used, clippy::unwrap_used))]
#![cfg_attr(not(test), deny(clippy::panic))]

#[macro_use]
extern crate structure;

pub mod decoder;

pub use decoder::*;
