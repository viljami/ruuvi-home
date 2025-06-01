#!/bin/bash
# Network Connectivity Test Script for Ruuvi Home Setup
# Comprehensive diagnostics for external IP detection and webhook connectivity

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m'

# Test configuration
readonly WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"
readonly TEST_TIMEOUT=5
readonly MAX_RETRIES=3

# Get script directory and source config library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

# Test framework
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_test() {
    local level="$1"
    local message="$2"
    case "$level" in
        "PASS")
            echo -e "${COLOR_GREEN}[PASS]${COLOR_NC} $message"
            ((PASS_COUNT++))
            ;;
        "FAIL")
            echo -e "${COLOR_RED}[FAIL]${COLOR_NC} $message"
            ((FAIL_COUNT++))
            ;;
        "WARN")
            echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $message"
            ((WARN_COUNT++))
            ;;
        "INFO")
            echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $message"
            ;;
        "STEP")
            echo -e "${COLOR_CYAN}[TEST]${COLOR_NC} $message"
            ;;
    esac
    ((TEST_COUNT++))
}

print_header() {
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}    Ruuvi Home Network Connectivity Tests      ${COLOR_NC}"
    echo -e "${COLOR_BLUE}================================================${COLOR_NC}"
    echo ""
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${COLOR_CYAN}=== $title ===${COLOR_NC}"
    echo ""
}

# Basic connectivity tests
test_basic_connectivity() {
    print_section "Basic Connectivity Tests"

    log_test "STEP" "Testing internet connectivity"

    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        log_test "PASS" "DNS resolution working"
    else
        log_test "FAIL" "DNS resolution failed"
        return 1
    fi

    # Test ping connectivity
    if ping -c 3 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_test "PASS" "Internet connectivity via ping"
    else
        log_test "FAIL" "No internet connectivity via ping"
    fi

    # Test HTTP connectivity
    if curl -s --connect-timeout $TEST_TIMEOUT google.com >/dev/null 2>&1; then
        log_test "PASS" "HTTP connectivity working"
    else
        log_test "FAIL" "HTTP connectivity failed"
    fi

    # Test HTTPS connectivity
    if curl -s --connect-timeout $TEST_TIMEOUT https://google.com >/dev/null 2>&1; then
        log_test "PASS" "HTTPS connectivity working"
    else
        log_test "FAIL" "HTTPS connectivity failed"
    fi
}

