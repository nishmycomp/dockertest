# User Identification System for PDF Service

## Overview

The PDF service now includes user identification to ensure notifications are sent to the correct user who initiated the operation. This system uses `appId` and `uniqueName` from the tenant database to identify users across the multi-tenant architecture.

## How It Works

### 1. User Identification Flow

```
Laravel App → PDF Service → Queue Manager → Notification System
     ↓              ↓              ↓              ↓
  appId/uniqueName → Batch Data → Failure → User Lookup
```

### 2. Data Flow

1. **Laravel Request**: When a user initiates a PDF/email operation, Laravel retrieves `appId` and `uniqueName` from the `extras` table
2. **PDF Service**: The service stores this information in the batch data
3. **Queue Processing**: When jobs fail, the queue manager includes this information in failure notifications
4. **User Lookup**: Laravel uses `appId` and `uniqueName` to find the correct user in the `app_root` database
5. **Notification**: The specific user receives the notification

### 3. Database Architecture

- **`app_root`**: Contains user login details and tenant mapping (`user_roots` table)
- **`app_{app_id}_{unique_name}`**: Individual tenant databases with user data
- **Mapping**: `user_roots` table links `app_id` + `unique_name` to `user_id`

## Implementation Details

### PDF Service Updates

#### Queue Manager (`queue-manager.js`)
- `startBatch()` now accepts `appId` and `uniqueName` parameters
- Batch data stores user identification information
- `sendFailureNotification()` includes app information in payload

#### Server (`server.js`)
- `/queue/batch/start` endpoint accepts `appId` and `uniqueName`
- Passes this information to the queue manager

### Laravel Updates

#### PdfService (`app/Services/PdfService.php`)
- `getTenantAppInfo()` retrieves `appId` and `uniqueName` from `extras` table
- Batch start requests include app information
- Both `generateBatchPdfs()` and `sendBulkInvoiceEmails()` updated

#### Notification Controller (`app/Http/Controllers/Api/QueueNotificationController.php`)
- Accepts `appId` and `uniqueName` in failure notifications
- Uses app mapping to find correct user in `app_root` database
- Falls back to `userId` if app mapping fails
- Final fallback to admin users

## User Lookup Logic

```php
// 1. Try app mapping (most specific)
if (appId && uniqueName) {
    $userMapping = DB::connection('mysql')
        ->table('user_roots')
        ->where('app_id', $appId)
        ->where('unique_name', $uniqueName)
        ->first();
    
    if ($userMapping) {
        $user = User::find($userMapping->user_id);
    }
}

// 2. Fallback to userId
if (!$user && $userId) {
    $user = User::find($userId);
}

// 3. Final fallback to admin users
if (!$user) {
    $users = User::where('user_type_id', 1)
        ->orWhere('email', 'LIKE', '%@imploy.com.au')
        ->get();
}
```

## Benefits

1. **Accurate Notifications**: Users receive notifications for their own operations
2. **Multi-Tenant Support**: Works across different tenant databases
3. **Fallback System**: Multiple levels of user identification
4. **Audit Trail**: Complete tracking of who initiated what operation

## Deployment

Run the deployment script to apply all updates:

```bash
./docker/deploy-user-identification.sh
```

## Monitoring

Check the logs to see user identification in action:

```bash
# PDF Service logs
docker logs -f pdf-service-1

# Worker logs
docker logs -f pdf-worker-1

# Laravel logs
tail -f storage/logs/laravel.log
```

## Testing

1. Create an invoice as a specific user
2. Trigger a PDF generation or email sending
3. Check that notifications are sent to the correct user
4. Verify the notification data includes app information

## Troubleshooting

### Common Issues

1. **Missing appId/uniqueName**: Check that `extras` table has these fields
2. **User not found**: Verify `user_roots` table mapping
3. **Database connection**: Ensure `app_root` database is accessible
4. **Fallback notifications**: Check that admin users receive notifications

### Debug Information

The system logs detailed information about user identification:

```
Log::info("Notifying user by app mapping", [
    'app_id' => $appId, 
    'unique_name' => $uniqueName,
    'user_id' => $userId, 
    'email' => $email
]);
```

## Future Enhancements

1. **User Preferences**: Allow users to configure notification preferences
2. **Notification Channels**: Support email, SMS, and in-app notifications
3. **Batch Notifications**: Group related notifications
4. **User Analytics**: Track notification engagement
