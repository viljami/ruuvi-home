#!/bin/bash
# Standalone SSL Certificate Generator for Local Raspberry Pi
# Generates self-signed certificates with IP address support

set -e

readonly SCRIPT_NAME="generate-local-certs"
readonly PROJECT_DIR="${PROJECT_DIR:-/home/${SUDO_USER:-pi}/ruuvi-home}"
readonly SSL_DIR="$PROJECT_DIR/ssl"
readonly CERT_FILE="$SSL_DIR/webhook.crt"
readonly KEY_FILE="$SSL_DIR/webhook.key"
readonly CSR_FILE="$SSL_DIR/webhook.csr"
readonly CONFIG_FILE="$SSL_DIR/openssl.conf"

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

log() {
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

print_header() {
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo -e "${COLOR_BLUE}  Ruuvi Home - Local SSL Certificate Gen   ${COLOR_NC}"
    echo -e "${COLOR_BLUE}============================================${COLOR_NC}"
    echo ""
}

check_dependencies() {
    log "INFO" "Checking dependencies"
    
    if ! command -v openssl &> /dev/null; then
        log "ERROR" "OpenSSL not found. Please install: sudo apt install openssl"
        exit 1
    fi
    
    log "SUCCESS" "Dependencies satisfied"
}

create_ssl_directory() {
    log "INFO" "Creating SSL directory structure"
    
    if ! mkdir -p "$SSL_DIR"; then
        log "ERROR" "Failed to create SSL directory: $SSL_DIR"
        exit 1
    fi
    
    # Set proper ownership if running as root
    if [ "$EUID" -eq 0 ]; then
        local target_user="${SUDO_USER:-pi}"
        if id "$target_user" &>/dev/null; then
            chown "$target_user:$target_user" "$SSL_DIR"
            log "INFO" "Set ownership to: $target_user"
        fi
    fi
    
    chmod 750 "$SSL_DIR"
    log "SUCCESS" "SSL directory created: $SSL_DIR"
}

detect_network_info() {
    log "INFO" "Detecting network configuration"
    
    # Get all local IP addresses
    local all_ips=($(hostname -I 2>/dev/null || echo "127.0.0.1"))
    local primary_ip="${all_ips[0]}"
    local hostname=$(hostname 2>/dev/null || echo "raspberrypi")
    
    # Get public IP address
    local public_ip=""
    for service in "ifconfig.me" "ipinfo.io/ip" "api.ipify.org"; do
        if public_ip=$(curl -s --connect-timeout 3 "$service" 2>/dev/null); then
            if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                break
            fi
        fi
        public_ip=""
    done
    
    # Filter out loopback and link-local addresses for display
    local local_ips=()
    for ip in "${all_ips[@]}"; do
        if [[ ! "$ip" =~ ^127\. ]] && [[ ! "$ip" =~ ^169\.254\. ]] && [[ ! "$ip" =~ ^fe80: ]]; then
            local_ips+=("$ip")
        fi
    done
    
    echo ""
    echo "=== Detected Network Configuration ==="
    echo "Hostname: $hostname"
    echo "Local Primary IP: $primary_ip"
    echo "All Local IPs: ${all_ips[*]}"
    echo "Public IP: ${public_ip:-unknown}"
    echo ""
    
    # Determine deployment scenario
    echo "=== Deployment Scenario Analysis ==="
    if [ -n "$public_ip" ] && [ "$public_ip" != "$primary_ip" ]; then
        echo "🏠 Scenario: Home/Private Network (NAT)"
        echo "   Local IP: $primary_ip (Pi internal address)"
        echo "   Public IP: $public_ip (Router external address)"
        echo "   GitHub Access: Requires port forwarding or tunnel"
    else
        echo "🌐 Scenario: Direct Internet Connection"
        echo "   Your Pi appears to have a direct public IP"
    fi
    echo ""
    
    # Export for use in certificate generation
    export DETECTED_HOSTNAME="$hostname"
    export DETECTED_PRIMARY_IP="$primary_ip"
    export DETECTED_ALL_IPS="${all_ips[*]}"
    export DETECTED_PUBLIC_IP="$public_ip"
}

create_openssl_config() {
    log "INFO" "Creating OpenSSL configuration"
    
    local hostname="${DETECTED_HOSTNAME:-raspberrypi}"
    local primary_ip="${DETECTED_PRIMARY_IP:-127.0.0.1}"
    local public_ip="${DETECTED_PUBLIC_IP:-}"
    local all_ips=($DETECTED_ALL_IPS)
    
    # Determine common name based on deployment scenario
    local common_name="$primary_ip"
    if [ -n "$public_ip" ] && [ "$DEPLOYMENT_SCENARIO" = "public" ]; then
        common_name="$public_ip"
    fi
    
    # Certificate subject information
    local country="FI"
    local state="Uusimaa"
    local city="Helsinki"
    local organization="Ruuvi Home"
    local organizational_unit="Local Webhook Server"
    local email="admin@ruuvi.local"
    
    cat > "$CONFIG_FILE" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $country
ST = $state
L = $city
O = $organization
OU = $organizational_unit
CN = $common_name
emailAddress = $email

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
EOF
    
    # Add IP addresses to Subject Alternative Names
    local ip_counter=1
    for ip in "${all_ips[@]}"; do
        echo "IP.$ip_counter = $ip" >> "$CONFIG_FILE"
        ((ip_counter++))
    done
    
    # Add public IP if different and available
    if [ -n "$public_ip" ] && [ "$public_ip" != "$primary_ip" ]; then
        echo "IP.$ip_counter = $public_ip" >> "$CONFIG_FILE"
        ((ip_counter++))
    fi
    
    # Add DNS names
    local dns_counter=1
    echo "DNS.$dns_counter = $hostname" >> "$CONFIG_FILE"
    ((dns_counter++))
    echo "DNS.$dns_counter = localhost" >> "$CONFIG_FILE"
    ((dns_counter++))
    echo "DNS.$dns_counter = webhook.ruuvi.local" >> "$CONFIG_FILE"
    ((dns_counter++))
    echo "DNS.$dns_counter = $hostname.local" >> "$CONFIG_FILE"
    
    log "SUCCESS" "OpenSSL configuration created"
    log "INFO" "Certificate will be valid for:"
    log "INFO" "  Local IPs: ${all_ips[*]}"
    if [ -n "$public_ip" ] && [ "$public_ip" != "$primary_ip" ]; then
        log "INFO" "  Public IP: $public_ip"
    fi
    log "INFO" "  Hostnames: $hostname, localhost, webhook.ruuvi.local, $hostname.local"
}

generate_certificate() {
    log "INFO" "Generating SSL certificate and private key"
    
    # Generate private key (4096-bit RSA)
    if ! openssl genrsa -out "$KEY_FILE" 4096 2>/dev/null; then
        log "ERROR" "Failed to generate private key"
        exit 1
    fi
    log "SUCCESS" "Private key generated"
    
    # Generate certificate signing request
    if ! openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -config "$CONFIG_FILE" 2>/dev/null; then
        log "ERROR" "Failed to generate certificate signing request"
        exit 1
    fi
    log "SUCCESS" "Certificate signing request generated"
    
    # Generate self-signed certificate (valid for 1 year)
    if ! openssl x509 -req -in "$CSR_FILE" -signkey "$KEY_FILE" -out "$CERT_FILE" -days 365 -extensions v3_req -extfile "$CONFIG_FILE" 2>/dev/null; then
        log "ERROR" "Failed to generate self-signed certificate"
        exit 1
    fi
    log "SUCCESS" "SSL certificate generated (valid for 365 days)"
}

set_permissions() {
    log "INFO" "Setting file permissions"
    
    # Set secure permissions
    chmod 600 "$KEY_FILE"        # Private key - read only by owner
    chmod 644 "$CERT_FILE"       # Certificate - readable by all
    chmod 644 "$CSR_FILE"        # CSR - readable by all
    chmod 644 "$CONFIG_FILE"     # Config - readable by all
    
    # Set ownership if running as root
    if [ "$EUID" -eq 0 ]; then
        local target_user="${SUDO_USER:-pi}"
        if id "$target_user" &>/dev/null; then
            chown "$target_user:$target_user" "$KEY_FILE" "$CERT_FILE" "$CSR_FILE" "$CONFIG_FILE"
            log "INFO" "Set file ownership to: $target_user"
        fi
    fi
    
    log "SUCCESS" "File permissions set securely"
}

validate_certificate() {
    log "INFO" "Validating generated certificate"
    
    # Check certificate syntax
    if ! openssl x509 -in "$CERT_FILE" -text -noout >/dev/null 2>&1; then
        log "ERROR" "Generated certificate has invalid syntax"
        exit 1
    fi
    
    # Check private key syntax
    if ! openssl rsa -in "$KEY_FILE" -check -noout >/dev/null 2>&1; then
        log "ERROR" "Generated private key has invalid syntax"
        exit 1
    fi
    
    # Verify certificate and key match
    local cert_modulus=$(openssl x509 -noout -modulus -in "$CERT_FILE" | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$KEY_FILE" | openssl md5)
    
    if [ "$cert_modulus" != "$key_modulus" ]; then
        log "ERROR" "Certificate and private key do not match"
        exit 1
    fi
    
    log "SUCCESS" "Certificate validation passed"
}

show_certificate_info() {
    log "INFO" "Certificate information"
    
    echo ""
    echo "=== Generated Certificate Details ==="
    openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates
    echo ""
    
    # Show Subject Alternative Names
    echo "=== Subject Alternative Names ==="
    openssl x509 -in "$CERT_FILE" -noout -text | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^[[:space:]]*//' || echo "None found"
    echo ""
}

show_usage_instructions() {
    local primary_ip="${DETECTED_PRIMARY_IP:-127.0.0.1}"
    local public_ip="${DETECTED_PUBLIC_IP:-}"
    
    echo "=== Usage Instructions ==="
    echo ""
    echo "Certificate files generated:"
    echo "  Certificate: $CERT_FILE"
    echo "  Private key: $KEY_FILE"
    echo ""
    
    echo "=== GitHub Webhook Configuration Options ==="
    echo ""
    
    if [ -n "$public_ip" ] && [ "$public_ip" != "$primary_ip" ]; then
        echo "🏠 Option 1: Local Network Only (Development)"
        echo "  URL: https://$primary_ip:9000"
        echo "  ⚠️  Only works if GitHub can reach your local network"
        echo ""
        
        echo "🌐 Option 2: Public Access (Production - Requires Setup)"
        echo "  URL: https://$public_ip:9000"
        echo "  📋 Required: Configure router port forwarding:"
        echo "    External Port: 9000 → Internal IP: $primary_ip → Internal Port: 9000"
        echo ""
        
        echo "🚇 Option 3: Tunnel Service (Easiest)"
        echo "  Install ngrok: sudo snap install ngrok"
        echo "  Run: ngrok http 9000"
        echo "  Use the provided https://xxxxx.ngrok.io URL"
        echo ""
    else
        echo "🌐 Direct Public Access:"
        echo "  URL: https://$primary_ip:9000"
        echo "  Your Pi appears to have a direct public IP"
        echo ""
    fi
    
    echo "=== Common Settings for All Options ==="
    echo "  Content type: application/json"
    echo "  Secret: [Get from $PROJECT_DIR/.env]"
    echo "  SSL verification: ❌ DISABLE (self-signed certificate)"
    echo "  Events: ✅ Just the push event"
    echo ""
    
    echo "=== Testing Commands ==="
    echo "Local test:"
    echo "  curl -k https://$primary_ip:9000"
    if [ -n "$public_ip" ] && [ "$public_ip" != "$primary_ip" ]; then
        echo "Public test (requires port forwarding):"
        echo "  curl -k https://$public_ip:9000"
    fi
    echo ""
    echo "Certificate details:"
    echo "  openssl x509 -in $CERT_FILE -text -noout"
    echo ""
}

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --project-dir DIR   Set project directory (default: $PROJECT_DIR)"
    echo "  --scenario TYPE     Deployment scenario (local|public|auto)"
    echo "  --force            Overwrite existing certificates"
    echo "  --help             Show this help"
    echo ""
    echo "Deployment Scenarios:"
    echo "  local    Generate certificate for local IP only"
    echo "  public   Include public IP for port forwarding setup"
    echo "  auto     Auto-detect based on network configuration (default)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect scenario"
    echo "  $0 --scenario public                 # Include public IP"
    echo "  $0 --force                          # Overwrite existing certificates"
    echo "  $0 --project-dir /opt/ruuvi-home   # Use custom project directory"
}

main() {
    local force_overwrite=false
    local deployment_scenario="auto"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-dir)
                PROJECT_DIR="$2"
                SSL_DIR="$PROJECT_DIR/ssl"
                CERT_FILE="$SSL_DIR/webhook.crt"
                KEY_FILE="$SSL_DIR/webhook.key"
                CSR_FILE="$SSL_DIR/webhook.csr"
                CONFIG_FILE="$SSL_DIR/openssl.conf"
                shift 2
                ;;
            --scenario)
                deployment_scenario="$2"
                shift 2
                ;;
            --force)
                force_overwrite=true
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
    
    # Set deployment scenario
    export DEPLOYMENT_SCENARIO="$deployment_scenario"
    
    print_header
    
    # Check if certificates already exist
    if [ -f "$CERT_FILE" ] && [ "$force_overwrite" != true ]; then
        log "WARN" "SSL certificate already exists: $CERT_FILE"
        log "INFO" "Use --force to overwrite existing certificates"
        exit 0
    fi
    
    # Run certificate generation steps
    check_dependencies
    detect_network_info
    create_ssl_directory
    create_openssl_config
    generate_certificate
    set_permissions
    validate_certificate
    show_certificate_info
    show_usage_instructions
    
    log "SUCCESS" "SSL certificate generation completed!"
    echo ""
    echo -e "${COLOR_GREEN}✓ HTTPS webhook server ready for GitHub integration${COLOR_NC}"
    echo -e "${COLOR_YELLOW}⚠ Remember to disable SSL verification in GitHub webhook settings${COLOR_NC}"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi