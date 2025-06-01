#!/bin/bash
# GitHub Webhook Configuration Guide
# Shows exact settings needed for GitHub webhook setup

set -e

readonly SCRIPT_NAME="show-github-webhook-config"
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"
readonly ENV_FILE="$PROJECT_DIR/.env"
readonly SSL_CERT_PATH="$PROJECT_DIR/ssl/webhook.crt"

# Source shared configuration library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m'

print_header() {
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}    GitHub Webhook Configuration Guide     ${COLOR_NC}"
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo ""
}

get_pi_info() {
    echo -e "${COLOR_CYAN}=== Raspberry Pi Information ===${COLOR_NC}"
    echo ""

    # Use enhanced network detection from shared configuration library
    echo "Detecting network configuration..."
    detect_network_configuration

    echo ""
    echo "Network Details:"
    echo "  Hostname: $DETECTED_HOSTNAME"
    echo "  Local/Private IP: $DETECTED_LOCAL_IP"
    echo "  External/Public IP: $DETECTED_EXTERNAL_IP"
    echo "  Webhook IP (recommended): $DETECTED_PUBLIC_IP"

    # Display network scenario with enhanced information
    echo ""
    case "$NETWORK_SCENARIO" in
        "nat")
            echo -e "${COLOR_YELLOW}🏠 Network Scenario: NAT/Router (Port forwarding needed)${COLOR_NC}"
            echo "   Your Pi is behind a router/firewall"
            echo "   Local IP ($DETECTED_LOCAL_IP) is different from public IP ($DETECTED_EXTERNAL_IP)"
            echo "   GitHub webhooks must reach your public IP: $DETECTED_EXTERNAL_IP"
            echo -e "${COLOR_YELLOW}   ⚠️  Port forwarding required for webhook to work${COLOR_NC}"
            ;;
        "direct")
            echo -e "${COLOR_GREEN}🌐 Network Scenario: Direct Internet Connection${COLOR_NC}"
            echo "   Your Pi appears to have a direct public IP"
            echo "   GitHub webhooks can reach directly: $DETECTED_PUBLIC_IP"
            echo -e "${COLOR_GREEN}   ✅ No port forwarding needed${COLOR_NC}"
            ;;
        *)
            echo -e "${COLOR_RED}❓ Network Scenario: Unknown or Local-only${COLOR_NC}"
            echo "   Could not determine external connectivity"
            echo "   Using local IP for webhook: $DETECTED_PUBLIC_IP"
            echo -e "${COLOR_RED}   ⚠️  May require manual network configuration${COLOR_NC}"
            ;;
    esac
    echo ""

    # Export for other functions (maintaining compatibility)
    export PI_LOCAL_IP="$DETECTED_LOCAL_IP"
    export PI_PUBLIC_IP="$DETECTED_EXTERNAL_IP"
}

get_webhook_config() {
    # Use shared configuration library for reading env vars
    export WEBHOOK_PORT=$(read_env_var "WEBHOOK_PORT" "$ENV_FILE" "$DEFAULT_WEBHOOK_PORT")
    export WEBHOOK_SECRET=$(read_env_var "WEBHOOK_SECRET" "$ENV_FILE" "")
    export HTTPS_ENABLED=$(read_env_var "WEBHOOK_ENABLE_HTTPS" "$ENV_FILE" "true")
}

check_certificate_type() {
    if [ ! -f "$SSL_CERT_PATH" ]; then
        export CERT_TYPE="none"
        export SSL_VERIFICATION="n/a"
        return
    fi

    # Check if it's a Let's Encrypt certificate
    local cert_issuer=$(openssl x509 -in "$SSL_CERT_PATH" -noout -issuer 2>/dev/null || echo "")
    if echo "$cert_issuer" | grep -q "Let's Encrypt"; then
        export CERT_TYPE="letsencrypt"
        export SSL_VERIFICATION="enable"
    else
        export CERT_TYPE="self-signed"
        export SSL_VERIFICATION="disable"
    fi
}

