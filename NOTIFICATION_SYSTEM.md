# Queue Job Failure Notification System

This document describes how the PDF service queue system sends notifications to the Laravel app's inbox when jobs fail.

## Overview

When a PDF generation or email sending job fails in the queue system, the PDF service automatically sends a notification to the Laravel application, which creates an inbox notification for admin users.

## Architecture

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│  Queue Worker   │──────▶│  Queue Manager  │──────▶│  Laravel App    │
│  (Job Failed)   │       │  logJobError()  │       │  Inbox API      │
└─────────────────┘       └─────────────────┘       └─────────────────┘
                                   │
                                   ▼
                          ┌─────────────────┐
                          │     Redis       │
                          │  (Error Store)  │
                          └─────────────────┘
```

## Components

### 1. Queue Manager (`queue-manager.js`)

**Function: `logJobError()`**
- Stores error details in Redis
- Sends HTTP notification to Laravel app

**Function: `sendFailureNotification()`**
- Makes POST request to Laravel API endpoint
- Includes job type, invoice number, error message, recipient, batch ID

**Function: `getLaravelUrl()`**
- Maps tenant IDs to Laravel app URLs
- Configurable via `LARAVEL_URL` environment variable

### 2. Laravel API Endpoint

**Route:** `POST /api/queue/notification/job-failed`

**Controller:** `App\Http\Controllers\Api\QueueNotificationController`

**Payload:**
```json
{
  "jobType": "pdf|email",
  "invoiceNumber": "INV-2025100001",
  "errorMessage": "SMTP connection failed",
  "recipient": "client@example.com",
  "batchId": "batch-2025-10-10-abc123",
  "tenantId": "app_imploy_com_au"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Notification sent to admin users",
  "notified_count": 3
}
```

### 3. Dashboard Notifications

**Model:** `App\Models\DashboardNotification`

**Table:** `dashboard_notifications`

**Notification Type:** `queue_job_failed`

**Fields:**
- `type`: `queue_job_failed`
- `title`: "Invoice Email Failed" or "Invoice PDF Generation Failed"
- `message`: Human-readable failure description
- `data`: JSON object with full error details
- `user_id`: Admin user to notify
- `is_read`: false (initially)

## Configuration

### PDF Service Environment Variables

Add to `docker/pdf-service/.env`:

```env
# Laravel Application URL (for notifications)
LARAVEL_URL=http://127.0.0.1:8000

# Laravel API Token (optional, for authentication)
LARAVEL_API_TOKEN=your-api-token-here
```

### Docker Compose

The `docker-compose-queue.yml` file already passes these variables to worker containers:

```yaml
environment:
  - LARAVEL_URL=${LARAVEL_URL:-http://127.0.0.1:8000}
  - LARAVEL_API_TOKEN=${LARAVEL_API_TOKEN}
```

You can also create a `.env` file in the `docker/` directory:

```env
LARAVEL_URL=http://127.0.0.1:8000
LARAVEL_API_TOKEN=your-token-here
```

### Multi-Tenant Configuration

For multiple tenants with different Laravel apps, update `getLaravelUrl()` in `queue-manager.js`:

```javascript
getLaravelUrl(tenantId) {
    const tenantUrls = {
        'app_imploy_com_au': 'http://127.0.0.1:8000',
        'tenant_2': 'http://tenant2.example.com',
        'tenant_3': 'http://tenant3.example.com'
    };
    
    return tenantUrls[tenantId] || process.env.LARAVEL_URL || 'http://127.0.0.1:8000';
}
```

## User Notification Targeting

The notification system intelligently determines who to notify:

### Primary Behavior (Preferred)
- **Notifies the specific user who initiated the bulk operation**
- The `userId` is tracked from the moment a user clicks "Download Selected" or sends bulk emails
- This userId is passed through Laravel → PDF Service → Queue → Back to Laravel

### Fallback Behavior
If no `userId` is provided (e.g., for legacy operations or system-generated jobs):
- Notifications are sent to admin users with:
  - `user_type_id = 1` (admin users)
  - OR email ending in `@imploy.com.au`

### How It Works
1. User clicks "Download Selected" in Laravel
2. Laravel captures `Auth::id()` (the current user's ID)
3. Laravel passes `userId` to PDF service when starting the batch
4. PDF service stores `userId` with the batch in Redis
5. When a job fails, PDF service retrieves `userId` from the batch
6. PDF service sends notification to Laravel with `userId`
7. Laravel creates notification **only for that specific user**

To customize the fallback admin query, edit `QueueNotificationController::jobFailed()`:

```php
$usersToNotify = User::where('user_type_id', 1)
    ->orWhere('role', 'admin')
    ->get()
    ->toArray();
```

## Viewing Notifications

Admin users will see failure notifications in their Laravel app inbox/dashboard:

1. **Title:** "Invoice Email Failed" or "Invoice PDF Generation Failed"
2. **Message:** Includes invoice number, recipient (for emails), error message, and batch ID
3. **Data:** Full JSON payload for debugging

Example notification message:
```
Email failed for invoice INV-2025100001. 
Recipient: client@example.com. 
Error: Connection timeout. 
(Batch: batch-2025-10-10-abc123)
```

## Error Handling

### Graceful Degradation

If the notification fails to send (Laravel app down, network issue, etc.):
- The error is logged but **not thrown**
- Job processing continues normally
- The error is still stored in Redis for manual review

### Logs

Check PDF service logs for notification status:
```bash
docker logs pdf-worker-1 | grep "notification"
```

Expected output:
```
📬 Failure notification sent to Laravel: Notification sent to admin users
```

Or if failed:
```
⚠️ Failed to send notification to Laravel: connect ECONNREFUSED
```

## Testing

### 1. Trigger a Test Failure

Intentionally cause a job to fail (e.g., invalid email address):

```bash
curl -X POST http://localhost:8080/send-invoice-email \
  -H "Content-Type: application/json" \
  -d '{
    "tenantId": "app_imploy_com_au",
    "invoiceData": {"invoice_number": "TEST-001"},
    "emailData": {
      "to": "invalid-email",
      "subject": "Test",
      "customMessage": "Test"
    }
  }'
