//! Utility functions for the API

use chrono::{
    DateTime,
    Utc,
};

// Type alias to reduce complexity
type ParseResult = Result<DateTime<Utc>, chrono::ParseError>;
use postgres_store::TimeInterval;

/// Parse a datetime string into a `DateTime<Utc>`
///
/// # Errors
/// Returns a `chrono::ParseError` if the datetime string cannot be parsed
pub fn parse_datetime(datetime_str: &str) -> ParseResult {
    datetime_str.parse::<DateTime<Utc>>()
}

/// Parse an interval string into a `TimeInterval`
pub fn parse_interval(interval_str: &str) -> Option<TimeInterval> {
    match interval_str {
        "15m" => Some(TimeInterval::Minutes(15)),
        "1h" => Some(TimeInterval::Hours(1)),
        "1d" => Some(TimeInterval::Days(1)),
        "1w" => Some(TimeInterval::Weeks(1)),
        _ => None,
    }
}

/// Validate that a MAC address has a reasonable format
pub fn is_valid_mac_format(mac: &str) -> bool {
    // Basic validation - MAC addresses should be 17 characters with colons
    // Format: XX:XX:XX:XX:XX:XX
    if mac.len() != 17 {
        return false;
    }

    let parts: Vec<&str> = mac.split(':').collect();
    if parts.len() != 6 {
        return false;
    }

    parts
        .iter()
        .all(|part| part.len() == 2 && part.chars().all(|c| c.is_ascii_hexdigit()))
}

/// Validate that a sensor MAC follows expected patterns
pub fn is_test_mac(mac: &str) -> bool {
    // Check if it's a placeholder MAC (all same pattern)
    mac.starts_with("AA:BB:CC:DD:EE:") || mac.starts_with("FF:FF:FF:FF:FF:")
}

/// Sanitize MAC address for logging (hide real MACs in production)
pub fn sanitize_mac_for_logging(mac: &str) -> String {
    if is_test_mac(mac) {
        mac.to_string()
    } else {
        // Replace the last 6 characters with XX:XX for privacy
        if mac.len() >= 17 {
            format!("{}XX:XX", &mac[..12])
        } else {
            "XX:XX:XX:XX:XX:XX".to_string()
        }
    }
}

/// Validate that a limit parameter is reasonable
pub const fn validate_limit(limit: i64) -> bool {
    limit > 0 && limit <= 10000 // Reasonable bounds
}