show_webhook_url() {
    echo -e "${COLOR_CYAN}=== Webhook URL Configuration ===${COLOR_NC}"

    local protocol="http"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        protocol="https"
        echo -e "${COLOR_GREEN}Protocol: HTTPS (Secure)${COLOR_NC}"
    else
        echo -e "${COLOR_YELLOW}Protocol: HTTP (Insecure)${COLOR_NC}"
    fi
    echo ""

    # Show the recommended webhook URL prominently
    echo -e "${COLOR_GREEN}🎯 RECOMMENDED WEBHOOK URL:${COLOR_NC}"
    echo -e "${COLOR_GREEN}   $protocol://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT${COLOR_NC}"
    echo ""

    case "$NETWORK_SCENARIO" in
        "nat")
            echo -e "${COLOR_YELLOW}📋 NAT/Router Setup Required${COLOR_NC}"
            echo ""
            echo "Your Pi is behind a router. To use the webhook URL above:"
            echo ""
            echo "🔧 Required: Configure Router Port Forwarding"
            echo "   1. Access your router admin panel (usually 192.168.1.1 or 192.168.0.1)"
            echo "   2. Find 'Port Forwarding' or 'Virtual Servers' section"
            echo "   3. Add this rule:"
            echo "      • Service Name: Ruuvi Webhook"
            echo "      • External Port: $WEBHOOK_PORT"
            echo "      • Internal IP: $PI_LOCAL_IP"
            echo "      • Internal Port: $WEBHOOK_PORT"
            echo "      • Protocol: TCP"
            echo "   4. Save and restart router"
            echo ""
            echo "🧪 Test after setup:"
            echo "   curl -k $protocol://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
            echo ""
            echo -e "${COLOR_BLUE}🚇 Alternative: Skip Port Forwarding with Tunnel${COLOR_NC}"
            echo "   • ngrok: sudo snap install ngrok && ngrok http $WEBHOOK_PORT"
            echo "   • Use the provided https://xxxxx.ngrok.io URL instead"
            ;;
        "direct")
            echo -e "${COLOR_GREEN}✅ Direct Connection - Ready to Use${COLOR_NC}"
            echo ""
            echo "Your Pi has a direct internet connection."
            echo "The webhook URL above should work immediately."
            echo ""
            echo "🧪 Test connection:"
            echo "   curl -k $protocol://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
            echo "   Expected response: 'Ruuvi Home Webhook Server - OK'"
            ;;
        *)
            echo -e "${COLOR_RED}⚠️  Network Setup Unclear${COLOR_NC}"
            echo ""
            echo "Could not determine your network configuration."
            echo "This may be because:"
            echo "• Internet connectivity is limited"
            echo "• Firewall is blocking external IP detection"
            echo "• Running in a local-only environment"
            echo ""
            echo "🔍 Try these options:"
            echo "1. Use local IP for testing: $protocol://$PI_LOCAL_IP:$WEBHOOK_PORT"
            echo "2. Configure port forwarding if behind router"
            echo "3. Use ngrok tunnel for external access"
            echo "4. Check internet connectivity: curl ifconfig.me"
            ;;
    esac
    echo ""
}

show_github_settings() {
    echo -e "${COLOR_CYAN}=== GitHub Webhook Settings ===${COLOR_NC}"
    echo ""
    echo "Navigate to: GitHub Repository → Settings → Webhooks → Add webhook"
    echo ""
    echo -e "${COLOR_YELLOW}Required Settings:${COLOR_NC}"
    echo ""

    # Payload URL
    local protocol="http"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        protocol="https"
    fi

    echo "📍 Payload URL:"
    echo "   $protocol://$DETECTED_LOCAL_IP:$WEBHOOK_PORT"
    echo ""

    # Content Type
    echo "📄 Content type:"
    echo "   application/json"
    echo ""

    # Secret
    echo "🔐 Secret:"
    if [ -n "$WEBHOOK_SECRET" ]; then
        echo "   $WEBHOOK_SECRET"
    else
        echo "   [Not found - check $ENV_FILE]"
    fi
    echo ""

    # SSL Verification
    echo "🔒 SSL verification:"
    case "$SSL_VERIFICATION" in
        "enable")
            echo -e "   ✅ ${COLOR_GREEN}Enable SSL verification${COLOR_NC} (Let's Encrypt certificate)"
            ;;
        "disable")
            echo -e "   ❌ ${COLOR_RED}Disable SSL verification${COLOR_NC} (Self-signed certificate)"
            ;;
        "n/a")
            echo "   N/A (HTTP connection)"
            ;;
    esac
    echo ""

    # Events
    echo "📨 Which events would you like to trigger this webhook?"
    echo "   ○ Just the push event (Recommended)"
    echo "   ○ Let me select individual events"
    echo ""

    # Active
    echo "✅ Active:"
    echo "   ☑ Checked"
    echo ""
}

