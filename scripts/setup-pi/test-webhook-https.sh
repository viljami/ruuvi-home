#!/bin/bash
# HTTPS Webhook Test Script
# Tests webhook server HTTPS functionality and certificate validation

set -e

readonly SCRIPT_NAME="test-webhook-https"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# Test configuration
readonly WEBHOOK_HOST="${WEBHOOK_HOST:-localhost}"
readonly WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"
readonly SSL_CERT_PATH="$PROJECT_DIR/ssl/webhook.crt"
readonly SSL_KEY_PATH="$PROJECT_DIR/ssl/webhook.key"

print_header() {
    echo -e "${COLOR_BLUE}========================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}    HTTPS Webhook Test Suite           ${COLOR_NC}"
    echo -e "${COLOR_BLUE}========================================${COLOR_NC}"
    echo ""
}

log_test() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "[${timestamp}] ${COLOR_BLUE}[INFO]${COLOR_NC} $message"
            ;;
        "SUCCESS")
            echo -e "[${timestamp}] ${COLOR_GREEN}[SUCCESS]${COLOR_NC} $message"
            ;;
        "ERROR")
            echo -e "[${timestamp}] ${COLOR_RED}[ERROR]${COLOR_NC} $message"
            ;;
        "WARN")
            echo -e "[${timestamp}] ${COLOR_YELLOW}[WARN]${COLOR_NC} $message"
            ;;
    esac
}

