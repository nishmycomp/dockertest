#!/bin/bash

echo "🔧 Fixing Missing Morgan Dependency"
echo "=================================="

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

print_header "Stopping all PDF services..."
docker compose -f docker-compose-queue.yml down

print_header "Adding missing dependencies to package.json..."
# Add morgan and ws to package.json
cd pdf-service
if ! grep -q "morgan" package.json; then
    # Add morgan dependency
    sed -i '/"dotenv": "^16.3.1"/a\    "morgan": "^1.10.0",' package.json
    print_success "Added morgan dependency"
fi

if ! grep -q "ws" package.json; then
    # Add ws dependency
    sed -i '/"morgan": "^1.10.0"/a\    "ws": "^8.14.2"' package.json
    print_success "Added ws dependency"
fi

print_header "Installing dependencies..."
npm install

if [ $? -eq 0 ]; then
    print_success "Dependencies installed successfully"
else
    print_error "Failed to install dependencies"
    exit 1
fi

cd ..

print_header "Rebuilding Docker images..."
docker compose -f docker-compose-queue.yml build --no-cache

if [ $? -eq 0 ]; then
    print_success "Docker images rebuilt successfully"
else
    print_error "Failed to rebuild Docker images"
    exit 1
fi

print_header "Starting services..."
docker compose -f docker-compose-queue.yml up -d

if [ $? -eq 0 ]; then
    print_success "Services started successfully"
else
    print_error "Failed to start services"
    exit 1
fi

print_header "Waiting for services to start..."
sleep 15

print_header "Checking service health..."

# Check PDF services
for i in {1..3}; do
    if curl -f -s http://localhost:300$i/health > /dev/null 2>&1; then
        print_success "PDF Service $i is healthy"
    else
        print_error "PDF Service $i is not responding"
    fi
done

# Check Load Balancer
if curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
    print_success "Load Balancer is healthy"
else
    print_error "Load Balancer is not responding"
fi

echo ""
print_success "Morgan dependency fix completed! 🎉"
echo ""
print_header "Service URLs:"
echo "=============="
echo "• Load Balancer: http://localhost:8080"
echo "• Queue Monitor: http://localhost:3004"
echo "• PDF Service 1: http://localhost:3001"
echo "• PDF Service 2: http://localhost:3002"
echo "• PDF Service 3: http://localhost:3003"
echo ""
print_success "Ready for bulk invoice processing! 🚀"