show_certificate_info() {
    if [ "$HTTPS_ENABLED" != "true" ]; then
        return
    fi

    echo -e "${COLOR_CYAN}=== SSL Certificate Information ===${COLOR_NC}"

    if [ ! -f "$SSL_CERT_PATH" ]; then
        echo -e "${COLOR_RED}❌ No SSL certificate found${COLOR_NC}"
        echo "Run: sudo ./scripts/setup-pi/generate-local-certs.sh"
        echo ""
        return
    fi

    # Certificate details
    local cert_subject=$(openssl x509 -in "$SSL_CERT_PATH" -noout -subject 2>/dev/null | sed 's/subject= *//' || echo "unknown")
    local cert_expiry=$(openssl x509 -in "$SSL_CERT_PATH" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "unknown")

    echo "Certificate Type: $CERT_TYPE"
    echo "Subject: $cert_subject"
    echo "Expires: $cert_expiry"

    # Check expiry
    if openssl x509 -in "$SSL_CERT_PATH" -checkend 0 >/dev/null 2>&1; then
        echo -e "Status: ${COLOR_GREEN}✅ Valid${COLOR_NC}"
    else
        echo -e "Status: ${COLOR_RED}❌ Expired${COLOR_NC}"
    fi

    # Show Subject Alternative Names
    local san_info=$(openssl x509 -in "$SSL_CERT_PATH" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^[[:space:]]*//' || echo "")
    if [ -n "$san_info" ]; then
        echo "Valid for: $san_info"
    fi

    echo ""
}

show_network_requirements() {
    echo -e "${COLOR_CYAN}=== Network Requirements & Diagnostics ===${COLOR_NC}"
    echo ""

    # Show current network status
    echo "📊 Current Network Status:"
    echo "   Local IP: $DETECTED_LOCAL_IP"
    echo "   Public IP: $DETECTED_EXTERNAL_IP"
    echo "   Webhook will use: $DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
    echo ""

    case "$NETWORK_SCENARIO" in
        "nat")
            echo -e "${COLOR_YELLOW}🏠 NAT/Router Configuration Required${COLOR_NC}"
            echo ""
            echo "Your setup requires port forwarding because:"
            echo "• Local IP ($DETECTED_LOCAL_IP) ≠ Public IP ($DETECTED_EXTERNAL_IP)"
            echo "• GitHub needs to reach $DETECTED_EXTERNAL_IP:$WEBHOOK_PORT"
            echo "• Router must forward external traffic to internal Pi"
            echo ""
            echo "📋 Port Forwarding Steps:"
            echo "   1. Router admin: http://192.168.1.1 (or your gateway IP)"
            echo "   2. Port Forwarding/Virtual Servers section"
            echo "   3. Add rule: External $WEBHOOK_PORT → $DETECTED_LOCAL_IP:$WEBHOOK_PORT"
            echo "   4. Protocol: TCP, Enable/Active: Yes"
            echo ""
            echo "🧪 Verification Commands:"
            echo "   Local test: curl -k https://$DETECTED_LOCAL_IP:$WEBHOOK_PORT"
            echo "   Public test: curl -k https://$DETECTED_EXTERNAL_IP:$WEBHOOK_PORT"
            echo "   Port check: nmap -p $WEBHOOK_PORT $DETECTED_EXTERNAL_IP"
            echo ""
            ;;
        "direct")
            echo -e "${COLOR_GREEN}✅ Direct Connection Ready${COLOR_NC}"
            echo ""
            echo "Your Pi has a direct internet connection:"
            echo "• No NAT/router between Pi and internet"
            echo "• GitHub can reach Pi directly"
            echo "• No port forwarding needed"
            echo ""
            echo "🧪 Quick Test:"
            echo "   curl -k https://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
            echo ""
            ;;
        *)
            echo -e "${COLOR_RED}❓ Network Diagnosis Needed${COLOR_NC}"
            echo ""
            echo "Could not determine network setup. Possible causes:"
            echo "• Limited internet connectivity"
            echo "• Firewall blocking IP detection services"
            echo "• Local/development environment"
            echo ""
            echo "🔍 Diagnostic Steps:"
            echo "   1. Test connectivity: ping 8.8.8.8"
            echo "   2. Check public IP manually: curl ifconfig.me"
            echo "   3. Test local webhook: curl http://$DETECTED_LOCAL_IP:$WEBHOOK_PORT"
            echo "   4. Check firewall: sudo ufw status"
            echo ""
            ;;
    esac

    echo "🔥 Firewall Configuration:"
    echo "   sudo ufw allow $WEBHOOK_PORT/tcp"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        echo "   sudo ufw allow 80/tcp  # For Let's Encrypt validation"
    fi
    echo ""

    echo "🚇 Alternative: Tunnel Services (No Router Config Needed)"
    echo "   ngrok:"
    echo "     sudo snap install ngrok"
    echo "     ngrok http $WEBHOOK_PORT"
    echo "     Use: https://xxxxx.ngrok.io (from ngrok output)"
    echo ""
    echo "   Cloudflare Tunnel:"
    echo "     curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o cloudflared.deb"
    echo "     sudo dpkg -i cloudflared.deb"
    echo "     cloudflared tunnel --url localhost:$WEBHOOK_PORT"
    echo ""
}

