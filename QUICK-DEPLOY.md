# Quick Deployment Guide - PDF Service to AlmaLinux

Fast track guide to deploy your PDF service to AlmaLinux in under 5 minutes.

---

## 🚀 Quick Start (Automated)

### From Windows (PowerShell):

```powershell
# Navigate to docker directory
cd C:\imploySeptember\app.imploy.com.au\docker

# Run deployment script
.\Deploy-ToAlmaLinux.ps1 -Host your-server.com -User root

# Or with custom settings
.\Deploy-ToAlmaLinux.ps1 -Host 192.168.1.100 -User deploy -Port 2222 -Path /home/deploy/pdf-service
```

### From Linux/Mac (Bash):

```bash
# Navigate to docker directory
cd /path/to/app.imploy.com.au/docker

# Make script executable
chmod +x deploy-to-almalinux.sh

# Run deployment script
./deploy-to-almalinux.sh --host your-server.com --user root

# Or with custom settings
./deploy-to-almalinux.sh --host 192.168.1.100 --user deploy --port 2222 --path /home/deploy/pdf-service
```

---

## 📋 Manual Deployment (Step-by-Step)

### 1. Copy Files to Server

```bash
# From your local machine
scp -r docker/pdf-service root@your-server.com:/opt/pdf-service
```

### 2. SSH into Server

```bash
ssh root@your-server.com
cd /opt/pdf-service
```

### 3. Install Docker (if not installed)

```bash
# Quick Docker installation
curl -fsSL https://get.docker.com | sh
systemctl start docker
systemctl enable docker
```

### 4. Configure Environment

```bash
# Edit .env file
nano .env
```

Update these values:
```env
NODE_ENV=production
PORT=3001
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
```

### 5. Build and Run

```bash
# Build Docker image
docker build -t pdf-service:latest .

# Run container
docker run -d \
  --name pdf-service \
  --restart unless-stopped \
  -p 3001:3001 \
  --env-file .env \
  pdf-service:latest

# Check status
docker ps
docker logs pdf-service
```

### 6. Test Service

```bash
# Health check
curl http://localhost:3001/health

# Should return: {"status":"healthy","timestamp":"..."}
```

### 7. Open Firewall (if needed)

```bash
firewall-cmd --permanent --add-port=3001/tcp
firewall-cmd --reload
```

---

## 🔧 Post-Deployment

### Update Laravel Configuration

In your Laravel `.env` file:
```env
PDF_SERVICE_URL=http://your-server-ip:3001
```

### Set Up Nginx Reverse Proxy (Recommended)

Create `/etc/nginx/conf.d/pdf-service.conf`:

```nginx
server {
    listen 80;
    server_name pdf.yourdomain.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        # Increase timeout for PDF generation
        proxy_read_timeout 60s;
    }
}
```

Then:
```bash
nginx -t
systemctl reload nginx
```

### Install SSL Certificate (Let's Encrypt)

```bash
# Install certbot
yum install -y certbot python3-certbot-nginx

# Get certificate
certbot --nginx -d pdf.yourdomain.com

# Auto-renewal is set up automatically
```

---

## 📊 Monitoring & Management

### View Logs
```bash
docker logs -f pdf-service
```

### Restart Service
```bash
docker restart pdf-service
```

### Stop Service
```bash
docker stop pdf-service
```

### Update Service
```bash
# Upload new files
scp -r docker/pdf-service root@your-server.com:/opt/pdf-service

# SSH into server
ssh root@your-server.com
cd /opt/pdf-service

# Rebuild and restart
docker stop pdf-service
docker rm pdf-service
docker build -t pdf-service:latest .
docker run -d \
  --name pdf-service \
  --restart unless-stopped \
  -p 3001:3001 \
  --env-file .env \
  pdf-service:latest
```

### Check Resource Usage
```bash
docker stats pdf-service
```

---

## 🐛 Troubleshooting

### Service won't start
```bash
# Check logs
docker logs pdf-service

# Check if port is in use
netstat -tulpn | grep 3001
```

### Chromium errors
```bash
# Enter container
docker exec -it pdf-service /bin/sh

# Check Chromium
which chromium-browser
chromium-browser --version
```

### PDF generation fails
```bash
# Check if service is reachable
curl http://localhost:3001/health

# Test PDF generation
curl -X POST http://localhost:3001/generate-invoice-pdf \
  -H "Content-Type: application/json" \
  -d '{"invoice":{"invoice_number":"TEST-001",...}}'
```

---

## 📞 Need Help?

- **Full Documentation**: See `ALMALINUX-DEPLOYMENT.md`
- **Docker Setup**: See `docker/README.md`
- **GitHub Issues**: [Report an issue](https://github.com/your-repo/issues)

---

## ✅ Deployment Checklist

- [ ] Docker installed on server
- [ ] Files copied to server
- [ ] `.env` configured for production
- [ ] Docker image built
- [ ] Container running
- [ ] Health check passing
- [ ] Firewall configured
- [ ] Laravel `.env` updated
- [ ] (Optional) Nginx reverse proxy configured
- [ ] (Optional) SSL certificate installed

---

**Last Updated**: October 9, 2025  
**Version**: 1.0.0

