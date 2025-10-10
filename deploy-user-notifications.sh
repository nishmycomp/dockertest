#!/bin/bash

################################################################################
# Deploy User-Specific Notification System to AlmaLinux
# This script deploys the updated PDF service with user tracking for notifications
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
echo -e "${PURPLE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║     User-Specific Notification System Deployment              ║"
echo "║     For AlmaLinux PDF Queue Service                           ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Configuration
LARAVEL_URL="${LARAVEL_URL:-http://127.0.0.1:8000}"
LARAVEL_API_TOKEN="${LARAVEL_API_TOKEN:-}"

echo -e "${CYAN}📋 Configuration:${NC}"
echo "  Laravel URL: ${LARAVEL_URL}"
echo "  API Token: ${LARAVEL_API_TOKEN:-'(not set)'}"
echo ""

# Step 1: Check if .env file exists
echo -e "${BLUE}[1/7]${NC} Checking environment configuration..."
if [ ! -f "pdf-service/.env" ]; then
    echo -e "${YELLOW}⚠${NC}  No .env file found. Creating from template..."
    cat > pdf-service/.env << EOF
# PDF Service Configuration
PORT=3001
NODE_ENV=production
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Redis Configuration (for Bull queue)
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=

# Laravel Integration
LARAVEL_URL=${LARAVEL_URL}
LARAVEL_API_TOKEN=${LARAVEL_API_TOKEN}

# SMTP Configuration for Nodemailer
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM="Imploy <noreply@imploy.com.au>"

# Service Configuration
MONITOR_PORT=3004
EOF
    echo -e "${GREEN}✓${NC} Created .env file"
    echo -e "${YELLOW}⚠${NC}  Please update SMTP settings in pdf-service/.env before production use"
else
    echo -e "${GREEN}✓${NC} Found existing .env file"
    
    # Update LARAVEL_URL if not set
    if ! grep -q "LARAVEL_URL=" pdf-service/.env; then
        echo "LARAVEL_URL=${LARAVEL_URL}" >> pdf-service/.env
        echo -e "${GREEN}✓${NC} Added LARAVEL_URL to .env"
    fi
    
    # Update LARAVEL_API_TOKEN if provided and not set
    if [ -n "${LARAVEL_API_TOKEN}" ] && ! grep -q "LARAVEL_API_TOKEN=" pdf-service/.env; then
        echo "LARAVEL_API_TOKEN=${LARAVEL_API_TOKEN}" >> pdf-service/.env
        echo -e "${GREEN}✓${NC} Added LARAVEL_API_TOKEN to .env"
    fi
fi
echo ""

# Step 2: Stop existing containers
echo -e "${BLUE}[2/7]${NC} Stopping existing PDF service containers..."
docker compose -f docker-compose-queue.yml down 2>/dev/null || true
echo -e "${GREEN}✓${NC} Containers stopped"
echo ""

# Step 3: Build new images with updated code
echo -e "${BLUE}[3/7]${NC} Building updated PDF service images..."
echo "  This includes the new user tracking functionality..."
docker compose -f docker-compose-queue.yml build --no-cache pdf-service-1 pdf-service-2 pdf-service-3 pdf-worker-1 pdf-worker-2 queue-monitor
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Images built successfully"
else
    echo -e "${RED}✗${NC} Failed to build images"
    exit 1
fi
echo ""

# Step 4: Start the services
echo -e "${BLUE}[4/7]${NC} Starting PDF service with user notification tracking..."
docker compose -f docker-compose-queue.yml up -d
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Services started"
else
    echo -e "${RED}✗${NC} Failed to start services"
    exit 1
fi
echo ""

# Step 5: Wait for services to be healthy
echo -e "${BLUE}[5/7]${NC} Waiting for services to be ready..."
sleep 10

# Check Redis
echo -n "  Checking Redis... "
if docker exec pdf-redis redis-cli ping >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Check PDF services
for i in 1 2 3; do
    echo -n "  Checking PDF Service $i... "
    if curl -f -s http://localhost:300$i/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}⚠${NC} (still starting)"
    fi
done

# Check Nginx
echo -n "  Checking Nginx Load Balancer... "
if curl -f -s http://localhost:8080/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} (still starting)"
fi

