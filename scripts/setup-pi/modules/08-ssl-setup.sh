#!/bin/bash
# Module: SSL Certificate Setup
# Description: Sets up SSL certificates for HTTPS webhook server
# Dependencies: 01-system-setup.sh (base packages), 03-directories.sh (project structure)

set -e

# Module context for logging
readonly MODULE_CONTEXT="SSL"

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source dependencies
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/validation.sh"

# SSL configuration
readonly SSL_DIR="$PROJECT_DIR/ssl"
readonly CERT_FILE="$SSL_DIR/webhook.crt"
readonly KEY_FILE="$SSL_DIR/webhook.key"
readonly CSR_FILE="$SSL_DIR/webhook.csr"
readonly LETS_ENCRYPT_DIR="/etc/letsencrypt"
readonly CERTBOT_WEBROOT="/var/www/certbot"

# Install SSL tools
install_ssl_tools() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Installing SSL tools"
    
    # Update package list
    if ! apt-get update -qq; then
        log_error "$context" "Failed to update package list"
        return 1
    fi
    
    # Install required packages
    local packages=(
        "openssl"
        "certbot"
        "python3-certbot-nginx"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "$context" "Installing $package"
            if ! apt-get install -y -qq "$package"; then
                log_error "$context" "Failed to install $package"
                return 1
            fi
        else
            log_debug "$context" "Package already installed: $package"
        fi
    done
    
    log_success "$context" "SSL tools installed successfully"
    return 0
}

# Create SSL directory structure
create_ssl_directory() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Creating SSL directory structure"
    
    # Create SSL directory
    if ! mkdir -p "$SSL_DIR"; then
        log_error "$context" "Failed to create SSL directory: $SSL_DIR"
        return 1
    fi
    
    # Set proper ownership
    if ! chown "$RUUVI_USER:$RUUVI_USER" "$SSL_DIR"; then
        log_error "$context" "Failed to set ownership of SSL directory"
        return 1
    fi
    
    # Set secure permissions
    chmod 750 "$SSL_DIR"
    
    log_success "$context" "SSL directory created: $SSL_DIR"
    return 0
}

# Generate self-signed certificate
generate_self_signed_certificate() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Generating self-signed SSL certificate for local Pi"
    
    # Get local IP addresses
    local primary_ip=$(hostname -I | awk '{print $1}')
    local all_ips=($(hostname -I))
    local hostname=$(hostname)
    
    log_info "$context" "Detected primary IP: $primary_ip"
    log_info "$context" "Detected hostname: $hostname"
    
    # Certificate subject information
    local country="FI"
    local state="Uusimaa"
    local city="Helsinki"
    local organization="Ruuvi Home"
    local organizational_unit="Webhook Server"
    local common_name="${WEBHOOK_DOMAIN:-$primary_ip}"
    local email="${WEBHOOK_EMAIL:-admin@ruuvi.local}"
    
    # Create certificate subject
    local subject="/C=$country/ST=$state/L=$city/O=$organization/OU=$organizational_unit/CN=$common_name/emailAddress=$email"
    
    log_info "$context" "Certificate subject: $subject"
    
    # Create OpenSSL config file with SAN extensions for IP addresses
    local ssl_config="$SSL_DIR/openssl.conf"
    cat > "$ssl_config" << EOF
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
    
    # Add IP addresses to SAN
    local ip_counter=1
    for ip in "${all_ips[@]}"; do
        echo "IP.$ip_counter = $ip" >> "$ssl_config"
        ((ip_counter++))
    done
    
    # Add DNS names to SAN
    local dns_counter=1
    echo "DNS.$dns_counter = $hostname" >> "$ssl_config"
    ((dns_counter++))
    echo "DNS.$dns_counter = localhost" >> "$ssl_config"
    ((dns_counter++))
    echo "DNS.$dns_counter = webhook.ruuvi.local" >> "$ssl_config"
    
    # Add custom domain if specified
    if [ -n "$WEBHOOK_DOMAIN" ] && [ "$WEBHOOK_DOMAIN" != "$primary_ip" ]; then
        ((dns_counter++))
        echo "DNS.$dns_counter = $WEBHOOK_DOMAIN" >> "$ssl_config"
    fi
    
    log_info "$context" "OpenSSL config created with IP and hostname extensions"
    
    # Generate private key
    if ! openssl genrsa -out "$KEY_FILE" 4096; then
        log_error "$context" "Failed to generate private key"
        return 1
    fi
    
    # Generate certificate signing request with extensions
    if ! openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -config "$ssl_config"; then
        log_error "$context" "Failed to generate certificate signing request"
        return 1
    fi
    
    # Generate self-signed certificate with SAN extensions (valid for 1 year)
    if ! openssl x509 -req -in "$CSR_FILE" -signkey "$KEY_FILE" -out "$CERT_FILE" -days 365 -extensions v3_req -extfile "$ssl_config"; then
        log_error "$context" "Failed to generate self-signed certificate"
        return 1
    fi
    
    # Set proper permissions
    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    chmod 644 "$CSR_FILE"
    chmod 644 "$ssl_config"
    
    # Set ownership
    chown "$RUUVI_USER:$RUUVI_USER" "$KEY_FILE" "$CERT_FILE" "$CSR_FILE" "$ssl_config"
    
    log_success "$context" "Self-signed certificate generated with IP address support"
    log_info "$context" "Certificate: $CERT_FILE"
    log_info "$context" "Private key: $KEY_FILE"
    log_info "$context" "Valid for IPs: ${all_ips[*]}"
    log_info "$context" "Valid for hostnames: $hostname, localhost, webhook.ruuvi.local"
    
    return 0
}

