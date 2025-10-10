# User-Specific Notifications - Implementation Guide

## Overview

The notification system now tracks which user initiated a bulk operation and sends failure notifications **only to that specific user**, not to all admins.

## How It Works

### The User Journey

1. **User Action**: Jane (user ID: 42) logs into `app.imploy.com.au`
2. **Selects Invoices**: She selects 10 invoices and clicks "Download Selected"
3. **System Tracking**: Laravel captures her user ID (`Auth::id()` = 42)
4. **Batch Creation**: A batch is created with `userId: 42` stored in Redis
5. **Job Processing**: Queue workers process the PDF generation jobs
6. **Job Failure**: 2 out of 10 PDFs fail to generate
7. **Notification**: Jane (and only Jane) receives 2 inbox notifications about the failures
8. **Other Users**: John, Mary, and other admins see nothing - these weren't their jobs

### The Technical Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  User: Jane (ID: 42)                                            │
│  Action: Clicks "Download Selected"                             │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  Laravel: PlatformInvoiceController::bulkDownload()             │
│  - Captures: Auth::id() = 42                                    │
│  - Calls: PdfService::generateBatchPdfs($invoices, 42)          │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  Laravel: PdfService::generateBatchPdfs()                       │
│  - Creates batch ID: batch-20251010-143022-abc123               │
│  - Sends to PDF service:                                        │
│    POST /queue/batch/start                                      │
│    { batchId, total: 10, userId: 42 }                           │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  PDF Service: QueueManager::startBatch()                        │
│  - Stores in Redis:                                             │
│    batch:app_imploy_com_au:batch-20251010-143022-abc123         │
│    { total: 10, completed: 0, failed: 0, userId: 42 }           │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  Queue Workers: Process 10 PDF jobs                             │
│  - 8 succeed ✓                                                  │
│  - 2 fail ✗ (INV-001, INV-005)                                  │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  PDF Service: QueueManager::logJobError()                       │
│  For each failure:                                              │
│  - Retrieves userId from batch (userId: 42)                     │
│  - Calls: sendFailureNotification()                             │
│    POST http://127.0.0.1:8000/api/queue/notification/job-failed │
│    { invoiceNumber, errorMessage, userId: 42, ... }             │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  Laravel: QueueNotificationController::jobFailed()              │
│  - Receives userId: 42                                          │
│  - Finds User: Jane (ID: 42)                                    │
│  - Creates DashboardNotification for Jane ONLY                  │
│    { user_id: 42, title: "PDF Generation Failed", ... }         │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  Jane's Inbox: Shows 2 new notifications                        │
│  - "Invoice PDF Generation Failed for INV-001"                  │
│  - "Invoice PDF Generation Failed for INV-005"                  │
└─────────────────────────────────────────────────────────────────┘
```

## Code Changes Summary

### 1. Laravel: Capture User ID

**File**: `app/Http/Controllers/Admin/PlatformInvoiceController.php`

```php
public function bulkDownload(Request $request)
{
    // ... validation ...
    
    $pdfService = new \App\Services\PdfService();
    $result = $pdfService->generateBatchPdfs($invoices->all(), Auth::id()); // ← Pass user ID
    
    // ... response ...
}
```

### 2. Laravel: Pass to PDF Service

**File**: `app/Services/PdfService.php`

```php
public function generateBatchPdfs(array $invoices, $userId = null) // ← Accept user ID
{
    // Initialize batch with userId
    $batchStartResponse = Http::timeout(10)
        ->post($this->pdfServiceUrl . '/queue/batch/start', [
            'tenantId' => $tenantId,
            'batchId' => $batchId,
            'total' => $total,
            'userId' => $userId // ← Send to PDF service
        ]);
    
    // Queue each PDF job with userId
    foreach ($invoices as $invoice) {
        $response = Http::timeout(30)
            ->post($this->pdfServiceUrl . '/generate-invoice-pdf', [
                'invoice' => $invoiceData,
                'tenantId' => $tenantId,
                'batchId' => $batchId,
                'userId' => $userId // ← Include in each job
            ]);
    }
}
```

### 3. PDF Service: Store User ID

**File**: `docker/pdf-service/server.js`

```javascript
app.post('/queue/batch/start', async (req, res) => {
    const { tenantId = 'app_imploy_com_au', batchId, total, userId } = req.body || {};
    await queueManager.startBatch(tenantId, String(batchId), Number(total), userId); // ← Pass userId
    res.json({ success: true });
});
```

**File**: `docker/pdf-service/queue-manager.js`

```javascript
async startBatch(tenantId, batchId, total, userId = null) {
    const batchData = { 
        total: total, 
        completed: 0, 
        failed: 0, 
        createdAt: Date.now()
    };
    if (userId) {
        batchData.userId = userId; // ← Store userId in Redis
    }
    await this.hSetCompat(key, batchData);
}
```

### 4. PDF Service: Retrieve and Send User ID

**File**: `docker/pdf-service/queue-manager.js`

```javascript
async sendFailureNotification(tenantId, jobType, invoiceNumber, errorMessage, batchId, recipient = null) {
    // Get userId from batch if available
    let userId = null;
    if (batchId) {
        const batchStatus = await this.getBatchStatus(tenantId, batchId);
        userId = batchStatus?.userId || null; // ← Retrieve userId from Redis
    }
    
    const notificationPayload = {
        jobType,
        invoiceNumber,
        errorMessage,
        recipient,
        batchId,
        tenantId,
        userId // ← Send to Laravel
    };

    await axios.post(`${laravelUrl}/api/queue/notification/job-failed`, notificationPayload);
}
```

### 5. Laravel: Notify Specific User

**File**: `app/Http/Controllers/Api/QueueNotificationController.php`

```php
public function jobFailed(Request $request)
{
    $validated = $request->validate([
        'jobType' => 'required|string|in:pdf,email',
        'invoiceNumber' => 'required|string',
        'errorMessage' => 'required|string',
        'userId' => 'nullable|integer', // ← Accept userId
        // ... other fields ...
    ]);

    // Determine who to notify
    $usersToNotify = [];
    
    if (!empty($validated['userId'])) {
        // Notify the specific user who initiated the operation
        $initiatingUser = User::find($validated['userId']); // ← Find the specific user
        if ($initiatingUser) {
            $usersToNotify[] = $initiatingUser; // ← Only this user
        }
    }
    
    // Fallback to admin users if no userId
    if (empty($usersToNotify)) {
        $usersToNotify = User::where('user_type_id', 1)
            ->orWhere('email', 'LIKE', '%@imploy.com.au')
            ->get()
            ->toArray();
    }

    // Create notifications for targeted users
    foreach ($usersToNotify as $user) {
        DashboardNotification::create([
            'type' => 'queue_job_failed',
            'title' => $title,
            'message' => $message,
            'user_id' => is_array($user) ? $user['id'] : $user->id, // ← Specific user
            'is_read' => false
        ]);
    }
}
```

## Benefits

### 1. **Privacy**
- Users only see their own failures, not everyone else's
- Reduces notification noise

### 2. **Accountability**
- Clear tracking of who initiated each batch
- Audit trail for bulk operations

### 3. **User Experience**
- Relevant notifications only
- Users can act on their own failures without confusion

### 4. **Scalability**
- In a multi-user SaaS environment, prevents notification spam
- Each user manages their own queue jobs

## Testing

### Test User-Specific Notifications

1. **Login as User 1**:
   ```
   Email: user1@imploy.com.au
   ```

2. **Select and download invoices**:
   - Go to Platform Invoices
   - Select 5 invoices
   - Click "Download Selected"

3. **Trigger a failure** (optional - for testing):
   - Use the test script to simulate a failure for this batch

4. **Check User 1's inbox**:
   - User 1 should see failure notifications

5. **Login as User 2**:
   ```
   Email: user2@imploy.com.au
   ```

6. **Check User 2's inbox**:
   - User 2 should NOT see User 1's failure notifications
   - Inbox should be empty (for this batch)

### Manual API Test

Test the notification targeting:

```bash
# Should notify user ID 42 only
curl -X POST http://127.0.0.1:8000/api/queue/notification/job-failed \
  -H "Content-Type: application/json" \
  -d '{
    "jobType": "pdf",
    "invoiceNumber": "TEST-001",
    "errorMessage": "Test for user 42",
    "batchId": "test-batch",
    "tenantId": "app_imploy_com_au",
    "userId": 42
  }'

