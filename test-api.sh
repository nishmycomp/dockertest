#!/bin/bash

# Test API script for Invoice PDF Service
# Usage: ./test-api.sh [endpoint]
#   health  - Test health endpoint (default)
#   pdf     - Test PDF generation

set -e

ENDPOINT=${1:-health}
PDF_SERVICE_URL=${PDF_SERVICE_URL:-http://localhost:3000}

echo "========================================="
echo "Testing Invoice PDF Service"
echo "Endpoint: $ENDPOINT"
echo "========================================="

case $ENDPOINT in
    health)
        echo "Testing health endpoint..."
        curl -s $PDF_SERVICE_URL/health | jq '.'
        ;;
    pdf)
        echo "Testing PDF generation..."
        curl -s -X POST $PDF_SERVICE_URL/generate-invoice-pdf \
            -H "Content-Type: application/json" \
            -d '{
                "invoice": {
                    "invoice_number": "TEST-001",
                    "invoice_date": "2025-10-09",
                    "due_date": "2025-10-23",
                    "status": "draft",
                    "company_name": "My Companionship",
                    "company_address": "123 Main St, Sydney NSW 2000",
                    "company_phone": "+61 2 1234 5678",
                    "company_email": "info@test.com",
                    "company_abn": "12 345 678 901",
                    "billing_details": {
                        "type": "client",
                        "name": "John Smith",
                        "email": "john@test.com",
                        "address": "456 Test St, Melbourne VIC 3000"
                    },
                    "line_items": [
                        {
                            "description": "Support Services",
                            "service_date": "09/10/2025",
                            "appointment_type": "Personal Care",
                            "entry_type": "service",
                            "quantity": 1,
                            "unit_price": 150.00
                        }
                    ],
                    "subtotal": 150.00,
                    "total_amount": 150.00,
                    "notes": "Test invoice",
                    "payment_terms": "Net 14",
                    "generated_at": "2025-10-09T12:00:00.000Z"
                }
            }' \
            --output test-invoice.pdf
        
        if [ -f test-invoice.pdf ]; then
            echo ""
            echo "PDF generated successfully!"
            echo "File: test-invoice.pdf"
            echo "Size: $(ls -lh test-invoice.pdf | awk '{print $5}')"
        else
            echo "Failed to generate PDF"
            exit 1
        fi
        ;;
    batch)
        echo "Testing batch PDF generation..."
        curl -s -X POST $PDF_SERVICE_URL/generate-batch-pdf \
            -H "Content-Type: application/json" \
            -d '{
                "invoices": [
                    {
                        "invoice_number": "BATCH-001",
                        "invoice_date": "2025-10-09",
                        "status": "draft",
                        "company_name": "Test Company",
                        "billing_details": {"type": "client", "name": "Client 1"},
                        "line_items": [{"description": "Service 1", "quantity": 1, "unit_price": 100}],
                        "subtotal": 100,
                        "total_amount": 100,
                        "generated_at": "2025-10-09T12:00:00.000Z"
                    },
                    {
                        "invoice_number": "BATCH-002",
                        "invoice_date": "2025-10-09",
                        "status": "draft",
                        "company_name": "Test Company",
                        "billing_details": {"type": "client", "name": "Client 2"},
                        "line_items": [{"description": "Service 2", "quantity": 1, "unit_price": 200}],
                        "subtotal": 200,
                        "total_amount": 200,
                        "generated_at": "2025-10-09T12:00:00.000Z"
                    }
                ]
            }' | jq '.'
        ;;
    *)
        echo "Unknown endpoint: $ENDPOINT"
        echo "Usage: ./test-api.sh [health|pdf|batch]"
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo "Test Complete!"
echo "========================================="