test_ssl_certificate_files() {
    log_test "INFO" "Testing SSL certificate files"

    # Check if certificate files exist
    if [ ! -f "$SSL_CERT_PATH" ]; then
        log_test "ERROR" "SSL certificate not found: $SSL_CERT_PATH"
        return 1
    fi

    if [ ! -f "$SSL_KEY_PATH" ]; then
        log_test "ERROR" "SSL private key not found: $SSL_KEY_PATH"
        return 1
    fi

    log_test "SUCCESS" "SSL certificate files found"

    # Validate certificate syntax
    if ! openssl x509 -in "$SSL_CERT_PATH" -text -noout >/dev/null 2>&1; then
        log_test "ERROR" "Invalid SSL certificate format"
        return 1
    fi

    # Validate private key syntax
    if ! openssl rsa -in "$SSL_KEY_PATH" -check -noout >/dev/null 2>&1; then
        log_test "ERROR" "Invalid SSL private key format"
        return 1
    fi

    # Check if certificate and key match
    local cert_modulus=$(openssl x509 -noout -modulus -in "$SSL_CERT_PATH" | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$SSL_KEY_PATH" | openssl md5)

    if [ "$cert_modulus" != "$key_modulus" ]; then
        log_test "ERROR" "SSL certificate and private key do not match"
        return 1
    fi

    log_test "SUCCESS" "SSL certificate validation passed"
    return 0
}

test_certificate_details() {
    log_test "INFO" "Checking SSL certificate details"

    # Get certificate information
    local cert_subject=$(openssl x509 -in "$SSL_CERT_PATH" -noout -subject | sed 's/subject= *//')
    local cert_issuer=$(openssl x509 -in "$SSL_CERT_PATH" -noout -issuer | sed 's/issuer= *//')
    local cert_not_before=$(openssl x509 -in "$SSL_CERT_PATH" -noout -startdate | sed 's/notBefore=//')
    local cert_not_after=$(openssl x509 -in "$SSL_CERT_PATH" -noout -enddate | sed 's/notAfter=//')

    echo ""
    echo "=== Certificate Details ==="
    echo "Subject: $cert_subject"
    echo "Issuer: $cert_issuer"
    echo "Valid From: $cert_not_before"
    echo "Valid Until: $cert_not_after"

    # Check if certificate is expired
    if ! openssl x509 -in "$SSL_CERT_PATH" -checkend 0 >/dev/null 2>&1; then
        log_test "ERROR" "SSL certificate has expired"
        return 1
    fi

    # Check if certificate expires within 30 days
    if ! openssl x509 -in "$SSL_CERT_PATH" -checkend 2592000 >/dev/null 2>&1; then
        log_test "WARN" "SSL certificate expires within 30 days"
    fi

    # Determine certificate type
    if echo "$cert_issuer" | grep -q "Let's Encrypt"; then
        log_test "INFO" "Certificate type: Let's Encrypt"
    else
        log_test "INFO" "Certificate type: Self-signed or other"
    fi

    log_test "SUCCESS" "Certificate details validated"
    echo ""
    return 0
}

test_webhook_service_status() {
    log_test "INFO" "Testing webhook service status"

    # Check if webhook service is running
    if ! systemctl is-active --quiet ruuvi-webhook.service; then
        log_test "ERROR" "Webhook service is not running"
        log_test "INFO" "Try: sudo systemctl start ruuvi-webhook"
        return 1
    fi

    log_test "SUCCESS" "Webhook service is running"

    # Show service status
    local service_status=$(systemctl show ruuvi-webhook.service --property=ActiveState --value)
    local service_substate=$(systemctl show ruuvi-webhook.service --property=SubState --value)
    log_test "INFO" "Service status: $service_status/$service_substate"

    return 0
}

test_https_connectivity() {
    log_test "INFO" "Testing HTTPS connectivity"

    local webhook_url="https://$WEBHOOK_HOST:$WEBHOOK_PORT"

    # Test HTTPS connection (ignore certificate validation for self-signed)
    if curl -k -s --connect-timeout 5 "$webhook_url" >/dev/null 2>&1; then
        log_test "SUCCESS" "HTTPS connection successful"
    else
        log_test "ERROR" "Failed to connect to webhook server via HTTPS"
        log_test "INFO" "URL tested: $webhook_url"
        return 1
    fi

    # Test health check endpoint
    local response=$(curl -k -s --connect-timeout 5 "$webhook_url" || echo "")
    if echo "$response" | grep -q "Webhook Server"; then
        log_test "SUCCESS" "Webhook health check passed"
        log_test "INFO" "Response: $response"
    else
        log_test "WARN" "Unexpected health check response: $response"
    fi

    return 0
}

test_certificate_trust() {
    log_test "INFO" "Testing certificate trust"

    local webhook_url="https://$WEBHOOK_HOST:$WEBHOOK_PORT"

    # Test with certificate validation enabled
    if curl -s --connect-timeout 5 "$webhook_url" >/dev/null 2>&1; then
        log_test "SUCCESS" "Certificate is trusted by system"
    else
        log_test "WARN" "Certificate not trusted (expected for self-signed)"
        log_test "INFO" "This is normal for self-signed certificates"
        log_test "INFO" "GitHub webhooks with self-signed certs require SSL verification disabled"
    fi

    return 0
}

test_webhook_signature_validation() {
    log_test "INFO" "Testing webhook signature validation"

    # Load webhook secret
    local webhook_secret=""
    if [ -f "$PROJECT_DIR/.env" ]; then
        webhook_secret=$(grep "WEBHOOK_SECRET=" "$PROJECT_DIR/.env" | cut -d'=' -f2)
    fi

    if [ -z "$webhook_secret" ]; then
        log_test "WARN" "Webhook secret not found in .env file"
        return 0
    fi

    local webhook_url="https://$WEBHOOK_HOST:$WEBHOOK_PORT"
    local test_payload='{"ref":"refs/heads/main","repository":{"full_name":"test/repo"}}'

    # Calculate signature
    local signature=$(echo -n "$test_payload" | openssl dgst -sha256 -hmac "$webhook_secret" | awk '{print $2}')
    local github_signature="sha256=$signature"

    # Test valid signature
    local response=$(curl -k -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: $github_signature" \
        -H "X-GitHub-Event: push" \
        -d "$test_payload" \
        "$webhook_url" 2>/dev/null || echo "")

    if echo "$response" | grep -q "triggered"; then
        log_test "SUCCESS" "Valid signature accepted"
    else
        log_test "WARN" "Unexpected response to valid signature: $response"
    fi

    # Test invalid signature
    local invalid_response=$(curl -k -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: sha256=invalid" \
        -H "X-GitHub-Event: push" \
        -d "$test_payload" \
        "$webhook_url" 2>/dev/null || echo "")

    if echo "$invalid_response" | grep -q "Unauthorized"; then
        log_test "SUCCESS" "Invalid signature rejected"
    else
        log_test "WARN" "Invalid signature not properly rejected: $invalid_response"
    fi

    return 0
}

test_webhook_logs() {
    log_test "INFO" "Checking webhook logs"

    local log_file="/var/log/ruuvi-home/webhook.log"

    if [ -f "$log_file" ]; then
        local log_lines=$(tail -n 5 "$log_file")
        log_test "SUCCESS" "Webhook log file found"
        echo "Recent log entries:"
        echo "$log_lines"
    else
        log_test "WARN" "Webhook log file not found: $log_file"
    fi

    # Check systemd logs
    log_test "INFO" "Recent systemd logs for webhook service:"
    journalctl -u ruuvi-webhook --no-pager -n 5 2>/dev/null || log_test "WARN" "Could not read systemd logs"

    return 0
}

test_port_accessibility() {
    log_test "INFO" "Testing port accessibility"

    # Check if port is listening
    if netstat -tuln 2>/dev/null | grep -q ":$WEBHOOK_PORT "; then
        log_test "SUCCESS" "Webhook port $WEBHOOK_PORT is listening"
    else
        log_test "ERROR" "Webhook port $WEBHOOK_PORT is not listening"
        return 1
    fi

    # Check firewall status
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "$WEBHOOK_PORT"; then
            log_test "SUCCESS" "Firewall allows webhook port"
        else
            log_test "WARN" "Firewall may be blocking webhook port"
            log_test "INFO" "Run: sudo ufw allow $WEBHOOK_PORT/tcp"
        fi
    fi

    return 0
}

generate_github_webhook_config() {
    log_test "INFO" "Generating GitHub webhook configuration"

    echo ""
    echo "=== GitHub Webhook Configuration ==="

    # Determine external IP
    local external_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    local webhook_secret=""

    if [ -f "$PROJECT_DIR/.env" ]; then
        webhook_secret=$(grep "WEBHOOK_SECRET=" "$PROJECT_DIR/.env" | cut -d'=' -f2)
    fi

    echo "Webhook URL: https://$external_ip:$WEBHOOK_PORT"
    echo "Content Type: application/json"
    echo "Secret: ${webhook_secret:-[Check $PROJECT_DIR/.env]}"

    # Check certificate type for SSL verification recommendation
    if [ -f "$SSL_CERT_PATH" ]; then
        local cert_issuer=$(openssl x509 -in "$SSL_CERT_PATH" -noout -issuer | sed 's/issuer= *//')
        if echo "$cert_issuer" | grep -q "Let's Encrypt"; then
            echo "SSL Verification: ✅ Enable (Let's Encrypt certificate)"
        else
            echo "SSL Verification: ❌ Disable (Self-signed certificate)"
        fi
    fi

    echo "Events: Just the push event"
    echo "Active: ✅ Checked"
    echo ""

    return 0
}

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --cert-only     Test only SSL certificate validation"
    echo "  --connectivity  Test only HTTPS connectivity"
    echo "  --webhook       Test only webhook functionality"
    echo "  --logs          Show only logs"
    echo "  --config        Generate GitHub webhook config only"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 --cert-only       # Test certificates only"
    echo "  $0 --connectivity    # Test connectivity only"
}

main() {
    local test_cert=true
    local test_connectivity=true
    local test_webhook=true
    local test_logs=true
    local show_config=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cert-only)
                test_connectivity=false
                test_webhook=false
                test_logs=false
                show_config=false
                shift
                ;;
            --connectivity)
                test_cert=false
                test_webhook=false
                test_logs=false
                show_config=false
                shift
                ;;
            --webhook)
                test_cert=false
                test_connectivity=false
                test_logs=false
                show_config=false
                shift
                ;;
            --logs)
                test_cert=false
                test_connectivity=false
                test_webhook=false
                show_config=false
                shift
                ;;
            --config)
                test_cert=false
                test_connectivity=false
                test_webhook=false
                test_logs=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    print_header

    local failed_tests=()

    # Run tests based on selection
    if [ "$test_cert" = true ]; then
        if ! test_ssl_certificate_files; then
            failed_tests+=("SSL Certificate Files")
        fi

        if ! test_certificate_details; then
            failed_tests+=("Certificate Details")
        fi
    fi

    if [ "$test_connectivity" = true ]; then
        if ! test_webhook_service_status; then
            failed_tests+=("Service Status")
        fi

        if ! test_port_accessibility; then
            failed_tests+=("Port Accessibility")
        fi

        if ! test_https_connectivity; then
            failed_tests+=("HTTPS Connectivity")
        fi

        if ! test_certificate_trust; then
            failed_tests+=("Certificate Trust")
        fi
    fi

    if [ "$test_webhook" = true ]; then
        if ! test_webhook_signature_validation; then
            failed_tests+=("Signature Validation")
        fi
    fi

    if [ "$test_logs" = true ]; then
        test_webhook_logs
    fi

    if [ "$show_config" = true ]; then
        generate_github_webhook_config
    fi

    # Print results
    echo ""
    echo -e "${COLOR_BLUE}=== Test Results ===${COLOR_NC}"

    if [ ${#failed_tests[@]} -eq 0 ]; then
        log_test "SUCCESS" "All HTTPS webhook tests passed!"
        echo ""
        echo -e "${COLOR_GREEN}✓ SSL certificates are valid${COLOR_NC}"
        echo -e "${COLOR_GREEN}✓ HTTPS connectivity working${COLOR_NC}"
        echo -e "${COLOR_GREEN}✓ Webhook service operational${COLOR_NC}"
        echo -e "${COLOR_GREEN}✓ Ready for GitHub webhook integration${COLOR_NC}"
        exit 0
    else
        log_test "ERROR" "Some tests failed: ${failed_tests[*]}"
        echo ""
        echo -e "${COLOR_RED}✗ Fix the above issues before configuring GitHub webhook${COLOR_NC}"
        exit 1
    fi
}

# Export functions for testing
export -f test_ssl_certificate_files test_certificate_details test_https_connectivity

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