```

### 2. Check Laravel Inbox

Log in to your Laravel app as an admin user and check your notifications/inbox.

### 3. Direct API Test

Test the notification endpoint directly:

```bash
curl -X POST http://127.0.0.1:8000/api/queue/notification/job-failed \
  -H "Content-Type: application/json" \
  -d '{
    "jobType": "email",
    "invoiceNumber": "TEST-001",
    "errorMessage": "Test notification",
    "recipient": "test@example.com",
    "batchId": "test-batch",
    "tenantId": "app_imploy_com_au"
  }'
```

Expected response:
```json
{
  "success": true,
  "message": "Notification sent to admin users",
  "notified_count": 2
}
```

### 4. Check Database

Verify notifications were created:

```sql
SELECT * FROM dashboard_notifications 
WHERE type = 'queue_job_failed' 
ORDER BY created_at DESC 
LIMIT 5;
```

## Batch Completion Notifications

For batch operations, you can also receive a summary notification when a batch completes with errors.

**Route:** `POST /api/queue/notification/batch-completed`

**Payload:**
```json
{
  "batchId": "batch-2025-10-10-abc123",
  "tenantId": "app_imploy_com_au",
  "total": 100,
  "completed": 95,
  "failed": 5
}
```

This creates a notification like:
```
Batch batch-2025-10-10-abc123 completed: 95/100 succeeded, 5 failed. 
Check queue monitor for details.
```

## Security Considerations

1. **No Authentication Required:** The notification endpoints do not require authentication by default. Consider adding API token validation if your PDF service is publicly accessible.

2. **Rate Limiting:** The Laravel app should implement rate limiting on these endpoints to prevent abuse.

3. **Validation:** All input is validated before creating notifications.

## Troubleshooting

### Notifications Not Appearing

1. **Check PDF service logs:** Look for "Failed to send notification"
2. **Check Laravel logs:** `storage/logs/laravel.log`
3. **Verify LARAVEL_URL:** Ensure it's accessible from the Docker container
4. **Check admin user query:** Ensure your admin users match the query criteria

### Container Networking Issues

If running Laravel locally and PDF service in Docker:
- Use `host.docker.internal` instead of `localhost` or `127.0.0.1`
- Update `LARAVEL_URL=http://host.docker.internal:8000`

For production (both in Docker):
- Use the service name: `LARAVEL_URL=http://laravel-app`
- Or use the external domain: `LARAVEL_URL=https://app.imploy.com.au`

### Too Many Notifications

If you're getting too many notifications, you can:
1. Only notify on batches (not individual jobs)
2. Add a threshold (only notify if > X failures)
3. Implement notification grouping/throttling

Example modification:
```javascript
// Only send notification if this is part of a batch
if (batchId) {
    await this.sendFailureNotification(...);
}
```

## Future Enhancements

- [ ] Email notifications (in addition to inbox)
- [ ] Slack/Discord webhook integration
- [ ] Notification throttling/grouping
- [ ] Custom notification templates per tenant
- [ ] Admin dashboard widget for recent failures
- [ ] Retry failed jobs directly from notification


