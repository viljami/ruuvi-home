#!/bin/bash
# GitHub Webhook Configuration Guide
# Shows exact settings needed for GitHub webhook setup

set -e

readonly SCRIPT_NAME="show-github-webhook-config"
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"
readonly ENV_FILE="$PROJECT_DIR/.env"
readonly SSL_CERT_PATH="$PROJECT_DIR/ssl/webhook.crt"

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
    local hostname=$(hostname 2>/dev/null || echo "raspberrypi")
    local local_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    local external_ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo "unknown")
    
    echo -e "${COLOR_CYAN}=== Raspberry Pi Information ===${COLOR_NC}"
    echo "Hostname: $hostname"
    echo "Local/Private IP: $local_ip"
    echo "Public IP: $external_ip"
    
    # Detect network scenario
    if [ "$external_ip" != "unknown" ] && [ "$external_ip" != "$local_ip" ]; then
        echo -e "${COLOR_YELLOW}Network Scenario: NAT/Router (Port forwarding needed)${COLOR_NC}"
        export NETWORK_SCENARIO="nat"
    elif [ "$external_ip" = "$local_ip" ]; then
        echo -e "${COLOR_GREEN}Network Scenario: Direct Internet Connection${COLOR_NC}"
        export NETWORK_SCENARIO="direct"
    else
        echo -e "${COLOR_RED}Network Scenario: Unknown (Cannot determine public IP)${COLOR_NC}"
        export NETWORK_SCENARIO="unknown"
    fi
    echo ""
    
    # Export for other functions
    export PI_LOCAL_IP="$local_ip"
    export PI_PUBLIC_IP="$external_ip"
}

get_webhook_config() {
    local webhook_port="9000"
    local webhook_secret=""
    local https_enabled="true"
    
    # Read configuration from .env file
    if [ -f "$ENV_FILE" ]; then
        webhook_port=$(grep "WEBHOOK_PORT=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "9000")
        webhook_secret=$(grep "WEBHOOK_SECRET=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
        https_enabled=$(grep "WEBHOOK_ENABLE_HTTPS=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "true")
    fi
    
    export WEBHOOK_PORT="$webhook_port"
    export WEBHOOK_SECRET="$webhook_secret"
    export HTTPS_ENABLED="$https_enabled"
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
    
    case "$NETWORK_SCENARIO" in
        "nat")
            echo -e "${COLOR_YELLOW}⚠️  NAT/Router Detected - Port Forwarding Required${COLOR_NC}"
            echo ""
            echo "🏠 Option 1: Local Development (GitHub on same network)"
            echo "   URL: $protocol://$PI_LOCAL_IP:$WEBHOOK_PORT"
            echo "   ⚠️  Only works if GitHub runner is on your local network"
            echo ""
            echo "🌐 Option 2: Public Access (Recommended for GitHub.com)"
            echo "   URL: $protocol://$PI_PUBLIC_IP:$WEBHOOK_PORT"
            echo "   📋 REQUIRES: Router port forwarding configuration"
            echo "      External Port: $WEBHOOK_PORT → Internal IP: $PI_LOCAL_IP → Internal Port: $WEBHOOK_PORT"
            echo ""
            echo "🚇 Option 3: Tunnel Service (Easiest - No Router Config)"
            echo "   • Install: sudo snap install ngrok"
            echo "   • Run: ngrok http $WEBHOOK_PORT"
            echo "   • Use provided https://xxxxx.ngrok.io URL"
            ;;
        "direct")
            echo -e "${COLOR_GREEN}✅ Direct Internet Connection Detected${COLOR_NC}"
            echo ""
            echo "🌐 GitHub Webhook URL:"
            echo "   $protocol://$PI_LOCAL_IP:$WEBHOOK_PORT"
            echo "   ✅ No port forwarding needed"
            ;;
        *)
            echo -e "${COLOR_RED}❓ Cannot determine network setup${COLOR_NC}"
            echo ""
            echo "🏠 Local Network URL:"
            echo "   $protocol://$PI_LOCAL_IP:$WEBHOOK_PORT"
            echo ""
            echo "Try these troubleshooting steps:"
            echo "1. Check internet connectivity"
            echo "2. Configure port forwarding"
            echo "3. Consider using ngrok tunnel"
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
    local local_ip=$(hostname -I | awk '{print $1}')
    local protocol="http"
    if [ "$HTTPS_ENABLED" = "true" ]; then
        protocol="https"
    fi
    
    echo "📍 Payload URL:"
    echo "   $protocol://$local_ip:$WEBHOOK_PORT"
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
    echo -e "${COLOR_CYAN}=== Network Requirements ===${COLOR_NC}"
    echo ""
    
    case "$NETWORK_SCENARIO" in
        "nat")
            echo -e "${COLOR_YELLOW}🏠 NAT/Router Setup (Most Common)${COLOR_NC}"
            echo ""
            echo "📋 Router Port Forwarding Configuration:"
            echo "   1. Access router admin (usually 192.168.1.1 or 192.168.0.1)"
            echo "   2. Find 'Port Forwarding' or 'Virtual Servers' section"
            echo "   3. Add new rule:"
            echo "      • Service Name: Ruuvi Webhook"
            echo "      • External Port: $WEBHOOK_PORT"
            echo "      • Internal IP: $PI_LOCAL_IP"
            echo "      • Internal Port: $WEBHOOK_PORT"
            echo "      • Protocol: TCP"
            echo "   4. Save and restart router"
            echo ""
            echo "🧪 Test Port Forwarding:"
            echo "   From outside network: curl -k https://$PI_PUBLIC_IP:$WEBHOOK_PORT"
            echo "   Should return 'Webhook Server - OK'"
            echo ""
            ;;
        "direct")
            echo -e "${COLOR_GREEN}✅ Direct Connection (No Setup Needed)${COLOR_NC}"
            echo "Your Pi has a direct internet connection."
            echo "No router configuration required."
            echo ""
            ;;
        *)
            echo -e "${COLOR_RED}❓ Unknown Network Setup${COLOR_NC}"
            echo "Manual network diagnosis required."
            echo ""
            ;;
    esac
    
    echo "🔥 Firewall Configuration:"
    echo "   • Check: sudo ufw status"
    echo "   • Allow webhook: sudo ufw allow $WEBHOOK_PORT/tcp"
    if [ "$NETWORK_SCENARIO" = "nat" ]; then
        echo "   • Allow HTTP for Let's Encrypt: sudo ufw allow 80/tcp"
    fi
    echo ""
    
    echo "🚇 Alternative: Tunnel Services (Skip Port Forwarding)"
    echo "   • ngrok: sudo snap install ngrok && ngrok http $WEBHOOK_PORT"
    echo "   • Cloudflare Tunnel: cloudflared tunnel"
    echo "   • localtunnel: npm install -g localtunnel && lt --port $WEBHOOK_PORT"
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