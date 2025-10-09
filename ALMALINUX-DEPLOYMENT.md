# PDF Service Deployment Guide - AlmaLinux

Complete guide for deploying the PDF generation service to your AlmaLinux production server.

---

## 📋 Prerequisites

### On AlmaLinux Server:
- Docker installed and running
- Docker Compose installed
- Port 3001 available (or choose another port)
- Git installed (optional, for cloning)

---

## 🚀 Deployment Methods

### Method 1: Using Docker Compose (Recommended)

#### Step 1: Copy Files to Server

**Option A: Using Git**
```bash
# SSH into your AlmaLinux server
ssh user@your-server.com

# Clone your repository
git clone https://github.com/your-repo/app.imploy.com.au.git
cd app.imploy.com.au/docker/pdf-service
```

**Option B: Using SCP/SFTP**
```bash
# From your local Windows machine
scp -r docker/pdf-service user@your-server.com:/home/user/pdf-service
```

#### Step 2: Configure Environment

```bash
# SSH into server
cd /home/user/pdf-service

# Create/edit .env file
nano .env
```

Add these variables:
```env
NODE_ENV=production
PORT=3001

# Chromium path for Linux
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Laravel API Configuration
LARAVEL_API_URL=http://your-laravel-domain.com
LARAVEL_API_TOKEN=sFIuGW7X5vQOSwahgdzU9c2o13PNxHkVpyEiYfJrCeZ4TBL8MbtRq06KnlmjAD
```

#### Step 3: Build and Run with Docker Compose

```bash
# Build the Docker image
docker-compose build

# Start the service
docker-compose up -d

# Check logs
docker-compose logs -f pdf-service

# Check status
docker-compose ps
```

---

### Method 2: Using Standalone Docker

#### Step 1: Build the Image

```bash
cd /path/to/pdf-service

# Build the image
docker build -t pdf-service:latest .
```

#### Step 2: Run the Container

```bash
docker run -d \
  --name pdf-service \
  --restart unless-stopped \
  -p 3001:3001 \
  -e NODE_ENV=production \
  -e PORT=3001 \
  -e LARAVEL_API_URL=http://your-laravel-domain.com \
  -e LARAVEL_API_TOKEN=sFIuGW7X5vQOSwahgdzU9c2o13PNxHkVpyEiYfJrCeZ4TBL8MbtRq06KnlmjAD \
  pdf-service:latest
```

#### Step 3: Verify

```bash
# Check if container is running
docker ps

# View logs
docker logs -f pdf-service

# Test health endpoint
curl http://localhost:3001/health
```

---

### Method 3: Using Pre-built Image (Registry)

If you push to Docker Hub or private registry:

```bash
# Pull the image
docker pull your-registry/pdf-service:latest

# Run it
docker run -d \
  --name pdf-service \
  --restart unless-stopped \
  -p 3001:3001 \
  --env-file /path/to/.env \
  your-registry/pdf-service:latest
```

---

## 🔧 Docker Compose Configuration

Create `docker-compose.yml` in `/home/user/pdf-service`:

```yaml
version: '3.8'

services:
  pdf-service:
    build: .
    container_name: pdf-service
    restart: unless-stopped
    ports:
      - "3001:3001"
    environment:
      - NODE_ENV=production
      - PORT=3001
    env_file:
      - .env
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
        reservations:
          memory: 512M
          cpus: '0.5'
```

---

## 🔐 Firewall Configuration

### Open Port 3001 (if needed)

```bash
# For firewalld (AlmaLinux default)
sudo firewall-cmd --permanent --add-port=3001/tcp
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-ports
```

### Or use Nginx Reverse Proxy (Recommended for Production)

```nginx
# /etc/nginx/conf.d/pdf-service.conf
server {
    listen 80;
    server_name pdf.yourdomain.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Increase timeout for PDF generation
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

Then reload Nginx:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

---

## 📦 Installing Docker on AlmaLinux

If Docker is not installed:

```bash
# Remove old versions (if any)
sudo yum remove docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine

# Install required packages
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

# Add Docker repository
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Verify
sudo docker --version
sudo docker compose version

# Add your user to docker group (optional)
sudo usermod -aG docker $USER
newgrp docker
```

---

## 🧪 Testing the Deployment

### 1. Health Check
```bash
curl http://localhost:3001/health
# Expected: {"status":"healthy","timestamp":"2025-10-09T..."}
```

### 2. Test PDF Generation
```bash
curl -X POST http://localhost:3001/generate-invoice-pdf \
  -H "Content-Type: application/json" \
  -d '{
    "invoice": {
      "invoice_number": "TEST-001",
      "invoice_date": "2025-10-09",
      "total_amount": "100.00",
      "billing_details": {
        "name": "Test Client",
        "email": "test@example.com",
        "address": "123 Test St"
      },
      "line_items": [{
        "description": "Test Service",
        "quantity": 1,
        "rate": "100.00",
        "amount": "100.00"
      }]
    }
  }' \
  --output test.pdf

# Check if PDF was created
file test.pdf
# Expected: test.pdf: PDF document...
```

---

## 🔄 Updating the Service

### Update Code and Restart

```bash
# Pull latest code (if using git)
git pull origin main

# Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Or for standalone docker
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

---

## 📊 Monitoring & Logs

### View Logs
```bash
# Docker Compose
docker-compose logs -f pdf-service

# Standalone Docker
docker logs -f pdf-service

# Last 100 lines
docker logs --tail 100 pdf-service
```

### Resource Usage
```bash
# Container stats
docker stats pdf-service

# Disk usage
docker system df
```

### Restart Service
```bash
# Docker Compose
docker-compose restart pdf-service

# Standalone Docker
docker restart pdf-service
```

---

## 🛡️ Security Best Practices

1. **Use Environment Variables**: Never hardcode sensitive data
2. **Restrict Access**: Use firewall rules or reverse proxy
3. **HTTPS**: Use SSL/TLS in production (via Nginx)
4. **Rate Limiting**: Implement rate limiting in Nginx or application
5. **Regular Updates**: Keep Docker images and packages updated

---

## 🐛 Troubleshooting

### Container Won't Start
```bash
# Check logs
docker logs pdf-service

# Check if port is already in use
sudo netstat -tulpn | grep 3001

# Inspect container
docker inspect pdf-service
```

### Chromium Issues
```bash
# Enter container
docker exec -it pdf-service /bin/sh

# Check if Chromium is installed
which chromium-browser

# Test Chromium
chromium-browser --version
```

### Permission Issues
```bash
# Check SELinux status
sestatus

# If needed, set SELinux to permissive
sudo setenforce 0
```

---

## 📞 Support

- **GitHub Issues**: [Your Repository Issues]
- **Documentation**: See `/docker/README.md`
- **Logs Location**: `/var/log/docker/` or `docker logs`

---

## 📝 Quick Reference

| Command | Description |
|---------|-------------|
| `docker-compose up -d` | Start service in background |
| `docker-compose down` | Stop service |
| `docker-compose logs -f` | View live logs |
| `docker-compose ps` | Check service status |
| `docker-compose restart` | Restart service |
| `curl http://localhost:3001/health` | Health check |

---

**Last Updated**: October 9, 2025  
**Version**: 1.0.0