/// Format duration in human readable form
pub fn format_duration_human(seconds: i64) -> String {
    match seconds {
        secs if secs < 60 => format!("{secs}s"),
        secs if secs < 3600 => {
            let minutes = secs / 60;
            format!("{minutes}m")
        }
        secs if secs < 86400 => {
            let hours = secs / 3600;
            format!("{hours}h")
        }
        secs => {
            let days = secs / 86400;
            format!("{days}d")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_datetime_invalid() {
        let test_cases = vec![
            "invalid-date",
            "2024-13-01T00:00:00Z", // Invalid month
            "2024-01-32T00:00:00Z", // Invalid day
            "2024-01-01T25:00:00Z", // Invalid hour
            "",
            "2024-01-01", // Missing time
        ];

        for datetime_str in test_cases {
            let result = parse_datetime(datetime_str);
            assert!(result.is_err(), "Expected error for: {datetime_str}");
        }
    }

    #[test]
    fn test_parse_interval_valid() {
        assert_eq!(parse_interval("15m"), Some(TimeInterval::Minutes(15)));
        assert_eq!(parse_interval("1h"), Some(TimeInterval::Hours(1)));
        assert_eq!(parse_interval("1d"), Some(TimeInterval::Days(1)));
        assert_eq!(parse_interval("1w"), Some(TimeInterval::Weeks(1)));
    }

    #[test]
    fn test_parse_interval_invalid() {
        let test_cases = vec![
            "invalid", "2h", "30m", "2d", "", "1H", // Case sensitive
            "1m",
        ];

        for interval in test_cases {
            assert_eq!(
                parse_interval(interval),
                None,
                "Expected None for: {interval}"
            );
        }
    }

    #[test]
    fn test_is_valid_mac_format() {
        // Valid MAC addresses
        let valid_macs = vec![
            "AA:BB:CC:DD:EE:FF",
            "12:34:56:78:9A:BC",
            "aa:bb:cc:dd:ee:ff",
            "00:11:22:33:44:55",
            "FF:FF:FF:FF:FF:FF",
        ];

        for mac in valid_macs {
            assert!(is_valid_mac_format(mac), "Expected valid for: {mac}");
        }
    }

    #[test]
    fn test_is_valid_mac_format_invalid() {
        let invalid_macs = vec![
            "AA:BB:CC:DD:EE",       // Too short
            "AA:BB:CC:DD:EE:FF:GG", // Too long
            "AA-BB-CC-DD-EE-FF",    // Wrong separator
            "GG:HH:II:JJ:KK:LL",    // Invalid hex
            "AA:BB:CC:DD:EE:FG",    // Invalid hex character
            "",                     // Empty
            "AA:BB:CC:DD:EE:F",     // Short segment
            "AAA:BB:CC:DD:EE:FF",   // Long segment
            "AA:BB:CC:DD:EE:",      // Missing last segment
            ":BB:CC:DD:EE:FF",      // Missing first segment
        ];

        for mac in invalid_macs {
            assert!(!is_valid_mac_format(mac), "Expected invalid for: {mac}");
        }
    }

    #[test]
    fn test_is_test_mac() {
        // Test MACs (should return true)
        let test_macs = vec![
            "AA:BB:CC:DD:EE:01",
            "AA:BB:CC:DD:EE:FF",
            "FF:FF:FF:FF:FF:01",
            "FF:FF:FF:FF:FF:99",
        ];

        for mac in test_macs {
            assert!(is_test_mac(mac), "Expected test MAC for: {mac}");
        }

        // Real-looking MACs (should return false)
        let real_macs = vec![
            "D1:10:96:D8:08:F4",
            "F7:97:E3:6E:D8:11",
            "12:34:56:78:9A:BC",
            "00:11:22:33:44:55",
        ];

        for mac in real_macs {
            assert!(!is_test_mac(mac), "Expected real MAC for: {mac}");
        }
    }

    #[test]
    fn test_sanitize_mac_for_logging() {
        // Test MACs should remain unchanged
        assert_eq!(
            sanitize_mac_for_logging("AA:BB:CC:DD:EE:01"),
            "AA:BB:CC:DD:EE:01"
        );
        assert_eq!(
            sanitize_mac_for_logging("FF:FF:FF:FF:FF:99"),
            "FF:FF:FF:FF:FF:99"
        );

        // Real MACs should be sanitized
        assert_eq!(
            sanitize_mac_for_logging("D1:10:96:D8:08:F4"),
            "D1:10:96:D8:XX:XX"
        );
        assert_eq!(
            sanitize_mac_for_logging("F7:97:E3:6E:D8:11"),
            "F7:97:E3:6E:XX:XX"
        );

        // Invalid MAC should default to all XX
        assert_eq!(sanitize_mac_for_logging("invalid"), "XX:XX:XX:XX:XX:XX");
        assert_eq!(sanitize_mac_for_logging(""), "XX:XX:XX:XX:XX:XX");
    }

    #[test]
    fn test_validate_limit() {
        // Valid limits
        assert!(validate_limit(1));
        assert!(validate_limit(100));
        assert!(validate_limit(1000));
        assert!(validate_limit(10000));

        // Invalid limits
        assert!(!validate_limit(0));
        assert!(!validate_limit(-1));
        assert!(!validate_limit(10001));
        assert!(!validate_limit(100_000));
    }

    #[test]
    fn test_format_duration_human() {
        assert_eq!(format_duration_human(30), "30s");
        assert_eq!(format_duration_human(59), "59s");
        assert_eq!(format_duration_human(60), "1m");
        assert_eq!(format_duration_human(120), "2m");
        assert_eq!(format_duration_human(3599), "59m");
        assert_eq!(format_duration_human(3600), "1h");
        assert_eq!(format_duration_human(7200), "2h");
        assert_eq!(format_duration_human(86399), "23h");
        assert_eq!(format_duration_human(86400), "1d");
        assert_eq!(format_duration_human(172_800), "2d");
    }

    #[test]
    fn test_format_duration_edge_cases() {
        assert_eq!(format_duration_human(0), "0s");
        assert_eq!(format_duration_human(1), "1s");
        assert_eq!(format_duration_human(61), "1m");
        assert_eq!(format_duration_human(3661), "1h");
        assert_eq!(format_duration_human(90061), "1d");
    }
}