# Test external IP detection
test_external_ip_detection() {
    print_section "External IP Detection Tests"

    log_test "STEP" "Testing external IP detection services"

    local services_tested=0
    local services_working=0
    local detected_ips=()

    for service in "${EXTERNAL_IP_SERVICES[@]}"; do
        ((services_tested++))
        log_test "INFO" "Testing service: $service"

        local ip=""
        if ip=$(curl -s --connect-timeout $TEST_TIMEOUT --max-time $((TEST_TIMEOUT * 2)) "$service" 2>/dev/null | tr -d '[:space:]'); then
            if is_valid_ip "$ip"; then
                log_test "PASS" "Service $service returned: $ip"
                detected_ips+=("$ip")
                ((services_working++))
            else
                log_test "FAIL" "Service $service returned invalid IP: '$ip'"
            fi
        else
            log_test "FAIL" "Service $service failed to respond"
        fi
    done

    echo ""
    log_test "INFO" "External IP detection summary:"
    log_test "INFO" "  Services tested: $services_tested"
    log_test "INFO" "  Services working: $services_working"

    if [ $services_working -gt 0 ]; then
        # Check if all working services agree on IP
        local unique_ips=($(printf '%s\n' "${detected_ips[@]}" | sort -u))
        if [ ${#unique_ips[@]} -eq 1 ]; then
            log_test "PASS" "All working services agree on IP: ${unique_ips[0]}"
            export CONSENSUS_EXTERNAL_IP="${unique_ips[0]}"
        else
            log_test "WARN" "Services returned different IPs: ${unique_ips[*]}"
            export CONSENSUS_EXTERNAL_IP="${detected_ips[0]}"
        fi
    else
        log_test "FAIL" "No external IP detection services working"
        return 1
    fi
}

# Test local network configuration
test_local_network() {
    print_section "Local Network Configuration"

    log_test "STEP" "Analyzing local network setup"

    # Get local IP
    local local_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    if [ "$local_ip" != "unknown" ] && is_valid_ip "$local_ip"; then
        log_test "PASS" "Local IP detected: $local_ip"
        export TEST_LOCAL_IP="$local_ip"
    else
        log_test "FAIL" "Could not detect valid local IP"
        return 1
    fi

    # Check hostname resolution
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    log_test "INFO" "Hostname: $hostname"

    # Test if local IP is private
    if [[ "$local_ip" =~ ^10\. ]] || [[ "$local_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$local_ip" =~ ^192\.168\. ]]; then
        log_test "INFO" "Local IP is private (RFC 1918) - NAT likely"
        export IS_PRIVATE_IP=true
    else
        log_test "INFO" "Local IP appears to be public"
        export IS_PRIVATE_IP=false
    fi

    # Get gateway
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1 2>/dev/null || echo "unknown")
    if [ "$gateway" != "unknown" ]; then
        log_test "PASS" "Default gateway: $gateway"

        # Test gateway connectivity
        if ping -c 2 -W 2 "$gateway" >/dev/null 2>&1; then
            log_test "PASS" "Gateway is reachable"
        else
            log_test "WARN" "Gateway ping failed"
        fi
    else
        log_test "WARN" "Could not detect default gateway"
    fi
}

# Network scenario analysis
test_network_scenario() {
    print_section "Network Scenario Analysis"

    log_test "STEP" "Determining network deployment scenario"

    if [ -z "${TEST_LOCAL_IP:-}" ] || [ -z "${CONSENSUS_EXTERNAL_IP:-}" ]; then
        log_test "FAIL" "Missing network information for scenario analysis"
        return 1
    fi

    echo ""
    log_test "INFO" "Network configuration summary:"
    log_test "INFO" "  Local IP: $TEST_LOCAL_IP"
    log_test "INFO" "  External IP: $CONSENSUS_EXTERNAL_IP"
    log_test "INFO" "  Private IP range: ${IS_PRIVATE_IP:-unknown}"

    if [ "$TEST_LOCAL_IP" = "$CONSENSUS_EXTERNAL_IP" ]; then
        log_test "PASS" "Direct internet connection detected"
        log_test "INFO" "Webhook URL should be: https://$TEST_LOCAL_IP:$WEBHOOK_PORT"
        export NETWORK_SCENARIO="direct"
    elif [ "${IS_PRIVATE_IP:-false}" = "true" ]; then
        log_test "PASS" "NAT/Router configuration detected"
        log_test "WARN" "Port forwarding required for external webhook access"
        log_test "INFO" "External webhook URL: https://$CONSENSUS_EXTERNAL_IP:$WEBHOOK_PORT"
        log_test "INFO" "Internal webhook URL: https://$TEST_LOCAL_IP:$WEBHOOK_PORT"
        export NETWORK_SCENARIO="nat"
    else
        log_test "WARN" "Unusual network configuration detected"
        export NETWORK_SCENARIO="unusual"
    fi
}

# Test webhook service
test_webhook_service() {
    print_section "Webhook Service Tests"

    log_test "STEP" "Testing webhook service availability"

    # Check if webhook service is running
    if systemctl is-active ruuvi-webhook >/dev/null 2>&1; then
        log_test "PASS" "Webhook service is running"
    elif [ -f "$PROJECT_DIR/scripts/deploy-webhook.py" ]; then
        log_test "WARN" "Webhook service not running, but script exists"
    else
        log_test "FAIL" "Webhook service not found"
        return 1
    fi

    # Test local webhook connectivity
    log_test "STEP" "Testing local webhook connectivity"

    local local_http_url="http://$TEST_LOCAL_IP:$WEBHOOK_PORT"
    local local_https_url="https://$TEST_LOCAL_IP:$WEBHOOK_PORT"

    # Test HTTP
    if curl -s --connect-timeout $TEST_TIMEOUT "$local_http_url" >/dev/null 2>&1; then
        log_test "PASS" "Local HTTP webhook accessible: $local_http_url"
    else
        log_test "FAIL" "Local HTTP webhook not accessible: $local_http_url"
    fi

    # Test HTTPS (allow self-signed)
    if curl -s -k --connect-timeout $TEST_TIMEOUT "$local_https_url" >/dev/null 2>&1; then
        log_test "PASS" "Local HTTPS webhook accessible: $local_https_url"
    else
        log_test "WARN" "Local HTTPS webhook not accessible: $local_https_url"
    fi
}

# Test port forwarding (for NAT scenarios)
test_port_forwarding() {
    if [ "${NETWORK_SCENARIO:-}" != "nat" ]; then
        return 0
    fi

    print_section "Port Forwarding Tests"

    log_test "STEP" "Testing external port forwarding"

    if [ -z "${CONSENSUS_EXTERNAL_IP:-}" ]; then
        log_test "FAIL" "No external IP available for testing"
        return 1
    fi

    local external_url="https://$CONSENSUS_EXTERNAL_IP:$WEBHOOK_PORT"

    # Test if port is open from external perspective
    log_test "INFO" "Testing external webhook access: $external_url"

    if timeout $TEST_TIMEOUT bash -c "echo >/dev/tcp/$CONSENSUS_EXTERNAL_IP/$WEBHOOK_PORT" 2>/dev/null; then
        log_test "PASS" "External port $WEBHOOK_PORT is reachable"

        # Try actual HTTP request
        if curl -s -k --connect-timeout $TEST_TIMEOUT "$external_url" >/dev/null 2>&1; then
            log_test "PASS" "External webhook is responding"
        else
            log_test "WARN" "Port is open but webhook not responding"
        fi
    else
        log_test "FAIL" "External port $WEBHOOK_PORT is not reachable"
        log_test "INFO" "This likely means port forwarding is not configured"
    fi
}

# Test firewall configuration
test_firewall() {
    print_section "Firewall Configuration Tests"

    log_test "STEP" "Testing firewall configuration"

    # Check if ufw is installed and active
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null | head -1)
        log_test "INFO" "UFW status: $ufw_status"

        if echo "$ufw_status" | grep -q "Status: active"; then
            log_test "INFO" "UFW firewall is active"

            # Check if webhook port is allowed
            if ufw status | grep -q "$WEBHOOK_PORT"; then
                log_test "PASS" "Webhook port $WEBHOOK_PORT is allowed in firewall"
            else
                log_test "FAIL" "Webhook port $WEBHOOK_PORT not allowed in firewall"
                log_test "INFO" "Run: sudo ufw allow $WEBHOOK_PORT/tcp"
            fi

            # Check if HTTP port is allowed (for Let's Encrypt)
            if ufw status | grep -q "80/tcp"; then
                log_test "PASS" "HTTP port 80 is allowed (good for Let's Encrypt)"
            else
                log_test "WARN" "HTTP port 80 not allowed (needed for Let's Encrypt)"
                log_test "INFO" "Run: sudo ufw allow 80/tcp"
            fi
        else
            log_test "INFO" "UFW firewall is not active"
        fi
    else
        log_test "INFO" "UFW not installed, checking iptables"

        if command -v iptables >/dev/null 2>&1; then
            local iptables_rules=$(iptables -L 2>/dev/null | wc -l)
            if [ "$iptables_rules" -gt 10 ]; then
                log_test "WARN" "Custom iptables rules detected - manual review needed"
            else
                log_test "INFO" "Minimal iptables rules - likely no firewall blocking"
            fi
        fi
    fi
}

