# Invoice PDF Generation Service

A microservice for generating professional PDF invoices using Node.js, Puppeteer, and Handlebars.

## Features

- 🚀 Fast PDF generation using Puppeteer
- 📄 Professional invoice templates with Handlebars
- 🔄 Batch PDF generation support
- 🏥 Health check endpoints
- 🐳 Docker-ready with optimized Alpine image
- 💾 Low memory footprint
- 🔒 Secure and isolated

## Prerequisites

- Docker & Docker Compose
- Node.js 18+ (for local development)

## Quick Start

### Using Docker Compose

```bash
# Build and start the service
cd docker
docker-compose up -d

# Check logs
docker-compose logs -f pdf-service

# Stop the service
docker-compose down
```

### Using Docker

```bash
# Build the image
cd docker/pdf-service
docker build -t invoice-pdf-service .

# Run the container
docker run -d -p 3000:3000 --name pdf-service invoice-pdf-service

# Check health
curl http://localhost:3000/health
```

### Local Development

```bash
cd docker/pdf-service

# Install dependencies
npm install

# Create .env file
cp env.example .env

# Start the service
npm start

# Or use nodemon for development
npm run dev
```

## API Endpoints

### Health Check
```http
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-10-09T12:00:00.000Z"
}
```

### Generate Single Invoice PDF
```http
POST /generate-invoice-pdf
Content-Type: application/json

{
  "invoice": {
    "invoice_number": "INV-2025100001",
    "invoice_date": "2025-10-09",
    "due_date": "2025-10-23",
    "status": "draft",
    "company_name": "My Companionship",
    "company_address": "123 Main St, Sydney NSW 2000",
    "company_phone": "+61 2 1234 5678",
    "company_email": "info@mycompanionship.com.au",
    "company_abn": "12 345 678 901",
    "billing_details": {
      "type": "organization",
      "name": "ABC Organization",
      "email": "billing@abc.com.au",
      "phone": "+61 2 9876 5432",
      "address": "456 Business Ave, Melbourne VIC 3000",
      "abn": "98 765 432 109"
    },
    "client_name": "John Smith",
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
    "tax_amount": 0,
    "total_amount": 150.00,
    "notes": "Payment due within 14 days",
    "payment_terms": "Net 14",
    "generated_at": "2025-10-09T12:00:00.000Z"
  }
}
```

**Response:**
- Content-Type: `application/pdf`
- File download with name: `invoice-{invoice_number}.pdf`

### Generate Batch PDFs
```http
POST /generate-batch-pdf
Content-Type: application/json

{
  "invoices": [
    { /* invoice object 1 */ },
    { /* invoice object 2 */ },
    { /* invoice object 3 */ }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "results": [
    {
      "invoice_number": "INV-2025100001",
      "success": true,
      "pdf": "base64-encoded-pdf-data"
    },
    {
      "invoice_number": "INV-2025100002",
      "success": true,
      "pdf": "base64-encoded-pdf-data"
    }
  ],
  "total": 2,
  "successful": 2,
  "failed": 0
}
```

## Invoice Data Structure

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `invoice_number` | string | Yes | Unique invoice identifier |
| `invoice_date` | string | Yes | Invoice issue date |
| `due_date` | string | No | Payment due date |
| `status` | string | No | Invoice status (draft/sent/paid/overdue) |
| `company_name` | string | Yes | Your company name |
| `company_address` | string | No | Company address |
| `company_phone` | string | No | Company phone |
| `company_email` | string | No | Company email |
| `company_abn` | string | No | Company ABN |
| `billing_details` | object | Yes | Billing party details |
| `client_name` | string | No | Service recipient name |
| `line_items` | array | Yes | Invoice line items |
| `subtotal` | number | Yes | Subtotal amount |
| `tax_amount` | number | No | Tax amount |
| `discount_amount` | number | No | Discount amount |
| `total_amount` | number | Yes | Total amount |
| `notes` | string | No | Invoice notes |
| `payment_terms` | string | No | Payment terms |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_ENV` | development | Environment mode |
| `PORT` | 3000 | Service port |
| `PUPPETEER_EXECUTABLE_PATH` | /usr/bin/chromium-browser | Chromium path |

## Performance

- **Average Generation Time:** 500-800ms per invoice
- **Memory Usage:** ~300-500MB
- **Concurrent Requests:** Supports multiple concurrent requests
- **Batch Processing:** Optimized for batch generation

## Customization

### Modify Invoice Template

Edit `templates/invoice-template.hbs` to customize the invoice layout and styling.

### Add Custom Helpers

Add Handlebars helpers in `server.js`:

```javascript
Handlebars.registerHelper('myHelper', function(param) {
    // Your logic here
    return result;
});
```

## Troubleshooting

### PDF Generation Fails

1. Check Chromium installation:
```bash
docker exec -it pdf-service which chromium-browser
```

2. Check service logs:
```bash
docker-compose logs pdf-service
```

### Memory Issues

Increase Docker memory limits in `docker-compose.yml`:
```yaml
deploy:
  resources:
    limits:
      memory: 2G
```

### Slow Generation

- Use batch endpoint for multiple invoices
- Increase CPU limits
- Enable browser instance pooling (already implemented)

## Security Considerations

- Service runs in isolated Docker container
- No direct file system access from outside
- Rate limiting recommended for production
- API authentication should be implemented

## Production Deployment

1. Set up reverse proxy (nginx/traefik)
2. Enable HTTPS
3. Implement API authentication
4. Configure monitoring and logging
5. Set up auto-scaling if needed
6. Regular security updates

## Integration with Laravel

See `app/Services/PdfService.php` for Laravel integration example.

## License

Proprietary - Imploy

## Support

For issues or questions, contact the development team.

