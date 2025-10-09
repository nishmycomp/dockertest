# PDF Service - Docker Deployment

This directory contains everything needed to deploy the PDF generation service using Docker.

---

## 📁 Directory Structure

```
docker/
├── pdf-service/              # PDF service source code
│   ├── server.js            # Node.js Express server
│   ├── package.json         # Node dependencies
│   ├── Dockerfile           # Docker image definition
│   ├── .env                 # Environment configuration
│   ├── templates/           # Handlebars invoice templates
│   └── ...
│
├── docker-compose.yml       # Docker Compose configuration
│
├── ALMALINUX-DEPLOYMENT.md  # Complete deployment guide for AlmaLinux
├── QUICK-DEPLOY.md          # Quick start deployment guide
│
├── deploy-to-almalinux.sh   # Bash deployment script (Linux/Mac)
└── Deploy-ToAlmaLinux.ps1   # PowerShell deployment script (Windows)
```

---

## 🚀 Quick Start

### Development (Windows)

```powershell
cd docker\pdf-service
$env:PORT=3001
node server.js
```

### Development (Linux/Mac)

```bash
cd docker/pdf-service
PORT=3001 node server.js
```

### Production (Docker)

#### Using Docker Compose:
```bash
cd docker
docker-compose up -d
```

#### Using Docker directly:
```bash
cd docker/pdf-service
docker build -t pdf-service:latest .
docker run -d \
  --name pdf-service \
  --restart unless-stopped \
  -p 3001:3001 \
  --env-file .env \
  pdf-service:latest
```

---

## 📖 Documentation

| Document | Purpose |
|----------|---------|
| **ALMALINUX-DEPLOYMENT.md** | Complete guide for deploying to AlmaLinux servers |
| **QUICK-DEPLOY.md** | Fast-track deployment guide (5 minutes) |
| **pdf-service/README.md** | Detailed PDF service documentation |

---

## 🖥️ Deployment to AlmaLinux

### Automated Deployment

**From Windows:**
```powershell
.\Deploy-ToAlmaLinux.ps1 -Host your-server.com -User root
```

**From Linux/Mac:**
```bash
./deploy-to-almalinux.sh --host your-server.com --user root
```

### Manual Deployment

See [QUICK-DEPLOY.md](./QUICK-DEPLOY.md) for step-by-step instructions.

---

## 🔧 Configuration

### Environment Variables

Create a `.env` file in `pdf-service/` directory:

```env
# Environment
NODE_ENV=production

# Server
PORT=3001

# Chromium (for Linux/Docker)
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Laravel API
LARAVEL_API_URL=http://your-laravel-domain.com
LARAVEL_API_TOKEN=your-api-token-here

# Company Details (for invoice template)
COMPANY_NAME=Your Company Name
COMPANY_ADDRESS=123 Main St, City, State, ZIP
COMPANY_PHONE=+1 234 567 8900
COMPANY_EMAIL=billing@yourcompany.com
COMPANY_ABN=12 345 678 901
```

### Docker Compose Configuration

The `docker-compose.yml` file is pre-configured with:
- Port mapping (3001:3001)
- Health checks
- Automatic restart
- Resource limits
- Log rotation

---

## 🧪 Testing

### Health Check

```bash
curl http://localhost:3001/health
```

Expected response:
```json
{"status":"healthy","timestamp":"2025-10-09T..."}
```

### Test PDF Generation

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
```

---

## 📊 Monitoring

### View Logs

```bash
# Docker Compose
docker-compose logs -f pdf-service

# Standalone Docker
docker logs -f pdf-service
```

### Resource Usage

```bash
docker stats pdf-service
```

### Container Status

```bash
# Docker Compose
docker-compose ps

# Standalone Docker
docker ps -f name=pdf-service
```

---

## 🔄 Updating

### Update and Restart

```bash
# Pull latest code
git pull origin main

# Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

---

## 🐛 Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs pdf-service

# Check if port is in use
netstat -tulpn | grep 3001

# Inspect container
docker inspect pdf-service
```

### Chromium Issues

```bash
# Enter container
docker exec -it pdf-service /bin/sh

# Check Chromium
which chromium-browser
chromium-browser --version
```

### Reset Everything

```bash
# Stop and remove container
docker-compose down

# Remove image
docker rmi pdf-service:latest

# Rebuild from scratch
docker-compose build --no-cache
docker-compose up -d
```

---

## 🔐 Security

### Production Checklist

- [ ] Use environment variables for sensitive data
- [ ] Enable firewall (only allow necessary ports)
- [ ] Use HTTPS/SSL (via Nginx reverse proxy)
- [ ] Implement rate limiting
- [ ] Regular security updates
- [ ] Monitor logs for suspicious activity
- [ ] Use non-root user in container (already configured)
- [ ] Keep Docker and dependencies updated

---

## 📞 Support

- **Documentation**: See `ALMALINUX-DEPLOYMENT.md`
- **Quick Start**: See `QUICK-DEPLOY.md`
- **Issues**: [GitHub Issues](https://github.com/your-repo/issues)
- **Service Logs**: `docker logs pdf-service`

---

## 📝 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-10-09 | Initial release with AlmaLinux deployment support |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Laravel Application                 │
│              (app.imploy.com.au)                    │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ HTTP POST /generate-invoice-pdf
                  │ (Invoice Data)
                  ▼
┌─────────────────────────────────────────────────────┐
│              PDF Service (Node.js)                   │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │  Express Server (port 3001)                │    │
│  └───────────┬────────────────────────────────┘    │
│              │                                       │
│              ▼                                       │
│  ┌────────────────────────────────────────────┐    │
│  │  Handlebars Template Engine                │    │
│  │  (renders invoice HTML)                    │    │
│  └───────────┬────────────────────────────────┘    │
│              │                                       │
│              ▼                                       │
│  ┌────────────────────────────────────────────┐    │
│  │  Puppeteer + Chromium                      │    │
│  │  (HTML to PDF conversion)                  │    │
│  └───────────┬────────────────────────────────┘    │
│              │                                       │
└──────────────┼───────────────────────────────────────┘
               │
               ▼
          PDF Binary Data
          (returned to Laravel)
```

---

**Last Updated**: October 9, 2025  
**Maintained by**: Imploy Development Team

