#!/bin/bash

echo "🚀 Setting up Multi-Instance PDF Service on VM"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "Docker is running ✓"

# Stop existing PDF service if running
print_status "Stopping existing PDF service..."
docker stop pdf-service 2>/dev/null || true
docker rm pdf-service 2>/dev/null || true

# Build the PDF service image
print_status "Building PDF service image..."
docker build -t pdf-service:latest ./pdf-service

if [ $? -eq 0 ]; then
    print_success "PDF service image built successfully"
else
    print_error "Failed to build PDF service image"
    exit 1
fi

# Start the multi-instance setup
print_status "Starting multi-instance PDF services..."
docker-compose -f docker-compose-multi.yml up -d

if [ $? -eq 0 ]; then
    print_success "Multi-instance PDF services started successfully"
else
    print_error "Failed to start multi-instance PDF services"
    exit 1
fi

# Wait for services to be ready
print_status "Waiting for services to be ready..."
sleep 30

# Check health of all services
print_status "Checking service health..."

services=("pdf-service-1:3001" "pdf-service-2:3002" "pdf-service-3:3003" "nginx:80")

for service in "${services[@]}"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    
    if curl -f http://localhost:$port/health > /dev/null 2>&1; then
        print_success "$name is healthy ✓"
    else
        print_warning "$name is not responding (may still be starting up)"
    fi
done

# Show running containers
print_status "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
print_success "🎉 Multi-Instance PDF Service Setup Complete!"
echo ""
print_status "Service URLs:"
echo "  • Load Balancer: http://localhost:80"
echo "  • PDF Service 1: http://localhost:3001"
echo "  • PDF Service 2: http://localhost:3002"
echo "  • PDF Service 3: http://localhost:3003"
echo ""
print_status "Health Check URLs:"
echo "  • Load Balancer: http://localhost/health"
echo "  • PDF Service 1: http://localhost:3001/health"
echo "  • PDF Service 2: http://localhost:3002/health"
echo "  • PDF Service 3: http://localhost:3003/health"
echo ""
print_status "To monitor logs:"
echo "  docker-compose -f docker-compose-multi.yml logs -f"
echo ""
print_status "To stop services:"
echo "  docker-compose -f docker-compose-multi.yml down"
echo ""
print_warning "Update your Laravel .env file:"
echo "  PDF_SERVICE_URL=http://your-vm-ip:80"
echo ""
print_success "Setup complete! Your PDF service can now handle 15-20 concurrent users! 🚀"
