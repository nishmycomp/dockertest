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
docker build -t pdf-service-queue ./pdf-service

if [ $? -ne 0 ]; then
    print_error "Failed to build PDF service image"
    exit 1
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
sleep 10

print_header "Checking service health..."

# Check Redis
if curl -f -s http://localhost:6379 > /dev/null 2>&1; then
    print_success "Redis is healthy"
else
    print_warning "Redis health check failed (this is normal for Redis)"
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
print_header "Queue Management:"
echo "===================="
echo "• View dashboard: http://localhost:3004"
echo "• API endpoints: http://localhost:8080/queue/api/"
echo "• Bulk operations: POST to /queue/api/bulk/pdf or /queue/api/bulk/email"

echo ""
print_header "Test the system:"
echo "==================="
echo "1. Open dashboard: http://localhost:3004"
echo "2. Test bulk PDF generation:"
echo "   curl -X POST http://localhost:8080/queue/api/bulk/pdf \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"tenantId\":\"app_imploy_com_au\",\"invoices\":[{\"invoice_number\":\"TEST-001\",\"total_amount\":100}]}'"

echo ""
print_header "Monitor services:"
echo "===================="
echo "• View logs: docker compose -f docker-compose-queue.yml logs -f"
echo "• Check stats: docker compose -f docker-compose-queue.yml ps"
echo "• Restart: docker compose -f docker-compose-queue.yml restart"

echo ""
print_success "Multi-tenant queue system deployed successfully! 🎉"
echo ""
print_header "Next steps:"
echo "============="
echo "1. Update your Laravel .env:"
echo "   PDF_SERVICE_URL=http://62.72.57.236:8080"
echo "   QUEUE_MONITOR_URL=http://62.72.57.236:3004"
echo ""
echo "2. Test bulk invoice processing from your Laravel app"
echo "3. Monitor queue performance in the dashboard"
echo ""
print_success "Ready for bulk invoice email processing! 🚀"
