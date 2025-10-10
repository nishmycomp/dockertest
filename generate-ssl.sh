#!/bin/bash

echo "🔐 Generating SSL Certificates for PDF Service"
echo "============================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Create SSL directory
mkdir -p ssl
cd ssl

print_status "Generating SSL certificates..."

# Generate private key
print_status "Creating private key..."
openssl genrsa -out key.pem 4096

if [ $? -eq 0 ]; then
    print_success "Private key generated"
else
    print_error "Failed to generate private key"
    exit 1
fi

# Generate certificate signing request
print_status "Creating certificate signing request..."
openssl req -new -key key.pem -out cert.csr -subj "/C=AU/ST=NSW/L=Sydney/O=PDF Service/OU=IT Department/CN=pdf-service.local"

if [ $? -eq 0 ]; then
    print_success "CSR generated"
else
    print_error "Failed to generate CSR"
    exit 1
fi

# Generate self-signed certificate
print_status "Creating self-signed certificate..."
openssl x509 -req -days 365 -in cert.csr -signkey key.pem -out cert.pem

if [ $? -eq 0 ]; then
    print_success "Self-signed certificate generated"
else
    print_error "Failed to generate certificate"
    exit 1
fi

# Set proper permissions
chmod 600 key.pem
chmod 644 cert.pem

print_success "SSL certificates generated successfully!"
print_status "Certificate details:"
openssl x509 -in cert.pem -text -noout | grep -E "(Subject:|Not Before|Not After)"

echo ""
print_warning "Note: This is a self-signed certificate for development/testing."
print_warning "For production, use certificates from a trusted CA like Let's Encrypt."
echo ""
print_status "Files created:"
echo "  • ssl/cert.pem - SSL certificate"
echo "  • ssl/key.pem - Private key"
echo "  • ssl/cert.csr - Certificate signing request (can be deleted)"
echo ""
print_status "To use Let's Encrypt in production:"
echo "  certbot --nginx -d your-domain.com"
echo ""
print_success "SSL setup complete! 🔐"

