#!/bin/bash

echo "🧪 Testing Queue Integration"
echo "============================"

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

print_header "Testing Queue Integration..."

# Test 1: Check if services are running
print_header "1. Checking service health..."
if curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
    print_success "Load balancer is healthy"
else
    print_error "Load balancer is not responding"
    exit 1
fi

# Test 2: Check queue stats before adding jobs
print_header "2. Checking initial queue stats..."
echo "Queue stats before adding jobs:"
curl -s http://localhost:3004/api/stats | jq '.' 2>/dev/null || curl -s http://localhost:3004/api/stats

# Test 3: Add a single PDF job
print_header "3. Adding single PDF job to queue..."
response=$(curl -s -X POST http://localhost:8080/generate-invoice-pdf \
  -H 'Content-Type: application/json' \
  -d '{"invoice":{"invoice_number":"TEST-001","total_amount":100},"tenantId":"app_imploy_com_au"}')

echo "Response: $response"

if echo "$response" | grep -q "queued"; then
    print_success "Single PDF job added to queue"
else
    print_error "Failed to add single PDF job"
fi

# Test 4: Add bulk PDF jobs
print_header "4. Adding bulk PDF jobs to queue..."
bulk_response=$(curl -s -X POST http://localhost:8080/queue/api/bulk/pdf \
  -H 'Content-Type: application/json' \
  -d '{"tenantId":"app_imploy_com_au","invoices":[
    {"invoice_number":"TEST-002","total_amount":200},
    {"invoice_number":"TEST-003","total_amount":300},
    {"invoice_number":"TEST-004","total_amount":400}
  ]}')

echo "Bulk response: $bulk_response"

if echo "$bulk_response" | grep -q "Added"; then
    print_success "Bulk PDF jobs added to queue"
else
    print_error "Failed to add bulk PDF jobs"
fi

# Test 5: Check queue stats after adding jobs
print_header "5. Checking queue stats after adding jobs..."
echo "Queue stats after adding jobs:"
curl -s http://localhost:3004/api/stats | jq '.' 2>/dev/null || curl -s http://localhost:3004/api/stats

# Test 6: Wait a moment and check again
print_header "6. Waiting for jobs to process..."
sleep 5

echo "Queue stats after processing:"
curl -s http://localhost:3004/api/stats | jq '.' 2>/dev/null || curl -s http://localhost:3004/api/stats

print_header "Test completed!"
echo ""
print_success "If you see jobs in the queue stats, the integration is working!"
echo ""
print_header "Dashboard URL: http://62.72.57.236:3004"
print_header "Monitor the queue in real-time!"
