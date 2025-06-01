#!/bin/bash
# Final Setup Summary Script
# Shows complete webhook configuration with external IP detection
# Run after setup completion to get GitHub webhook configuration

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_NC='\033[0m'

# Configuration
readonly SCRIPT_NAME="show-final-setup"
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"
readonly ENV_FILE="$PROJECT_DIR/.env"

# Get script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

# Print main header
print_header() {
    echo -e "${COLOR_BLUE}${COLOR_BOLD}============================================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}${COLOR_BOLD}           🎉 RUUVI HOME SETUP COMPLETE! 🎉               ${COLOR_NC}"
    echo -e "${COLOR_BLUE}${COLOR_BOLD}============================================================${COLOR_NC}"
    echo ""
    echo -e "${COLOR_CYAN}Your Ruuvi Home system is now configured and ready to use.${COLOR_NC}"
    echo -e "${COLOR_CYAN}Here's everything you need to complete the GitHub webhook setup:${COLOR_NC}"
    echo ""
}

# Network detection and analysis
detect_and_analyze_network() {
    echo -e "${COLOR_BLUE}📡 NETWORK CONFIGURATION${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Run enhanced network detection
    echo "🔍 Detecting network configuration..."
    detect_network_configuration

    echo ""
    echo "Network Details:"
    echo "  📍 Hostname: $DETECTED_HOSTNAME"
    echo "  🏠 Local IP: $DETECTED_LOCAL_IP"
    echo "  🌐 External IP: $DETECTED_EXTERNAL_IP"
    echo "  🎯 Webhook IP: $DETECTED_PUBLIC_IP"
    echo ""

    # Network scenario analysis
    case "$NETWORK_SCENARIO" in
        "nat")
            echo -e "${COLOR_YELLOW}🏠 SCENARIO: NAT/Router Configuration${COLOR_NC}"
            echo "   Your Pi is behind a router/firewall"
            echo "   External access requires port forwarding setup"
            export SETUP_TYPE="nat"
            ;;
        "direct")
            echo -e "${COLOR_GREEN}🌐 SCENARIO: Direct Internet Connection${COLOR_NC}"
            echo "   Your Pi has a direct public IP address"
            echo "   No port forwarding needed"
            export SETUP_TYPE="direct"
            ;;
        *)
            echo -e "${COLOR_RED}❓ SCENARIO: Unknown/Local Only${COLOR_NC}"
            echo "   Network configuration could not be determined"
            echo "   Manual configuration may be required"
            export SETUP_TYPE="unknown"
            ;;
    esac
}

# Read webhook configuration from .env file
read_webhook_config() {
    local webhook_port="9000"
    local webhook_secret=""
    local https_enabled="true"

    if [ -f "$ENV_FILE" ]; then
        webhook_port=$(read_env_var "WEBHOOK_PORT" "$ENV_FILE" "9000")
        webhook_secret=$(read_env_var "WEBHOOK_SECRET" "$ENV_FILE" "")
        https_enabled=$(read_env_var "WEBHOOK_ENABLE_HTTPS" "$ENV_FILE" "true")
    fi

    export WEBHOOK_PORT="$webhook_port"
    export WEBHOOK_SECRET="$webhook_secret"
    export HTTPS_ENABLED="$https_enabled"
}

# Show GitHub webhook configuration
show_github_webhook_config() {
    echo ""
    echo -e "${COLOR_BLUE}🔗 GITHUB WEBHOOK CONFIGURATION${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    read_webhook_config

    local protocol="http"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        protocol="https"
    fi

    # Main webhook URL
    echo -e "${COLOR_GREEN}${COLOR_BOLD}🎯 WEBHOOK URL TO USE:${COLOR_NC}"
    echo -e "${COLOR_GREEN}   $protocol://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT${COLOR_NC}"
    echo ""

    # GitHub settings
    echo "📋 GitHub Repository Settings:"
    echo "   Navigate to: Repository → Settings → Webhooks → Add webhook"
    echo ""
    echo "   📍 Payload URL:"
    echo "      $protocol://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
    echo ""
    echo "   📄 Content type:"
    echo "      application/json"
    echo ""
    echo "   🔐 Secret:"
    if [ -n "$WEBHOOK_SECRET" ]; then
        echo "      $WEBHOOK_SECRET"
    else
        echo "      [Not found - check $ENV_FILE]"
    fi
    echo ""
    echo "   🔒 SSL verification:"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        echo "      ❌ Disable SSL verification (self-signed certificate)"
    else
        echo "      N/A (HTTP connection)"
    fi
    echo ""
    echo "   📨 Events:"
    echo "      ☑ Just the push event"
    echo ""
    echo "   ✅ Active:"
    echo "      ☑ Checked"
}

