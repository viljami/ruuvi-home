# GitHub Secrets Setup Guide

This guide explains how to configure GitHub repository secrets for automated deployment of Ruuvi Home to your Raspberry Pi.

## Overview

The Ruuvi Home project uses GitHub Actions for continuous integration and deployment. The workflow builds container images and deploys them to your Raspberry Pi using webhooks. This requires setting up specific secrets in your GitHub repository.

## Required Secrets

### WEBHOOK_URL
- **Purpose**: The endpoint URL for triggering deployments on your Raspberry Pi
- **Format**: `http://YOUR_PI_IP:9000/webhook`
- **Example**: `http://192.168.1.100:9000/webhook`

### WEBHOOK_SECRET
- **Purpose**: Secret key for authenticating webhook requests
- **Format**: Base64 encoded string (minimum 32 characters)
- **Security**: Must match the value in your Pi's `.env` file

## Setting Up GitHub Secrets

### Step 1: Navigate to Repository Settings

1. Go to your GitHub repository
2. Click on **Settings** tab
3. In the left sidebar, click **Secrets and variables**
4. Click **Actions**

### Step 2: Add Required Secrets

#### WEBHOOK_URL Secret

1. Click **New repository secret**
2. **Name**: `WEBHOOK_URL`
3. **Secret**: Enter your Pi's webhook URL
   ```
   http://YOUR_PI_IP:9000/webhook
   ```
   Replace `YOUR_PI_IP` with your actual Raspberry Pi IP address
4. Click **Add secret**

#### WEBHOOK_SECRET Secret

1. Click **New repository secret**
2. **Name**: `WEBHOOK_SECRET`
3. **Secret**: Generate a secure secret (see generation methods below)
4. Click **Add secret**

### Step 3: Generate Secure Webhook Secret

Use one of these methods to generate a secure webhook secret:

#### Method 1: Using OpenSSL (Recommended)
```bash
openssl rand -base64 32
```

#### Method 2: Using Python
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

#### Method 3: Using Node.js
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

#### Method 4: Online Generator
Use a reputable online password generator with these settings:
- Length: 32+ characters
- Include: Letters (upper/lower), numbers, symbols
- Exclude: Ambiguous characters

### Step 4: Update Raspberry Pi Configuration

Ensure the webhook secret matches on your Raspberry Pi:

1. SSH to your Raspberry Pi
2. Edit the environment file:
   ```bash
   nano /home/pi/ruuvi-home/.env
   ```
3. Set the webhook secret:
   ```bash
   WEBHOOK_SECRET=your_generated_secret_here
   ```
4. Restart the webhook service:
   ```bash
   sudo systemctl restart ruuvi-webhook
   ```

## Security Considerations

### Secret Management Best Practices

1. **Never commit secrets to code**: Use GitHub Secrets, never environment variables in code
2. **Use strong secrets**: Minimum 32 characters, cryptographically secure
3. **Rotate secrets regularly**: Update secrets every 90 days
4. **Limit access**: Only repository admins should manage secrets
5. **Monitor usage**: Review deployment logs for unauthorized access attempts

### Network Security

1. **Firewall configuration**: Webhook port (9000) should only accept connections from GitHub IPs
2. **HTTPS recommended**: Use reverse proxy with SSL for webhook endpoint
3. **VPN access**: Consider VPN for additional security layer
4. **IP allowlisting**: Restrict webhook access to GitHub's IP ranges

### GitHub IP Ranges

For enhanced security, configure your firewall to only allow webhook requests from GitHub's IP ranges:
- Check current ranges: https://api.github.com/meta
- Update firewall rules to include only these ranges

## Verification

### Test Webhook Configuration

1. **Check secret is set**:
   - Go to repository Settings → Secrets and variables → Actions
   - Verify both `WEBHOOK_URL` and `WEBHOOK_SECRET` are listed

2. **Test webhook endpoint**:
   ```bash
   curl -X POST http://YOUR_PI_IP:9000/webhook \
     -H "Content-Type: application/json" \
     -d '{"test": "connection"}'
   ```

3. **Verify Pi webhook service**:
   ```bash
   sudo systemctl status ruuvi-webhook
   journalctl -u ruuvi-webhook -n 20
   ```

### Trigger Test Deployment

1. **Push to main branch** or **create a release**:
   ```bash
   git push origin main
   ```

2. **Monitor GitHub Actions**:
   - Go to **Actions** tab in your repository
   - Watch the workflow execution
   - Check for any secret-related errors

3. **Verify deployment on Pi**:
   ```bash
   sudo systemctl status ruuvi-home
   docker-compose ps
   ```

## Troubleshooting

### Common Issues

#### Secret Not Found
- **Error**: `Secret WEBHOOK_SECRET not found`
- **Solution**: Verify secret name matches exactly (case-sensitive)

#### Invalid Webhook URL
- **Error**: Connection refused or timeout
- **Solution**: Check Pi IP address, firewall rules, and webhook service status

#### Authentication Failed
- **Error**: `Invalid webhook signature`
- **Solution**: Ensure webhook secret matches between GitHub and Pi

#### Deployment Not Triggered
- **Error**: Workflow completes but no deployment happens
- **Solution**: Check webhook service logs and network connectivity

### Debug Commands

```bash
# Check webhook service status
sudo systemctl status ruuvi-webhook

# View webhook logs
journalctl -u ruuvi-webhook -f

# Test webhook manually
curl -X POST http://localhost:9000/webhook \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: sha256=test" \
  -d '{"action":"published","release":{"tag_name":"test"}}'

# Check GitHub Actions logs
# Go to repository → Actions → Select workflow run → View logs
```

## Optional: Advanced Configuration

### Multiple Environments

If you have multiple Raspberry Pi devices (staging, production):

1. **Create environment-specific secrets**:
   - `WEBHOOK_URL_STAGING`
   - `WEBHOOK_URL_PRODUCTION`
   - `WEBHOOK_SECRET_STAGING`
   - `WEBHOOK_SECRET_PRODUCTION`

2. **Use GitHub Environments**:
   - Go to Settings → Environments
   - Create `staging` and `production` environments
   - Add environment-specific secrets

3. **Update workflow**:
   ```yaml
   deploy-staging:
     environment: staging
     # Uses staging secrets

   deploy-production:
     environment: production
     # Uses production secrets
   ```

### Slack Notifications (Optional)

Add Slack webhook for deployment notifications:

1. **Create Slack webhook**: Go to Slack → Apps → Incoming Webhooks
2. **Add secret**: `SLACK_WEBHOOK_URL`
3. **Update workflow** to include Slack notification step

### Custom Domain with HTTPS

For production deployments with custom domains:

1. **Setup domain**: Point domain to your Pi's public IP
2. **SSL certificate**: Use Let's Encrypt with certbot
3. **Update webhook URL**: Use HTTPS endpoint
4. **Configure Nginx**: Proxy webhook requests to internal port

## Support

If you encounter issues with secrets configuration:

1. **Check documentation**: Review GitHub Actions documentation
2. **Repository issues**: Create issue with sanitized error logs (never include actual secrets)
3. **Community support**: Ask in GitHub Discussions
4. **Security concerns**: Contact repository maintainers privately

## Security Contact

For security-related issues with secrets or deployment:
- **Do not** post secrets or security issues in public
- **Do not** include actual secret values in issue reports
- Create private security advisory if needed
