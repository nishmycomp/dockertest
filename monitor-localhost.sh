#!/bin/bash

echo "📊 Localhost PDF Services Monitor"
echo "================================="

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

print_header "Container Status:"
echo "=================="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(pdf-service|nginx)"

echo ""
print_header "Service Health Checks:"
echo "=========================="

# Check each service
services=(
    "pdf-service-1:3001"
    "pdf-service-2:3002" 
    "pdf-service-3:3003"
    "nginx:80"
)

for service in "${services[@]}"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    
    if curl -f -s http://localhost:$port/health > /dev/null 2>&1; then
        print_success "$name (port $port) is healthy"
    else
        print_error "$name (port $port) is not responding"
    fi
done

echo ""
print_header "Resource Usage:"
echo "================"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep -E "(pdf-service|nginx)"

echo ""
print_header "Load Balancer Test:"
echo "======================"
echo "Testing load balancer distribution..."

for i in {1..6}; do
    response=$(curl -s http://localhost/health 2>/dev/null)
    if [ "$response" = "healthy" ]; then
        print_success "Request $i: Load balancer responding"
    else
        print_error "Request $i: Load balancer not responding"
    fi
    sleep 1
done

echo ""
print_header "Service URLs:"
echo "=============="
echo "• Load Balancer: http://localhost:80"
echo "• PDF Service 1: http://localhost:3001"
echo "• PDF Service 2: http://localhost:3002"
echo "• PDF Service 3: http://localhost:3003"

echo ""
print_header "Quick Commands:"
echo "================"
echo "• View all logs: docker compose -f docker-compose-localhost.yml logs -f"
echo "• Restart services: docker compose -f docker-compose-localhost.yml restart"
echo "• Stop services: docker compose -f docker-compose-localhost.yml down"
echo "• Scale services: docker compose -f docker-compose-localhost.yml up -d --scale pdf-service-1=2"

echo ""
print_header "Performance Info:"
echo "===================="
echo "• 3 PDF service instances"
echo "• 3GB RAM per instance"
echo "• Load balanced with Nginx"
echo "• 15-20 concurrent users capacity"
echo "• No SSL (localhost only)"
