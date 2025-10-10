#!/bin/bash

echo "🔐 PDF Service Security Monitor"
echo "=============================="

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

# Check SSL certificate
print_header "SSL Certificate Status:"
echo "=========================="
if [ -f "ssl/cert.pem" ]; then
    print_success "SSL certificate exists"
    echo "Certificate details:"
    openssl x509 -in ssl/cert.pem -text -noout | grep -E "(Subject:|Not Before|Not After|Signature Algorithm)"
    
    # Check certificate expiry
    expiry_date=$(openssl x509 -in ssl/cert.pem -noout -enddate | cut -d= -f2)
    expiry_epoch=$(date -d "$expiry_date" +%s)
    current_epoch=$(date +%s)
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [ $days_until_expiry -gt 30 ]; then
        print_success "Certificate expires in $days_until_expiry days"
    elif [ $days_until_expiry -gt 0 ]; then
        print_warning "Certificate expires in $days_until_expiry days"
    else
        print_error "Certificate has expired!"
    fi
else
    print_error "SSL certificate not found"
fi

echo ""
print_header "HTTPS Security Tests:"
echo "======================="

# Test HTTPS endpoint
if curl -k -f -s https://localhost/health > /dev/null 2>&1; then
    print_success "HTTPS endpoint is responding"
else
    print_error "HTTPS endpoint is not responding"
fi

# Test HTTP redirect
redirect_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health)
if [ "$redirect_status" = "301" ] || [ "$redirect_status" = "302" ]; then
    print_success "HTTP to HTTPS redirect is working"
else
    print_warning "HTTP to HTTPS redirect may not be working (status: $redirect_status)"
fi

# Test security headers
print_status "Testing security headers..."
headers=$(curl -k -s -I https://localhost/health)
if echo "$headers" | grep -q "Strict-Transport-Security"; then
    print_success "HSTS header present"
else
    print_warning "HSTS header missing"
fi

if echo "$headers" | grep -q "X-Frame-Options"; then
    print_success "X-Frame-Options header present"
else
    print_warning "X-Frame-Options header missing"
fi

if echo "$headers" | grep -q "X-Content-Type-Options"; then
    print_success "X-Content-Type-Options header present"
else
    print_warning "X-Content-Type-Options header missing"
fi

echo ""
print_header "Container Security Status:"
echo "=============================="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(pdf-service|nginx)"

echo ""
print_header "SSL/TLS Configuration:"
echo "=========================="
echo "Protocols: TLSv1.2, TLSv1.3"
echo "Ciphers: ECDHE-RSA-AES256-GCM-SHA512, DHE-RSA-AES256-GCM-SHA512"
echo "Session cache: 10m"
echo "Session timeout: 10m"

echo ""
print_header "Security Recommendations:"
echo "==============================="
echo "• Use Let's Encrypt for production certificates"
echo "• Regularly update SSL certificates"
echo "• Monitor certificate expiry dates"
echo "• Enable fail2ban for additional protection"
echo "• Consider using a WAF (Web Application Firewall)"
echo "• Implement rate limiting for API endpoints"

echo ""
print_header "Quick Security Commands:"
echo "============================"
echo "• Check certificate: openssl x509 -in ssl/cert.pem -text -noout"
echo "• Test SSL: openssl s_client -connect localhost:443"
echo "• Renew Let's Encrypt: certbot renew"
echo "• Check security headers: curl -I https://localhost/health"

