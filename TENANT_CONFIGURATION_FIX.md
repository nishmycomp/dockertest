# Tenant Configuration Fix for PDF Service

## Problem

The PDF service was configured with only two tenants:
- `app_imploy_com_au`
- `tenant_2`

But the Laravel application is using `app_3_my_companionship` as the tenant identifier, which wasn't configured in the PDF service. This caused the error:

```
❌ Error adding email job to queue: Error: Queue not found for tenant: app_3_my_companionship
```

## Solution

### 1. Updated Queue Manager Configuration

Added `app_3_my_companionship` tenant to the PDF service configuration in `docker/pdf-service/queue-manager.js`:

```javascript
const tenants = [
    {
        id: 'app_imploy_com_au',
        name: 'app.imploy.com.au',
        rateLimit: 100,
        concurrency: 5,
        emailRateLimit: 50
    },
    {
        id: 'app_3_my_companionship',  // ← Added this tenant
        name: 'My Companionship',
        rateLimit: 100,
        concurrency: 5,
        emailRateLimit: 50
    },
    {
        id: 'tenant_2',
        name: 'Tenant 2',
        rateLimit: 50,
        concurrency: 3,
        emailRateLimit: 25
    }
];
```

### 2. Updated Laravel URL Mapping

Added the new tenant to the Laravel URL mapping in the `getLaravelUrl()` method:

```javascript
const tenantUrls = {
    'app_imploy_com_au': process.env.LARAVEL_URL || 'http://127.0.0.1:8000',
    'app_3_my_companionship': process.env.LARAVEL_URL || 'http://127.0.0.1:8000',  // ← Added this
    'tenant_2': 'http://tenant2.example.com'
};
```

## Deployment

To deploy the fix, run the deployment script:

```bash
./docker/deploy-tenant-fix.sh
```

This will:
1. Stop existing PDF services
2. Build new images with updated configuration
3. Start updated services
4. Test the health of the services

## Verification

After deployment, you can verify the fix by:

1. **Check Queue Monitor**: Visit `http://localhost:8080/monitor`
2. **Check Logs**: `docker logs -f pdf-worker-1`
3. **Test Email Sending**: Try sending an invoice email from the Laravel application

## Expected Result

- ✅ PDF service now recognizes `app_3_my_companionship` tenant
- ✅ Email jobs can be queued successfully
- ✅ No more "Queue not found" errors
- ✅ Invoice emails can be sent properly

## Future Tenant Management

When adding new tenants to the system:

1. **Add to Queue Manager**: Update the `tenants` array in `queue-manager.js`
2. **Add to URL Mapping**: Update the `tenantUrls` object in `getLaravelUrl()`
3. **Deploy Changes**: Run the deployment script
4. **Test**: Verify the new tenant works correctly

## Troubleshooting

If you still see "Queue not found" errors:

1. **Check Tenant ID**: Ensure the tenant ID matches exactly (case-sensitive)
2. **Restart Services**: The PDF service needs to be restarted to pick up new tenant configurations
3. **Check Logs**: Look for any errors in the PDF service logs
4. **Verify Configuration**: Ensure the tenant is properly added to both the tenants array and URL mapping
