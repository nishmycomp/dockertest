#!/bin/bash

echo "🚀 Deploying Multi-Tenant Queue System for PDF Service"
echo "======================================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running"
    exit 1
fi

print_header "Stopping existing services..."
docker compose -f docker-compose-localhost.yml down 2>/dev/null || true
docker compose -f docker-compose-queue.yml down 2>/dev/null || true

print_header "Building PDF service image..."
# Build with no cache to ensure fresh install
docker build --no-cache -t pdf-service-queue ./pdf-service

if [ $? -ne 0 ]; then
    print_error "Failed to build PDF service image"
    print_warning "Trying alternative build method..."
    
    # Try building with npm install instead of npm ci
    print_header "Building with npm install..."
    docker build --build-arg NPM_CMD="npm install --omit=dev" -t pdf-service-queue ./pdf-service
    
    if [ $? -ne 0 ]; then
        print_error "Failed to build PDF service image with alternative method"
        exit 1
    fi
fi

print_success "PDF service image built successfully"

print_header "Starting queue-based PDF services..."
docker compose -f docker-compose-queue.yml up -d

if [ $? -ne 0 ]; then
    print_error "Failed to start queue services"
    exit 1
fi

print_success "Queue services started successfully"

print_header "Waiting for services to be ready..."
sleep 15

print_header "Checking service health..."

# Check Redis
if docker exec pdf-redis redis-cli ping > /dev/null 2>&1; then
    print_success "Redis is healthy"
else
    print_warning "Redis health check failed"
fi

# Check PDF services
for i in {1..3}; do
    if curl -f -s http://localhost:300$i/health > /dev/null 2>&1; then
        print_success "PDF Service $i is healthy"
    else
        print_error "PDF Service $i is not responding"
    fi
done

# Check Queue Monitor
if curl -f -s http://localhost:3004/api/stats > /dev/null 2>&1; then
    print_success "Queue Monitor is healthy"
else
    print_error "Queue Monitor is not responding"
fi

# Check Load Balancer
if curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
    print_success "Load Balancer is healthy"
else
    print_error "Load Balancer is not responding"
fi

echo ""
print_header "Service URLs:"
echo "=============="
echo "• Load Balancer: http://localhost:8080"
echo "• Queue Monitor: http://localhost:3004"
echo "• WebSocket: ws://localhost:3005"
echo "• PDF Service 1: http://localhost:3001"
echo "• PDF Service 2: http://localhost:3002"
echo "• PDF Service 3: http://localhost:3003"
echo "• Redis: localhost:6379"

echo ""
print_header "Quick Test:"
echo "============="
echo "Test the load balancer:"
echo "curl http://localhost:8080/health"
echo ""
echo "Test bulk PDF generation:"
echo "curl -X POST http://localhost:8080/queue/api/bulk/pdf \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"tenantId\":\"app_imploy_com_au\",\"invoices\":[{\"invoice_number\":\"TEST-001\",\"total_amount\":100}]}'"

echo ""
print_success "Multi-tenant queue system deployed successfully! 🎉"
echo ""
print_header "Next steps:"
echo "============="
echo "1. Update your Laravel .env:"
echo "   PDF_SERVICE_URL=http://62.72.57.236:8080"
echo "   QUEUE_MONITOR_URL=http://62.72.57.236:3004"
echo ""
echo "2. Access the dashboard:"
echo "   http://62.72.57.236:3004"
echo ""
print_success "Ready for bulk invoice email processing! 🚀"