# Show network setup requirements
show_network_requirements() {
    echo ""
    echo -e "${COLOR_BLUE}⚙️  NETWORK SETUP REQUIREMENTS${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    case "$SETUP_TYPE" in
        "nat")
            echo -e "${COLOR_YELLOW}🏠 NAT/Router Setup Required${COLOR_NC}"
            echo ""
            echo "Your Pi is behind a router. For the webhook to work, you must:"
            echo ""
            echo "1️⃣  Configure Port Forwarding on your router:"
            echo "   • Access router admin (usually 192.168.1.1 or 192.168.0.1)"
            echo "   • Find 'Port Forwarding' or 'Virtual Servers' section"
            echo "   • Add this rule:"
            echo "     - Service Name: Ruuvi Webhook"
            echo "     - External Port: $WEBHOOK_PORT"
            echo "     - Internal IP: $DETECTED_LOCAL_IP"
            echo "     - Internal Port: $WEBHOOK_PORT"
            echo "     - Protocol: TCP"
            echo "   • Save and restart router"
            echo ""
            echo "2️⃣  Configure Firewall:"
            echo "   sudo ufw allow $WEBHOOK_PORT/tcp"
            echo ""
            echo "3️⃣  Test the configuration:"
            echo "   curl -k https://$DETECTED_EXTERNAL_IP:$WEBHOOK_PORT"
            echo ""
            echo -e "${COLOR_CYAN}🚇 Alternative: Skip Port Forwarding with Ngrok${COLOR_NC}"
            echo "   sudo snap install ngrok"
            echo "   ngrok http $WEBHOOK_PORT"
            echo "   Use the ngrok HTTPS URL in GitHub webhook settings"
            ;;
        "direct")
            echo -e "${COLOR_GREEN}✅ Direct Connection - Ready to Use${COLOR_NC}"
            echo ""
            echo "Your Pi has a direct internet connection!"
            echo ""
            echo "1️⃣  Configure Firewall (if needed):"
            echo "   sudo ufw allow $WEBHOOK_PORT/tcp"
            echo ""
            echo "2️⃣  Test the webhook:"
            echo "   curl -k https://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
            echo "   Expected: 'Ruuvi Home Webhook Server - OK'"
            echo ""
            echo "3️⃣  GitHub webhook should work immediately with the URL above!"
            ;;
        *)
            echo -e "${COLOR_RED}❓ Manual Configuration Required${COLOR_NC}"
            echo ""
            echo "Network setup could not be automatically determined."
            echo ""
            echo "🔍 Troubleshooting steps:"
            echo "1. Test internet connectivity: ping 8.8.8.8"
            echo "2. Check external IP manually: curl ifconfig.me"
            echo "3. Test local webhook: curl http://$DETECTED_LOCAL_IP:$WEBHOOK_PORT"
            echo "4. Run diagnostics: ./scripts/setup-pi/test-network-connectivity.sh"
            ;;
    esac
}

# Show service status
show_service_status() {
    echo ""
    echo -e "${COLOR_BLUE}🔧 SERVICE STATUS${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check webhook service
    if systemctl is-active ruuvi-webhook >/dev/null 2>&1; then
        echo -e "${COLOR_GREEN}✅ Webhook service: Running${COLOR_NC}"
    else
        echo -e "${COLOR_RED}❌ Webhook service: Not running${COLOR_NC}"
        echo "   Start with: sudo systemctl start ruuvi-webhook"
    fi

    # Check main application
    if systemctl is-active ruuvi-home >/dev/null 2>&1; then
        echo -e "${COLOR_GREEN}✅ Ruuvi Home application: Running${COLOR_NC}"
    elif docker ps | grep -q ruuvi; then
        echo -e "${COLOR_GREEN}✅ Ruuvi Home containers: Running${COLOR_NC}"
    else
        echo -e "${COLOR_YELLOW}⚠️  Ruuvi Home application: Not detected${COLOR_NC}"
        echo "   Start with: cd $PROJECT_DIR && docker-compose up -d"
    fi

    # Check SSL certificates
    local cert_file="$PROJECT_DIR/ssl/webhook.crt"
    if [ -f "$cert_file" ]; then
        if openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null 2>&1; then
            echo -e "${COLOR_GREEN}✅ SSL certificate: Valid${COLOR_NC}"
        else
            echo -e "${COLOR_RED}❌ SSL certificate: Expired${COLOR_NC}"
            echo "   Regenerate: ./scripts/setup-pi/generate-local-certs.sh --force"
        fi
    else
        echo -e "${COLOR_YELLOW}⚠️  SSL certificate: Not found${COLOR_NC}"
        echo "   Generate: ./scripts/setup-pi/generate-local-certs.sh"
    fi
}