# Setup Let's Encrypt certificate
setup_lets_encrypt_certificate() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Setting up Let's Encrypt certificate"
    
    # Check if we're dealing with an IP address (Let's Encrypt doesn't support IP certificates)
    if [[ "$WEBHOOK_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warn "$context" "Let's Encrypt does not support IP address certificates"
        log_warn "$context" "Domain detected as IP address: $WEBHOOK_DOMAIN"
        log_info "$context" "Falling back to self-signed certificate"
        generate_self_signed_certificate
        return $?
    fi
    
    # Validate required variables
    if [ -z "$WEBHOOK_DOMAIN" ]; then
        log_error "$context" "WEBHOOK_DOMAIN not set for Let's Encrypt"
        return 1
    fi
    
    if [ -z "$WEBHOOK_EMAIL" ]; then
        log_error "$context" "WEBHOOK_EMAIL not set for Let's Encrypt"
        return 1
    fi
    
    # Create webroot directory for challenges
    mkdir -p "$CERTBOT_WEBROOT"
    chown www-data:www-data "$CERTBOT_WEBROOT" 2>/dev/null || true
    
    # Configure nginx for HTTP-01 challenge (temporary)
    setup_temporary_nginx_config
    
    # Determine certbot server
    local certbot_server=""
    if [ "${LETS_ENCRYPT_STAGING:-true}" = "true" ]; then
        certbot_server="--staging"
        log_info "$context" "Using Let's Encrypt staging server (for testing)"
    else
        log_info "$context" "Using Let's Encrypt production server"
    fi
    
    log_info "$context" "Requesting certificate for domain: $WEBHOOK_DOMAIN"
    log_info "$context" "Email: $WEBHOOK_EMAIL"
    
    # Request certificate
    if certbot certonly \
        --webroot \
        --webroot-path="$CERTBOT_WEBROOT" \
        --email "$WEBHOOK_EMAIL" \
        --agree-tos \
        --non-interactive \
        --domains "$WEBHOOK_DOMAIN" \
        $certbot_server; then
        
        log_success "$context" "Let's Encrypt certificate obtained successfully"
        
        # Copy certificates to webhook location
        copy_lets_encrypt_certificates
        
        # Setup automatic renewal
        setup_certificate_renewal
        
    else
        log_error "$context" "Failed to obtain Let's Encrypt certificate"
        log_warn "$context" "Falling back to self-signed certificate"
        
        # Clean up temporary nginx config
        cleanup_temporary_nginx_config
        
        # Generate self-signed as fallback
        generate_self_signed_certificate
        return $?
    fi
    
    # Clean up temporary nginx config
    cleanup_temporary_nginx_config
    
    return 0
}

# Setup temporary nginx configuration for Let's Encrypt challenge
setup_temporary_nginx_config() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Setting up temporary nginx configuration"
    
    # Install nginx if not present
    if ! command -v nginx &> /dev/null; then
        log_info "$context" "Installing nginx"
        apt-get install -y -qq nginx
    fi
    
    # Create temporary nginx configuration
    cat > "/etc/nginx/sites-available/certbot-challenge" << EOF
server {
    listen 80;
    server_name ${WEBHOOK_DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root ${CERTBOT_WEBROOT};
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
    
    # Enable the site
    ln -sf "/etc/nginx/sites-available/certbot-challenge" "/etc/nginx/sites-enabled/"
    
    # Remove default site if exists
    rm -f "/etc/nginx/sites-enabled/default"
    
    # Test and reload nginx
    if nginx -t; then
        systemctl reload nginx
        log_success "$context" "Temporary nginx configuration active"
    else
        log_error "$context" "Nginx configuration test failed"
        return 1
    fi
    
    return 0
}

# Cleanup temporary nginx configuration
cleanup_temporary_nginx_config() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Cleaning up temporary nginx configuration"
    
    # Remove certbot challenge site
    rm -f "/etc/nginx/sites-enabled/certbot-challenge"
    rm -f "/etc/nginx/sites-available/certbot-challenge"
    
    # Reload nginx
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
    fi
    
    log_success "$context" "Temporary nginx configuration removed"
}

# Copy Let's Encrypt certificates to webhook location
copy_lets_encrypt_certificates() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Copying Let's Encrypt certificates"
    
    local le_cert_dir="$LETS_ENCRYPT_DIR/live/$WEBHOOK_DOMAIN"
    
    if [ ! -d "$le_cert_dir" ]; then
        log_error "$context" "Let's Encrypt certificate directory not found: $le_cert_dir"
        return 1
    fi
    
    # Copy certificate and key
    if ! cp "$le_cert_dir/fullchain.pem" "$CERT_FILE"; then
        log_error "$context" "Failed to copy certificate"
        return 1
    fi
    
    if ! cp "$le_cert_dir/privkey.pem" "$KEY_FILE"; then
        log_error "$context" "Failed to copy private key"
        return 1
    fi
    
    # Set proper permissions
    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"
    chown "$RUUVI_USER:$RUUVI_USER" "$CERT_FILE" "$KEY_FILE"
    
    log_success "$context" "Let's Encrypt certificates copied to webhook location"
    return 0
}