# Test SSL certificates
test_ssl_certificates() {
    print_section "SSL Certificate Tests"

    log_test "STEP" "Testing SSL certificate configuration"

    local ssl_dir="$PROJECT_DIR/ssl"
    local cert_file="$ssl_dir/webhook.crt"
    local key_file="$ssl_dir/webhook.key"

    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        log_test "PASS" "SSL certificate files exist"

        # Check certificate validity
        if openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null 2>&1; then
            log_test "PASS" "SSL certificate is valid and not expired"

            # Get certificate details
            local cert_subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject= *//' || echo "unknown")
            local cert_expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "unknown")

            log_test "INFO" "Certificate subject: $cert_subject"
            log_test "INFO" "Certificate expires: $cert_expiry"

            # Check if certificate includes current IPs
            local cert_sans=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^[[:space:]]*//' || echo "")
            if [ -n "$cert_sans" ]; then
                log_test "INFO" "Certificate valid for: $cert_sans"

                if echo "$cert_sans" | grep -q "$TEST_LOCAL_IP"; then
                    log_test "PASS" "Certificate includes local IP: $TEST_LOCAL_IP"
                else
                    log_test "WARN" "Certificate does not include local IP: $TEST_LOCAL_IP"
                fi
            fi
        else
            log_test "FAIL" "SSL certificate is invalid or expired"
        fi

        # Test key file
        if openssl rsa -in "$key_file" -check >/dev/null 2>&1; then
            log_test "PASS" "SSL private key is valid"
        else
            log_test "FAIL" "SSL private key is invalid"
        fi
    else
        log_test "WARN" "SSL certificate files not found"
        log_test "INFO" "Run: ./scripts/setup-pi/generate-local-certs.sh"
    fi
}

