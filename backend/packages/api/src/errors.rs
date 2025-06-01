//! Error handling for the Ruuvi Home API

use std::fmt;

use axum::{
    http::StatusCode,
    response::{
        IntoResponse,
        Response,
    },
    Json,
};
use serde::{
    Deserialize,
    Serialize,
};
use sqlx;

/// API Error Response structure
#[derive(Debug, Serialize, Deserialize)]
pub struct ApiErrorResponse {
    pub error: String,
    pub message: String,
    pub details: Option<String>,
    pub status_code: u16,
}

/// API Error types
#[derive(Debug)]
pub enum ApiError {
    /// Invalid MAC address format
    InvalidMacFormat { mac: String },
    /// Invalid query parameter
    InvalidParameter {
        parameter: String,
        value: String,
        expected: String,
    },
    /// Invalid date format
    InvalidDateFormat {
        date: String,
        expected_format: String,
    },
    /// Invalid date range
    InvalidDateRange { reason: String },
    /// Resource not found
    NotFound {
        resource: String,
        identifier: String,
    },
    /// Database error
    DatabaseError { operation: String, details: String },
    /// Internal server error
    Internal { message: String },
    /// Bad request with custom message
    BadRequest { message: String },
}

impl fmt::Display for ApiError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ApiError::InvalidMacFormat { mac } => {
                write!(formatter, "Invalid MAC address format: {mac}")
            }
            ApiError::InvalidParameter {
                parameter,
                value,
                expected,
            } => {
                write!(
                    formatter,
                    "Invalid parameter '{parameter}' with value '{value}': expected {expected}",
                )
            }
            ApiError::InvalidDateFormat {
                date,
                expected_format,
            } => {
                write!(
                    formatter,
                    "Invalid date format '{date}': expected {expected_format}",
                )
            }
            ApiError::InvalidDateRange { reason } => {
                write!(formatter, "Invalid date range: {reason}")
            }
            ApiError::NotFound {
                resource,
                identifier,
            } => {
                write!(formatter, "{resource} not found: {identifier}")
            }
            ApiError::DatabaseError { operation, details } => {
                write!(formatter, "Database error during {operation}: {details}")
            }
            ApiError::Internal { message } => {
                write!(formatter, "Internal server error: {message}")
            }
            ApiError::BadRequest { message } => {
                write!(formatter, "Bad request: {message}")
            }
        }
    }
}

impl ApiError {
    /// Get the HTTP status code for this error
    pub const fn status_code(&self) -> StatusCode {
        match self {
            ApiError::InvalidMacFormat { .. }
            | ApiError::InvalidParameter { .. }
            | ApiError::InvalidDateFormat { .. }
            | ApiError::InvalidDateRange { .. }
            | ApiError::BadRequest { .. } => StatusCode::BAD_REQUEST,
            ApiError::NotFound { .. } => StatusCode::NOT_FOUND,
            ApiError::DatabaseError { .. } | ApiError::Internal { .. } => {
                StatusCode::INTERNAL_SERVER_ERROR
            }
        }
    }

    /// Get the error type as a string
    pub const fn error_type(&self) -> &'static str {
        match self {
            ApiError::InvalidMacFormat { .. } => "INVALID_MAC_FORMAT",
            ApiError::InvalidParameter { .. } => "INVALID_PARAMETER",
            ApiError::InvalidDateFormat { .. } => "INVALID_DATE_FORMAT",
            ApiError::InvalidDateRange { .. } => "INVALID_DATE_RANGE",
            ApiError::BadRequest { .. } => "BAD_REQUEST",
            ApiError::NotFound { .. } => "NOT_FOUND",
            ApiError::DatabaseError { .. } => "DATABASE_ERROR",
            ApiError::Internal { .. } => "INTERNAL_ERROR",
        }
    }

    /// Get additional details for the error
    pub fn details(&self) -> Option<String> {
        match self {
            ApiError::InvalidMacFormat { mac } => Some(format!(
                "MAC address must be in format XX:XX:XX:XX:XX:XX or XXXXXXXXXXXX. Invalid MAC: \
                 {mac}"
            )),
            ApiError::InvalidParameter { expected, .. } => Some(format!("Expected: {expected}")),
            ApiError::InvalidDateFormat {
                expected_format, ..
            } => Some(format!("Expected format: {expected_format}")),
            ApiError::InvalidDateRange { reason } => Some(reason.clone()),
            ApiError::BadRequest { .. } | ApiError::NotFound { .. } => None,
            ApiError::DatabaseError { .. } => Some(
                "Please try again later or contact support if the problem persists".to_string(),
            ),
            ApiError::Internal { .. } => {
                Some("An unexpected error occurred. Please try again later".to_string())
            }
        }
    }

    /// Convert to API error response
    pub fn to_response(&self) -> ApiErrorResponse {
        let status_code = self.status_code();
        ApiErrorResponse {
            error: self.error_type().to_string(),
            message: self.to_string(),
            details: self.details(),
            status_code: status_code.as_u16(),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status_code = self.status_code();
        let response = self.to_response();

        tracing::error!(
            error_type = response.error,
            status_code = response.status_code,
            message = response.message,
            details = response.details,
            "API Error occurred"
        );

        (status_code, Json(response)).into_response()
    }
}

/// Helper functions for creating common errors
impl ApiError {
    pub fn invalid_mac(mac: &str) -> Self {
        Self::InvalidMacFormat {
            mac: mac.to_string(),
        }
    }

    pub fn invalid_limit(limit: i64) -> Self {
        Self::InvalidParameter {
            parameter: "limit".to_string(),
            value: limit.to_string(),
            expected: "positive integer between 1 and 10000".to_string(),
        }
    }

    pub fn invalid_date(date: &str) -> Self {
        Self::InvalidDateFormat {
            date: date.to_string(),
            expected_format: "ISO 8601 format (e.g., 2023-12-01T10:00:00Z)".to_string(),
        }
    }

    pub fn invalid_date_range(reason: &str) -> Self {
        Self::InvalidDateRange {
            reason: reason.to_string(),
        }
    }

    pub fn sensor_not_found(mac: &str) -> Self {
        Self::NotFound {
            resource: "Sensor".to_string(),
            identifier: mac.to_string(),
        }
    }

    pub fn readings_not_found(mac: &str) -> Self {
        Self::NotFound {
            resource: "Sensor readings".to_string(),
            identifier: mac.to_string(),
        }
    }

    pub fn database_error(operation: &str, details: &str) -> Self {
        Self::DatabaseError {
            operation: operation.to_string(),
            details: details.to_string(),
        }
    }

    pub fn internal_error(message: &str) -> Self {
        Self::Internal {
            message: message.to_string(),
        }
    }

    pub fn bad_request(message: &str) -> Self {
        Self::BadRequest {
            message: message.to_string(),
        }
    }
}

/// Convert database errors to API errors
impl From<sqlx::Error> for ApiError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => Self::NotFound {
                resource: "Data".to_string(),
                identifier: "requested record".to_string(),
            },
            _ => Self::DatabaseError {
                operation: "database query".to_string(),
                details: err.to_string(),
            },
        }
    }
}

/// Result type alias for API handlers
pub type ApiResult<T> = Result<T, ApiError>;