# Check Queue Monitor
echo -n "  Checking Queue Monitor... "
if curl -f -s http://localhost:3004 >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} (still starting)"
fi
echo ""

# Step 6: Test notification endpoint
echo -e "${BLUE}[6/7]${NC} Testing user notification system..."
echo "  Testing connection to Laravel..."

# Test Laravel connectivity
if curl -f -s "${LARAVEL_URL}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Laravel is reachable at ${LARAVEL_URL}"
    
    # Test notification endpoint
    echo "  Testing notification endpoint..."
    RESPONSE=$(curl -s -X POST "${LARAVEL_URL}/api/queue/notification/job-failed" \
        -H "Content-Type: application/json" \
        -d '{
            "jobType": "pdf",
            "invoiceNumber": "DEPLOY-TEST",
            "errorMessage": "Deployment test notification",
            "batchId": "test-batch-'$(date +%s)'",
            "tenantId": "app_imploy_com_au",
            "userId": 1
        }' 2>&1)
    
    if echo "$RESPONSE" | grep -q '"success":true'; then
        echo -e "${GREEN}✓${NC} Notification endpoint is working!"
        echo "  A test notification has been sent to user ID 1"
    else
        echo -e "${YELLOW}⚠${NC} Notification endpoint test failed"
        echo "  Response: $RESPONSE"
        echo "  This is OK if Laravel is not running yet"
    fi
else
    echo -e "${YELLOW}⚠${NC} Cannot reach Laravel at ${LARAVEL_URL}"
    echo "  Make sure Laravel is running and accessible from this server"
    echo "  You can update LARAVEL_URL in pdf-service/.env"
fi
echo ""

# Step 7: Display status and next steps
echo -e "${BLUE}[7/7]${NC} Deployment Summary"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo ""
echo "📊 Service Status:"
docker compose -f docker-compose-queue.yml ps
echo ""

echo "🔗 Access Points:"
echo "  • Queue Monitor:      http://$(hostname -I | awk '{print $1}'):3004"
echo "  • Queue Monitor:      http://localhost:3004"
echo "  • Load Balancer:      http://localhost:8080"
echo "  • PDF Service 1:      http://localhost:3001"
echo "  • PDF Service 2:      http://localhost:3002"
echo "  • PDF Service 3:      http://localhost:3003"
echo "  • Redis:              localhost:6379"
echo ""

echo "📝 Container Logs:"
echo "  • All services:       docker compose -f docker-compose-queue.yml logs -f"
echo "  • PDF worker 1:       docker logs -f pdf-worker-1"
echo "  • PDF worker 2:       docker logs -f pdf-worker-2"
echo "  • Queue monitor:      docker logs -f queue-monitor"
echo ""

echo "🧪 Testing:"
echo "  1. Go to your Laravel app: ${LARAVEL_URL}/admin/platform-invoices"
echo "  2. Select some invoices and click 'Download Selected'"
echo "  3. If any jobs fail, ONLY the user who clicked will get notified"
echo "  4. Check notifications at: ${LARAVEL_URL}/notifications (or your inbox page)"
echo ""

echo "🔍 Verify User Tracking:"
echo "  1. Check batch has userId stored:"
echo "     docker exec -it pdf-redis redis-cli"
echo "     HGETALL batch:app_imploy_com_au:batch-YYYYMMDD-HHMMSS-xxxxx"
echo ""
echo "  2. Check logs for user notifications:"
echo "     docker logs pdf-worker-1 | grep 'userId'"
echo ""

echo "⚙️  Configuration:"
echo "  • Edit settings:      nano pdf-service/.env"
echo "  • Restart services:   docker compose -f docker-compose-queue.yml restart"
echo "  • Rebuild services:   docker compose -f docker-compose-queue.yml build --no-cache"
echo "  • Stop services:      docker compose -f docker-compose-queue.yml down"
echo ""

echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 User-Specific Notifications are now active!${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Optional: Show recent logs
echo -e "${CYAN}📋 Recent logs (last 20 lines):${NC}"
docker compose -f docker-compose-queue.yml logs --tail=20
echo ""

echo -e "${YELLOW}💡 Tip:${NC} Run this to watch logs in real-time:"
echo "   docker compose -f docker-compose-queue.yml logs -f"
echo ""