# Check: Only user 42's inbox should have this notification
```

```bash
# Should notify all admins (no userId provided)
curl -X POST http://127.0.0.1:8000/api/queue/notification/job-failed \
  -H "Content-Type: application/json" \
  -d '{
    "jobType": "pdf",
    "invoiceNumber": "TEST-002",
    "errorMessage": "Test fallback - no user",
    "batchId": "test-batch-2",
    "tenantId": "app_imploy_com_au"
  }'

# Check: All admin users' inboxes should have this notification
```

## Troubleshooting

### User Not Getting Notifications

**Check 1**: Verify userId is being passed from Laravel
```bash
# Check Laravel logs
tail -f storage/logs/laravel.log | grep "Bulk download initiated"
# Should show: "user_id" => 42
```

**Check 2**: Verify userId is stored in Redis
```bash
# From PDF service container
docker exec -it pdf-redis redis-cli
> HGETALL batch:app_imploy_com_au:batch-20251010-143022-abc123
# Should show: userId: "42"
```

**Check 3**: Verify notification payload includes userId
```bash
# Check PDF service logs
docker logs pdf-worker-1 | grep "Failure notification sent"
# Should show: (userId: 42)
```

**Check 4**: Verify Laravel found the user
```bash
# Check Laravel logs
tail -f storage/logs/laravel.log | grep "Notifying initiating user"
# Should show: user_id: 42, email: user@example.com
```

**Check 5**: Verify notification was created in database
```sql
SELECT * FROM dashboard_notifications 
WHERE type = 'queue_job_failed' 
AND user_id = 42
ORDER BY created_at DESC 
LIMIT 5;
```

### Wrong User Getting Notifications

This could happen if:
1. **userId not being captured**: Check `Auth::id()` in controller
2. **userId not being passed**: Check HTTP requests between Laravel and PDF service
3. **userId type mismatch**: Ensure it's an integer, not a string

## Fallback Behavior

The system gracefully falls back to admin notification when:
- `userId` is `null` or not provided
- User with `userId` not found in database
- System-generated jobs (not initiated by a specific user)
- Legacy batches created before this feature

This ensures **no notifications are lost** while still providing user-specific targeting when possible.

---

**Implementation Date**: October 10, 2025  
**Feature**: User-Specific Queue Failure Notifications  
**Status**: ✅ Complete and Ready for Testing