# Setup automatic certificate renewal
setup_certificate_renewal() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Setting up automatic certificate renewal"
    
    # Create renewal script
    local renewal_script="$PROJECT_DIR/scripts/renew-certificates.sh"
    
    cat > "$renewal_script" << EOF
#!/bin/bash
# Automatic SSL certificate renewal script

set -e

LOG_FILE="${LOG_DIR}/ssl-renewal.log"

log_renewal() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" | tee -a "\$LOG_FILE"
}

log_renewal "Starting certificate renewal check..."

# Renew certificates
if certbot renew --quiet; then
    log_renewal "Certificate renewal check completed"
    
    # Copy renewed certificates if they were updated
    if [ -f "$LETS_ENCRYPT_DIR/live/$WEBHOOK_DOMAIN/fullchain.pem" ]; then
        cp "$LETS_ENCRYPT_DIR/live/$WEBHOOK_DOMAIN/fullchain.pem" "$CERT_FILE"
        cp "$LETS_ENCRYPT_DIR/live/$WEBHOOK_DOMAIN/privkey.pem" "$KEY_FILE"
        
        # Set permissions
        chmod 644 "$CERT_FILE"
        chmod 600 "$KEY_FILE"
        chown "$RUUVI_USER:$RUUVI_USER" "$CERT_FILE" "$KEY_FILE"
        
        # Restart webhook service
        systemctl restart ruuvi-webhook
        
        log_renewal "Certificates updated and webhook service restarted"
    fi
else
    log_renewal "Certificate renewal failed"
    exit 1
fi

log_renewal "Certificate renewal process completed"
EOF
    
    chmod +x "$renewal_script"
    chown "$RUUVI_USER:$RUUVI_USER" "$renewal_script"
    
    # Add cron job for automatic renewal (check twice daily)
    local cron_entry="0 */12 * * * $renewal_script"
    
    # Add to user's crontab
    (crontab -u "$RUUVI_USER" -l 2>/dev/null || true; echo "$cron_entry") | \
        sort | uniq | crontab -u "$RUUVI_USER" -
    
    log_success "$context" "Automatic certificate renewal configured"
    log_info "$context" "Renewal script: $renewal_script"
    log_info "$context" "Cron schedule: Check every 12 hours"
    
    return 0
}

# Validate SSL certificate
validate_ssl_certificate() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "Validating SSL certificate"
    
    # Check if certificate files exist
    if [ ! -f "$CERT_FILE" ]; then
        log_error "$context" "Certificate file not found: $CERT_FILE"
        return 1
    fi
    
    if [ ! -f "$KEY_FILE" ]; then
        log_error "$context" "Private key file not found: $KEY_FILE"
        return 1
    fi
    
    # Validate certificate syntax
    if ! openssl x509 -in "$CERT_FILE" -text -noout >/dev/null 2>&1; then
        log_error "$context" "Invalid certificate file"
        return 1
    fi
    
    # Validate private key syntax
    if ! openssl rsa -in "$KEY_FILE" -check -noout >/dev/null 2>&1; then
        log_error "$context" "Invalid private key file"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus=$(openssl x509 -noout -modulus -in "$CERT_FILE" | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$KEY_FILE" | openssl md5)
    
    if [ "$cert_modulus" != "$key_modulus" ]; then
        log_error "$context" "Certificate and private key do not match"
        return 1
    fi
    
    # Get certificate information
    local cert_subject=$(openssl x509 -in "$CERT_FILE" -noout -subject | sed 's/subject= *//')
    local cert_issuer=$(openssl x509 -in "$CERT_FILE" -noout -issuer | sed 's/issuer= *//')
    local cert_expiry=$(openssl x509 -in "$CERT_FILE" -noout -enddate | sed 's/notAfter=//')
    
    log_success "$context" "SSL certificate validation passed"
    log_info "$context" "Subject: $cert_subject"
    log_info "$context" "Issuer: $cert_issuer"
    log_info "$context" "Expires: $cert_expiry"
    
    return 0
}

