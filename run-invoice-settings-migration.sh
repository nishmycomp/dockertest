#!/bin/bash

# Script to run invoice settings migration on AlmaLinux server
# This adds invoice-related fields to the extras table

echo "=========================================="
echo "Invoice Settings Migration Script"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if we're on the server
if [ ! -f "/var/www/app.imploy.com.au/artisan" ]; then
    echo -e "${RED}Error: Not in the correct directory${NC}"
    echo "Please run this script from the AlmaLinux server"
    echo "Expected path: /var/www/app.imploy.com.au"
    exit 1
fi

echo -e "${YELLOW}Step 1: Navigating to application directory...${NC}"
cd /var/www/app.imploy.com.au || exit 1
echo -e "${GREEN}✓ In application directory${NC}"
echo ""

echo -e "${YELLOW}Step 2: Checking current migration status...${NC}"
php artisan migrate:status | grep "extras_table"
echo ""

echo -e "${YELLOW}Step 3: Running invoice settings migration...${NC}"
echo "This will add the following fields to the extras table:"
echo "  - invoice_company_name"
echo "  - invoice_company_address"
echo "  - invoice_company_phone"
echo "  - invoice_company_email"
echo "  - invoice_company_abn"
echo "  - invoice_company_logo_url"
echo "  - invoice_payment_account_name"
echo "  - invoice_payment_bsb"
echo "  - invoice_payment_account_number"
echo "  - invoice_payment_terms"
echo "  - invoice_late_fee_policy"
echo "  - invoice_default_due_days"
echo ""

# Run the specific migration
php artisan migrate --path=database/migrations/2025_10_10_000005_add_invoice_settings_to_extras_table.php

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Migration completed successfully!${NC}"
    echo ""
    
    echo -e "${YELLOW}Step 4: Verifying migration...${NC}"
    php artisan migrate:status | grep "add_invoice_settings_to_extras_table"
    echo ""
    
    echo -e "${GREEN}=========================================="
    echo "Migration Complete!"
    echo "==========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Go to Settings → Extra Setting in the application"
    echo "2. Scroll to the 'Invoice Settings' section"
    echo "3. Fill in your company and payment details"
    echo "4. Click 'Update Invoice Settings'"
    echo ""
    echo "Your invoice PDFs will now use these settings!"
else
    echo ""
    echo -e "${RED}✗ Migration failed!${NC}"
    echo ""
    echo "Please check the error message above."
    echo "You may need to run: php artisan migrate:rollback"
    echo "Then try again."
    exit 1
fi