# Generate recommendations
generate_recommendations() {
    print_section "Recommendations & Next Steps"

    echo "Based on the test results, here are the recommended actions:"
    echo ""

    case "${NETWORK_SCENARIO:-unknown}" in
        "direct")
            echo -e "${COLOR_GREEN}✅ Direct Connection Setup${COLOR_NC}"
            echo "Your Pi has a direct internet connection. Recommended actions:"
            echo "1. Ensure webhook service is running"
            echo "2. Configure GitHub webhook with: https://$TEST_LOCAL_IP:$WEBHOOK_PORT"
            echo "3. Enable SSL verification in GitHub webhook settings"
            ;;
        "nat")
            echo -e "${COLOR_YELLOW}🏠 NAT/Router Setup Required${COLOR_NC}"
            echo "Your Pi is behind a router. Required actions:"
            echo "1. Configure port forwarding on your router:"
            echo "   External Port: $WEBHOOK_PORT → Internal IP: $TEST_LOCAL_IP → Internal Port: $WEBHOOK_PORT"
            echo "2. Configure GitHub webhook with: https://$CONSENSUS_EXTERNAL_IP:$WEBHOOK_PORT"
            echo "3. Test external connectivity after port forwarding setup"
            echo ""
            echo "Alternative: Use ngrok tunnel to avoid port forwarding:"
            echo "   sudo snap install ngrok"
            echo "   ngrok http $WEBHOOK_PORT"
            ;;
        *)
            echo -e "${COLOR_RED}❓ Network Configuration Unclear${COLOR_NC}"
            echo "Manual investigation required:"
            echo "1. Verify internet connectivity"
            echo "2. Check router/firewall configuration"
            echo "3. Consider using ngrok for external access"
            ;;
    esac

    echo ""

    # Firewall recommendations
    if [ $FAIL_COUNT -gt 0 ]; then
        echo -e "${COLOR_YELLOW}🔥 Firewall Actions Needed:${COLOR_NC}"
        echo "sudo ufw allow $WEBHOOK_PORT/tcp"
        echo "sudo ufw allow 80/tcp  # For Let's Encrypt"
        echo ""
    fi

    # SSL recommendations
    if [ ! -f "$PROJECT_DIR/ssl/webhook.crt" ]; then
        echo -e "${COLOR_BLUE}🔒 SSL Certificate Setup:${COLOR_NC}"
        echo "./scripts/setup-pi/generate-local-certs.sh"
        echo ""
    fi

    echo -e "${COLOR_CYAN}📋 Testing Commands:${COLOR_NC}"
    echo "# Test local webhook:"
    echo "curl -k https://$TEST_LOCAL_IP:$WEBHOOK_PORT"
    echo ""
    if [ "${NETWORK_SCENARIO:-}" = "nat" ]; then
        echo "# Test external webhook (after port forwarding):"
        echo "curl -k https://$CONSENSUS_EXTERNAL_IP:$WEBHOOK_PORT"
        echo ""
    fi
    echo "# Re-run this diagnostic:"
    echo "./scripts/setup-pi/test-network-connectivity.sh"
}

# Print test summary
print_summary() {
    echo ""
    echo -e "${COLOR_BLUE}=== Test Summary ===${COLOR_NC}"
    echo "Total tests: $TEST_COUNT"
    echo -e "Passed: ${COLOR_GREEN}$PASS_COUNT${COLOR_NC}"
    echo -e "Warnings: ${COLOR_YELLOW}$WARN_COUNT${COLOR_NC}"
    echo -e "Failed: ${COLOR_RED}$FAIL_COUNT${COLOR_NC}"
    echo ""

    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "${COLOR_GREEN}🎉 All critical tests passed!${COLOR_NC}"
        if [ $WARN_COUNT -gt 0 ]; then
            echo -e "${COLOR_YELLOW}⚠️  Some warnings need attention${COLOR_NC}"
        fi
    else
        echo -e "${COLOR_RED}❌ Some tests failed - action required${COLOR_NC}"
    fi
}

# Main test runner
main() {
    print_header

    echo "This script will test your network connectivity and webhook configuration."
    echo "It helps diagnose issues with external IP detection and GitHub webhook setup."
    echo ""

    # Run all tests
    test_basic_connectivity || true
    test_external_ip_detection || true
    test_local_network || true
    test_network_scenario || true
    test_webhook_service || true
    test_port_forwarding || true
    test_firewall || true
    test_ssl_certificates || true

    # Generate recommendations
    generate_recommendations

    # Print summary
    print_summary

    # Exit with appropriate code
    if [ $FAIL_COUNT -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Network connectivity test script for Ruuvi Home setup"
            echo ""
            echo "Options:"
            echo "  --help, -h          Show this help message"
            echo "  --webhook-port PORT Set webhook port (default: 9000)"
            echo "  --timeout SECONDS   Set connection timeout (default: 5)"
            echo ""
            echo "This script tests:"
            echo "• Basic internet connectivity"
            echo "• External IP detection"
            echo "• Local network configuration"
            echo "• Webhook service availability"
            echo "• Port forwarding (if applicable)"
            echo "• Firewall configuration"
            echo "• SSL certificate setup"
            exit 0
            ;;
        --webhook-port)
            WEBHOOK_PORT="$2"
            shift 2
            ;;
        --timeout)
            TEST_TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
