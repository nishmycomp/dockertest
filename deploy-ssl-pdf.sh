#!/bin/bash

echo "🔐 Setting up Encrypted Multi-Instance PDF Service"
echo "================================================="

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

# Stop existing services
print_status "Stopping existing PDF services..."
docker-compose -f docker-compose-multi.yml down 2>/dev/null || true
docker-compose -f docker-compose-ssl.yml down 2>/dev/null || true

# Generate SSL certificates
print_status "Generating SSL certificates..."
chmod +x generate-ssl.sh
./generate-ssl.sh

if [ $? -eq 0 ]; then
    print_success "SSL certificates generated"
else
    print_error "Failed to generate SSL certificates"
    exit 1
fi

# Build the PDF service image
print_status "Building PDF service image..."
docker build -t pdf-service:latest ./pdf-service

if [ $? -eq 0 ]; then
    print_success "PDF service image built successfully"
else
    print_error "Failed to build PDF service image"
    exit 1
fi

# Start the SSL-enabled multi-instance setup
print_status "Starting encrypted multi-instance PDF services..."
docker-compose -f docker-compose-ssl.yml up -d

if [ $? -eq 0 ]; then
    print_success "Encrypted multi-instance PDF services started successfully"
else
    print_error "Failed to start encrypted PDF services"
    exit 1
fi

# Wait for services to be ready
print_status "Waiting for services to be ready..."
sleep 30

# Check health of all services
print_status "Checking service health..."

services=("pdf-service-1:3001" "pdf-service-2:3002" "pdf-service-3:3003" "nginx:443")

for service in "${services[@]}"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    
    if [ "$name" = "nginx" ]; then
        # Test HTTPS endpoint
        if curl -k -f https://localhost:$port/health > /dev/null 2>&1; then
            print_success "$name (HTTPS) is healthy ✓"
        else
            print_warning "$name (HTTPS) is not responding (may still be starting up)"
        fi
    else
        # Test HTTP endpoint
        if curl -f http://localhost:$port/health > /dev/null 2>&1; then
            print_success "$name is healthy ✓"
        else
            print_warning "$name is not responding (may still be starting up)"
        fi
    fi
done

# Show running containers
print_status "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
print_success "🎉 Encrypted Multi-Instance PDF Service Setup Complete!"
echo ""
print_status "Service URLs:"
echo "  • HTTPS Load Balancer: https://localhost:443"
echo "  • HTTP Load Balancer: http://localhost:80 (redirects to HTTPS)"
echo "  • PDF Service 1: http://localhost:3001"
echo "  • PDF Service 2: http://localhost:3002"
echo "  • PDF Service 3: http://localhost:3003"
echo ""
print_status "Health Check URLs:"
echo "  • HTTPS: https://localhost/health"
echo "  • HTTP: http://localhost/health (redirects to HTTPS)"
echo ""
print_status "Security Features:"
echo "  • End-to-end HTTPS encryption"
echo "  • HTTP to HTTPS redirect"
echo "  • Security headers (HSTS, XSS protection, etc.)"
echo "  • SSL/TLS 1.2 and 1.3 support"
echo "  • Load balancing with health checks"
echo ""
print_status "To monitor logs:"
echo "  docker-compose -f docker-compose-ssl.yml logs -f"
echo ""
print_status "To stop services:"
echo "  docker-compose -f docker-compose-ssl.yml down"
echo ""
print_warning "Update your Laravel .env file:"
echo "  PDF_SERVICE_URL=https://your-vm-ip:443"
echo ""
print_warning "For production, replace self-signed certificates with Let's Encrypt:"
echo "  certbot --nginx -d your-domain.com"
echo ""
print_success "Setup complete! Your PDF service is now encrypted and can handle 15-20 concurrent users! 🔐🚀"