show_testing_commands() {
    local protocol="http"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        protocol="https"
    fi

    echo -e "${COLOR_CYAN}=== Testing Commands ===${COLOR_NC}"
    echo ""

    echo "🏠 Local Network Test:"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        echo "  curl -k $protocol://$PI_LOCAL_IP:$WEBHOOK_PORT"
    else
        echo "  curl $protocol://$PI_LOCAL_IP:$WEBHOOK_PORT"
    fi
    echo "  Expected: 'Ruuvi Home Webhook Server - OK'"
    echo ""

    if [ "$NETWORK_SCENARIO" = "nat" ]; then
        echo "🌐 Public Access Test (after port forwarding):"
        echo "  curl -k $protocol://$PI_PUBLIC_IP:$WEBHOOK_PORT"
        echo "  Expected: 'Ruuvi Home Webhook Server - OK'"
        echo ""

        echo "🔍 Port Forwarding Check:"
        echo "  nmap -p $WEBHOOK_PORT $PI_PUBLIC_IP"
        echo "  Expected: '$WEBHOOK_PORT/tcp open'"
        echo ""
    fi

    echo "🔧 Service Diagnostics:"
    echo "  sudo systemctl status ruuvi-webhook"
    echo "  journalctl -u ruuvi-webhook -f"
    echo ""

    echo "🔒 HTTPS Certificate Test:"
    echo "  ./scripts/setup-pi/test-webhook-https.sh"
    echo ""

    echo "📡 Network Connectivity:"
    echo "  ping google.com"
    echo "  curl ifconfig.me  # Check public IP"
    echo ""
}

show_troubleshooting() {
    echo -e "${COLOR_CYAN}=== Troubleshooting ===${COLOR_NC}"
    echo ""
    echo "❌ GitHub webhook delivery failed:"
    echo "   • Check Pi is accessible from internet"
    echo "   • Verify port forwarding configuration"
    echo "   • Check firewall settings"
    echo "   • Verify SSL verification setting matches certificate"
    echo ""
    echo "❌ SSL certificate errors:"
    echo "   • For self-signed: Disable SSL verification in GitHub"
    echo "   • For Let's Encrypt: Ensure certificate is valid"
    echo "   • Regenerate: sudo ./scripts/setup-pi/generate-local-certs.sh --force"
    echo ""
    echo "❌ Webhook service not responding:"
    echo "   • Check service: sudo systemctl status ruuvi-webhook"
    echo "   • Restart: sudo systemctl restart ruuvi-webhook"
    echo "   • Check logs: journalctl -u ruuvi-webhook -f"
    echo ""
}

main() {
    print_header
    get_pi_info
    get_webhook_config
    check_certificate_type
    show_webhook_url
    show_github_settings
    show_certificate_info
    show_network_requirements
    show_testing_commands
    show_troubleshooting

    echo -e "${COLOR_GREEN}🎉 Configuration guide complete!${COLOR_NC}"
    echo ""
    echo "Next steps:"
    echo "1. Copy the webhook URL and secret above"
    echo "2. Go to your GitHub repository settings"
    echo "3. Add a new webhook with the provided settings"
    echo "4. Test by pushing to your main branch"
    echo ""
}

# Show usage help
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help    Show this help message"
    echo ""
    echo "This script displays the exact configuration needed"
    echo "to set up a GitHub webhook for your Ruuvi Home Pi."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

# Run main function
main "$@"
