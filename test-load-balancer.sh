#!/bin/bash

echo "🚀 Load Balancer Stress Test - 300 PDF Requests"
echo "=============================================="

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

# Check if load balancer is responding
echo "🔍 Checking load balancer health..."
if curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
    print_success "Load balancer is healthy"
else
    print_error "Load balancer is not responding"
    exit 1
fi

echo ""
print_header "Starting 300 PDF generation requests..."
echo "This will test load distribution across 3 PDF service instances"
echo ""

# Create a simple test invoice data
INVOICE_DATA='{
    "invoice": {
        "invoice_number": "TEST-001",
        "total_amount": 100,
        "client_name": "Test Client",
        "line_items": [
            {
                "description": "Test Service",
                "quantity": 1,
                "rate": 100,
                "amount": 100
            }
        ]
    }
}'

# Counters
SUCCESS_COUNT=0
ERROR_COUNT=0
TOTAL_REQUESTS=300

echo "📊 Sending $TOTAL_REQUESTS requests to load balancer..."
echo "⏱️  This may take a few minutes..."
echo ""

# Start time
START_TIME=$(date +%s)

# Send requests in batches of 10 with 0.1 second delay between batches
for i in $(seq 1 $TOTAL_REQUESTS); do
    # Send request in background
    (
        response=$(curl -s -w "%{http_code}" -X POST http://localhost:8080/generate-invoice-pdf \
            -H 'Content-Type: application/json' \
            -d "$INVOICE_DATA" \
            --output /dev/null 2>/dev/null)
        
        if [ "$response" = "200" ]; then
            echo "✓ Request $i: Success"
        else
            echo "✗ Request $i: Failed (HTTP $response)"
        fi
    ) &
    
    # Limit concurrent requests to avoid overwhelming
    if [ $((i % 10)) -eq 0 ]; then
        wait
        echo "📈 Processed $i/$TOTAL_REQUESTS requests..."
        sleep 0.1
    fi
done

# Wait for all background processes
wait

# End time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
print_header "Test Results:"
echo "=============="
echo "📊 Total requests: $TOTAL_REQUESTS"
echo "⏱️  Duration: ${DURATION} seconds"
echo "📈 Average: $((TOTAL_REQUESTS / DURATION)) requests/second"

echo ""
print_header "Check service distribution:"
echo "================================="
echo "Run these commands to see which services handled the requests:"
echo ""
echo "docker logs pdf-service-1 | grep -c 'Received PDF generation request'"
echo "docker logs pdf-service-2 | grep -c 'Received PDF generation request'"
echo "docker logs pdf-service-3 | grep -c 'Received PDF generation request'"
echo ""

print_header "Monitor in real-time:"
echo "========================="
echo "To watch the load balancing in action, run:"
echo "docker compose -f docker-compose-localhost.yml logs -f"
echo ""

print_header "Performance check:"
echo "======================"
echo "Check resource usage:"
echo "docker stats --no-stream"