# Show testing commands
show_testing_commands() {
    echo ""
    echo -e "${COLOR_BLUE}🧪 TESTING COMMANDS${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local protocol="http"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        protocol="https"
    fi

    echo "🏠 Local network test:"
    echo "   curl -k $protocol://$DETECTED_LOCAL_IP:$WEBHOOK_PORT"
    echo ""

    if [ "$SETUP_TYPE" = "nat" ]; then
        echo "🌐 External access test (after port forwarding):"
        echo "   curl -k $protocol://$DETECTED_EXTERNAL_IP:$WEBHOOK_PORT"
        echo ""
        echo "🔍 Port forwarding verification:"
        echo "   nmap -p $WEBHOOK_PORT $DETECTED_EXTERNAL_IP"
        echo ""
    fi

    echo "📊 Service diagnostics:"
    echo "   sudo systemctl status ruuvi-webhook"
    echo "   journalctl -u ruuvi-webhook -f"
    echo ""

    echo "🔬 Complete network test:"
    echo "   ./scripts/setup-pi/test-network-connectivity.sh"
}

# Show access URLs
show_access_urls() {
    echo ""
    echo -e "${COLOR_BLUE}🌐 ACCESS URLS${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local api_port=$(read_env_var "API_PORT" "$ENV_FILE" "3000")
    local frontend_port=$(read_env_var "FRONTEND_PORT" "$ENV_FILE" "80")

    echo "📱 Frontend (Web UI):"
    echo "   http://$DETECTED_LOCAL_IP:$frontend_port"
    echo ""
    echo "🔌 API Endpoint:"
    echo "   http://$DETECTED_LOCAL_IP:$api_port"
    echo ""
    echo "🎣 Webhook Endpoint:"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        echo "   https://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
    else
        echo "   http://$DETECTED_PUBLIC_IP:$WEBHOOK_PORT"
    fi
}

# Show troubleshooting info
show_troubleshooting() {
    echo ""
    echo -e "${COLOR_BLUE}🔧 TROUBLESHOOTING${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "If GitHub webhook delivery fails:"
    echo ""
    echo "1. ✅ Verify network connectivity:"
    echo "   ./scripts/setup-pi/test-network-connectivity.sh"
    echo ""
    echo "2. 🔍 Check webhook service logs:"
    echo "   journalctl -u ruuvi-webhook -f"
    echo ""
    echo "3. 🔄 Restart services if needed:"
    echo "   sudo systemctl restart ruuvi-webhook"
    echo ""
    echo "4. 🔒 For SSL issues:"
    echo "   • Self-signed cert: Disable SSL verification in GitHub"
    echo "   • Regenerate cert: ./scripts/setup-pi/generate-local-certs.sh --force"
    echo ""
    echo "5. 🌐 For connectivity issues:"
    echo "   • Check firewall: sudo ufw status"
    echo "   • Test port forwarding (NAT setup)"
    echo "   • Consider using ngrok as alternative"
}

# Show next steps
show_next_steps() {
    echo ""
    echo -e "${COLOR_GREEN}${COLOR_BOLD}🚀 NEXT STEPS${COLOR_NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. 📝 Copy the webhook URL and secret from above"
    echo "2. 🔗 Go to your GitHub repository settings"
    echo "3. ➕ Add a new webhook with the provided configuration"
    echo "4. 🧪 Test by pushing to your main branch"
    echo "5. 📊 Monitor webhook deliveries in GitHub settings"
    echo ""
    if [ "$SETUP_TYPE" = "nat" ]; then
        echo -e "${COLOR_YELLOW}⚠️  Don't forget to configure port forwarding on your router!${COLOR_NC}"
        echo ""
    fi
    echo -e "${COLOR_CYAN}💡 Tip: Bookmark this output or run this script again anytime:${COLOR_NC}"
    echo "   ./scripts/setup-pi/show-final-setup.sh"
}

# Main function
main() {
    print_header
    detect_and_analyze_network
    show_github_webhook_config
    show_network_requirements
    show_service_status
    show_testing_commands
    show_access_urls
    show_troubleshooting
    show_next_steps

    echo ""
    echo -e "${COLOR_GREEN}${COLOR_BOLD}🎉 Setup complete! Your Ruuvi Home system is ready to go! 🎉${COLOR_NC}"
    echo ""
}

# Show usage if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Shows complete setup summary and GitHub webhook configuration"
    echo "Run this script after completing the Ruuvi Home setup process."
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "This script displays:"
    echo "• Network configuration and external IP detection"
    echo "• GitHub webhook settings"
    echo "• Network setup requirements (port forwarding, etc.)"
    echo "• Service status"
    echo "• Testing commands"
    echo "• Troubleshooting information"
    exit 0
fi

# Run main function
main "$@"
