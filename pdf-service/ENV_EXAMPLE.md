# Environment Variables Configuration

Copy these to your `.env` file in `docker/pdf-service/` directory:

```env
# Node Environment
NODE_ENV=production
PORT=3001

# Redis Configuration
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=

# Puppeteer Configuration
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Laravel API Token (for authentication)
LARAVEL_API_TOKEN=your-api-token-here

# Laravel Application URL (for notifications)
LARAVEL_URL=http://127.0.0.1:8000

# SMTP Configuration for Email Sending
# Default SMTP (used if tenant-specific not configured)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM="Imploy <noreply@imploy.com.au>"

# Tenant-specific SMTP (optional)
# app.imploy.com.au
IMPLOY_SMTP_HOST=smtp.gmail.com
IMPLOY_SMTP_PORT=587
IMPLOY_SMTP_SECURE=false
IMPLOY_SMTP_USER=noreply@imploy.com.au
IMPLOY_SMTP_PASS=your-password-here

# Service Configuration
SERVICE_ID=1
MONITOR_PORT=3004
```

## SMTP Setup Guide

### Gmail (Recommended for Testing)
1. Enable 2-Factor Authentication in your Google Account
2. Generate an App Password: https://myaccount.google.com/apppasswords
3. Use your Gmail address as `SMTP_USER`
4. Use the generated App Password as `SMTP_PASS`

### Other SMTP Providers
- **SendGrid**: `smtp.sendgrid.net:587`
- **Mailgun**: `smtp.mailgun.org:587`
- **AWS SES**: `email-smtp.us-east-1.amazonaws.com:587`
- **Office 365**: `smtp.office365.com:587`

## Testing Email Configuration

Test if SMTP is working:
```bash
curl http://localhost:3001/email/verify
```

Or for specific tenant:
```bash
curl http://localhost:3001/email/verify/app_imploy_com_au
```