# Show SSL configuration summary
show_ssl_summary() {
    local context="$MODULE_CONTEXT"
    
    log_info "$context" "SSL configuration summary"
    
    local primary_ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo "=== SSL Certificate Configuration ==="
    echo "HTTPS Enabled: ${WEBHOOK_ENABLE_HTTPS:-false}"
    echo "Certificate Type: $([ "$ENABLE_LETS_ENCRYPT" = "true" ] && echo "Let's Encrypt" || echo "Self-signed")"
    echo "Certificate File: $CERT_FILE"
    echo "Private Key File: $KEY_FILE"
    echo "Primary IP Address: $primary_ip"
    
    if [ "$ENABLE_LETS_ENCRYPT" = "true" ]; then
        echo "Domain: ${WEBHOOK_DOMAIN:-not-set}"
        echo "Email: ${WEBHOOK_EMAIL:-not-set}"
        echo "Staging Mode: ${LETS_ENCRYPT_STAGING:-true}"
    fi
    
    echo ""
    echo "=== GitHub Webhook URL ==="
    if [ "${WEBHOOK_ENABLE_HTTPS:-true}" = "true" ]; then
        echo "Webhook URL: https://$primary_ip:${WEBHOOK_PORT:-9000}"
        echo "SSL Verification: ❌ Disable (Self-signed certificate)"
    else
        echo "Webhook URL: http://$primary_ip:${WEBHOOK_PORT:-9000}"
        echo "SSL Verification: N/A (HTTP)"
    fi
    echo ""
    
    # Show certificate details if available
    if [ -f "$CERT_FILE" ]; then
        echo "=== Certificate Details ==="
        openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates
        echo ""
        
        # Show Subject Alternative Names
        local san_info=$(openssl x509 -in "$CERT_FILE" -noout -text | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^[[:space:]]*//')
        if [ -n "$san_info" ]; then
            echo "Subject Alternative Names: $san_info"
            echo ""
        fi
    fi
}

# Main SSL setup function
setup_ssl_certificates() {
    local context="$MODULE_CONTEXT"
    local setup_steps=(
        "install_ssl_tools:Install SSL tools"
        "create_ssl_directory:Create SSL directory"
    )
    
    # Add certificate generation step based on configuration
    if [ "${ENABLE_LETS_ENCRYPT:-false}" = "true" ]; then
        setup_steps+=("setup_lets_encrypt_certificate:Setup Let's Encrypt certificate")
    else
        setup_steps+=("generate_self_signed_certificate:Generate self-signed certificate")
    fi
    
    setup_steps+=(
        "validate_ssl_certificate:Validate SSL certificate"
        "show_ssl_summary:Show SSL summary"
    )
    
    log_section "SSL Certificate Setup"
    log_info "$context" "HTTPS enabled: ${WEBHOOK_ENABLE_HTTPS:-false}"
    
    # Skip SSL setup if HTTPS is disabled
    if [ "${WEBHOOK_ENABLE_HTTPS:-true}" != "true" ]; then
        log_info "$context" "HTTPS disabled, skipping SSL certificate setup"
        return 0
    fi
    
    local step_num=1
    local total_steps=${#setup_steps[@]}
    local failed_steps=()
    
    for step in "${setup_steps[@]}"; do
        local func_name="${step%:*}"
        local step_desc="${step#*:}"
        
        log_step "$step_num" "$total_steps" "$step_desc"
        
        if ! $func_name; then
            failed_steps+=("$step_desc")
            
            # Critical steps that should stop the process
            if [[ "$func_name" == "install_ssl_tools" || "$func_name" == "create_ssl_directory" ]]; then
                log_error "$context" "Critical SSL setup step failed: $step_desc"
                return 1
            fi
        fi
        
        ((step_num++))
    done
    
    if [ ${#failed_steps[@]} -gt 0 ]; then
        log_warn "$context" "Some SSL setup steps failed: ${failed_steps[*]}"
        log_warn "$context" "SSL certificates may not be properly configured"
    else
        log_success "$context" "SSL certificate setup completed successfully"
    fi
    
    return 0
}

# Export main function
export -f setup_ssl_certificates

# Run setup if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_ssl_certificates
fi