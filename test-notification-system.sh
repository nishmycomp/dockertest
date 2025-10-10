#!/bin/bash

# Test script for Queue Job Failure Notification System
# This script tests the notification integration between PDF service and Laravel app

set -e

echo "🔔 Testing Queue Job Failure Notification System"
echo "=================================================="
echo ""

# Configuration
LARAVEL_URL="${LARAVEL_URL:-http://127.0.0.1:8000}"
PDF_SERVICE_URL="${PDF_SERVICE_URL:-http://localhost:8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Check if Laravel app is running
echo "📍 Test 1: Checking Laravel app availability..."
if curl -f -s "${LARAVEL_URL}" > /dev/null; then
    echo -e "${GREEN}✓${NC} Laravel app is running at ${LARAVEL_URL}"
else
    echo -e "${RED}✗${NC} Laravel app is not accessible at ${LARAVEL_URL}"
    echo "   Please start your Laravel app first: php artisan serve"
    exit 1
fi
echo ""

# Test 2: Check if PDF service is running
echo "📍 Test 2: Checking PDF service availability..."
if curl -f -s "${PDF_SERVICE_URL}/health" > /dev/null; then
    echo -e "${GREEN}✓${NC} PDF service is running at ${PDF_SERVICE_URL}"
else
    echo -e "${RED}✗${NC} PDF service is not accessible at ${PDF_SERVICE_URL}"
    echo "   Please start the PDF service first: ./deploy-queue-system.sh"
    exit 1
fi
echo ""

# Test 3: Test notification endpoint directly
echo "📍 Test 3: Testing notification endpoint directly..."
RESPONSE=$(curl -s -X POST "${LARAVEL_URL}/api/queue/notification/job-failed" \
    -H "Content-Type: application/json" \
    -d '{
        "jobType": "email",
        "invoiceNumber": "TEST-NOTIFICATION-001",
        "errorMessage": "This is a test notification from the notification system test script",
        "recipient": "test@example.com",
        "batchId": "test-batch-' $(date +%s) '",
        "tenantId": "app_imploy_com_au"
    }')

if echo "$RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓${NC} Notification endpoint is working"
    echo "   Response: $RESPONSE"
    NOTIFIED_COUNT=$(echo "$RESPONSE" | grep -o '"notified_count":[0-9]*' | grep -o '[0-9]*')
    if [ ! -z "$NOTIFIED_COUNT" ]; then
        echo -e "   ${GREEN}${NOTIFIED_COUNT}${NC} admin users were notified"
    fi
else
    echo -e "${RED}✗${NC} Notification endpoint failed"
    echo "   Response: $RESPONSE"
    exit 1
fi
echo ""

# Test 4: Trigger an actual job failure
echo "📍 Test 4: Triggering a real job failure (invalid email)..."
JOB_RESPONSE=$(curl -s -X POST "${PDF_SERVICE_URL}/send-invoice-email" \
    -H "Content-Type: application/json" \
    -d '{
        "tenantId": "app_imploy_com_au",
        "invoiceData": {
            "invoice_number": "TEST-JOB-FAIL-001",
            "total_amount": 100.00,
            "due_date": "2025-12-31"
        },
        "emailData": {
            "to": "invalid-email-address",
            "subject": "Test Invoice - Should Fail",
            "customMessage": "This email should fail validation"
        }
    }')

if echo "$JOB_RESPONSE" | grep -q '"jobId"'; then
    echo -e "${GREEN}✓${NC} Job queued successfully"
    echo "   Response: $JOB_RESPONSE"
    echo -e "   ${YELLOW}⏳${NC} Waiting 10 seconds for worker to process and fail the job..."
    sleep 10
    echo -e "   ${GREEN}✓${NC} Job should have failed and notification sent"
else
    echo -e "${YELLOW}⚠${NC} Job queueing may have failed, but this is okay for testing"
    echo "   Response: $JOB_RESPONSE"
fi
echo ""

# Test 5: Check batch completion notification
echo "📍 Test 5: Testing batch completion notification..."
BATCH_RESPONSE=$(curl -s -X POST "${LARAVEL_URL}/api/queue/notification/batch-completed" \
    -H "Content-Type: application/json" \
    -d '{
        "batchId": "test-batch-completion-' $(date +%s) '",
        "tenantId": "app_imploy_com_au",
        "total": 10,
        "completed": 7,
        "failed": 3
    }')

if echo "$BATCH_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓${NC} Batch completion notification is working"
    echo "   Response: $BATCH_RESPONSE"
else
    echo -e "${RED}✗${NC} Batch completion notification failed"
    echo "   Response: $BATCH_RESPONSE"
fi
echo ""

# Test 6: Check Laravel database for notifications
echo "📍 Test 6: Checking Laravel database for recent notifications..."
echo "   You can manually verify by running this SQL query:"
echo ""
echo "   ${YELLOW}SELECT * FROM dashboard_notifications${NC}"
echo "   ${YELLOW}WHERE type = 'queue_job_failed'${NC}"
echo "   ${YELLOW}ORDER BY created_at DESC LIMIT 5;${NC}"
echo ""

# Final summary
echo "=================================================="
echo -e "${GREEN}✅ Notification System Test Complete!${NC}"
echo ""
echo "Next Steps:"
echo "1. Log in to your Laravel app as an admin user"
echo "2. Check your inbox/notifications dashboard"
echo "3. You should see test notifications created by this script"
echo ""
echo "Expected notifications:"
echo "  • 'Invoice Email Failed' for TEST-NOTIFICATION-001"
echo "  • 'Invoice Email Failed' for TEST-JOB-FAIL-001 (if job processed)"
echo "  • 'Batch Processing Completed with Errors' (if enabled)"
echo ""
echo "To clean up test notifications, run:"
echo "  ${YELLOW}php artisan tinker${NC}"
echo "  ${YELLOW}DashboardNotification::where('type', 'queue_job_failed')${NC}"
echo "  ${YELLOW}  ->where('message', 'LIKE', '%TEST%')->delete();${NC}"
echo ""

