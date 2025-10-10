# AlmaLinux Deployment Commands - Quick Reference

## 🚀 Deploy User-Specific Notifications

### Option 1: One-Command Deployment (Recommended)

```bash
cd /root
chmod +x deploy-user-notifications.sh
./deploy-user-notifications.sh
```

This script will:
- ✅ Check/create `.env` file with LARAVEL_URL
- ✅ Stop existing containers
- ✅ Rebuild images with new code
- ✅ Start all services
- ✅ Test the notification system
- ✅ Show you the status

---

### Option 2: Manual Step-by-Step

If you prefer to do it manually:

```bash
# 1. Navigate to docker directory
cd /root

# 2. Update .env file with Laravel URL
nano pdf-service/.env
# Add this line:
# LARAVEL_URL=http://127.0.0.1:8000
# (or your actual Laravel URL)

# 3. Stop existing services
docker compose -f docker-compose-queue.yml down

# 4. Rebuild with new code (no cache)
docker compose -f docker-compose-queue.yml build --no-cache

# 5. Start services
docker compose -f docker-compose-queue.yml up -d

# 6. Check status
docker compose -f docker-compose-queue.yml ps

# 7. View logs
docker compose -f docker-compose-queue.yml logs -f
```

---

## 📋 Environment Variables

Make sure your `pdf-service/.env` includes:

```env
# Laravel Integration (REQUIRED for notifications)
LARAVEL_URL=http://127.0.0.1:8000
LARAVEL_API_TOKEN=your-token-here
```

**Important URLs:**
- If Laravel is on **same server**: `http://127.0.0.1:8000` or `http://localhost:8000`
- If Laravel is on **different server**: `http://144.6.128.64:8000` (your Laravel server IP)
- If Laravel has **domain**: `https://app.imploy.com.au`

---

## 🧪 Test After Deployment

### Test 1: Check Services are Running
```bash
docker compose -f docker-compose-queue.yml ps
```

Expected: All containers should be "Up" and healthy.

### Test 2: Test Notification Endpoint
```bash
curl -X POST http://127.0.0.1:8000/api/queue/notification/job-failed \
  -H "Content-Type: application/json" \
  -d '{
    "jobType": "pdf",
    "invoiceNumber": "TEST-001",
    "errorMessage": "Test notification",
    "batchId": "test-batch",
    "tenantId": "app_imploy_com_au",
    "userId": 1
  }'
```

Expected: `{"success":true,"message":"Notification sent to user(s)","notified_count":1}`

### Test 3: Trigger Real Job with User Tracking
```bash
# From your Laravel app, run as a logged-in user:
# 1. Go to: http://your-laravel-url/admin/platform-invoices
# 2. Select invoices
# 3. Click "Download Selected"
# 4. Check YOUR inbox for any failure notifications
# 5. Other users should NOT see your notifications
```

---

## 🔍 Verify User Tracking is Working

### Check 1: Verify userId in Batch
```bash
# Access Redis
docker exec -it pdf-redis redis-cli

# List all batches for today
KEYS batch:app_imploy_com_au:batch-$(date +%Y%m%d)*

# Check a specific batch (replace with actual batch ID)
HGETALL batch:app_imploy_com_au:batch-20251010-143022-abc123
```

Expected output should include: `userId` field with the user ID.

### Check 2: Check Logs for User Tracking
```bash
# Check if userId is being logged
docker logs pdf-worker-1 | grep userId

# Check notification logs
docker logs pdf-worker-1 | grep "Failure notification sent"
```

Expected: Should show `(userId: X)` in the logs.

### Check 3: Verify in Laravel Database
```bash
# SSH into your Laravel server
# Run this SQL query:
mysql -u your_user -p your_database << EOF
SELECT 
    id,
    user_id,
    title,
    message,
    created_at
FROM dashboard_notifications 
WHERE type = 'queue_job_failed' 
ORDER BY created_at DESC 
LIMIT 5;
EOF
```

Expected: Notifications should be assigned to specific `user_id`, not all admins.

---

## 🛠️ Troubleshooting

### Problem: Notifications going to all admins instead of specific user

**Solution 1**: Check if userId is in the batch
```bash
docker exec -it pdf-redis redis-cli
HGETALL batch:app_imploy_com_au:your-batch-id
# Should show: userId field
```

**Solution 2**: Check Laravel logs
```bash
tail -f /path/to/laravel/storage/logs/laravel.log | grep "Bulk download initiated"
# Should show: "user_id" => 42
```

**Solution 3**: Verify .env has LARAVEL_URL
```bash
cat pdf-service/.env | grep LARAVEL_URL
```

### Problem: Cannot reach Laravel from PDF service

**Solution**: Update LARAVEL_URL based on your setup

If both are on the same server:
```bash
nano pdf-service/.env
# Set: LARAVEL_URL=http://127.0.0.1:8000
```

If Laravel is in Docker:
```bash
# Set: LARAVEL_URL=http://host.docker.internal:8000
# OR use the Laravel container service name
```

If Laravel is on different server:
```bash
# Set: LARAVEL_URL=http://LARAVEL_SERVER_IP:8000
```

Then restart:
```bash
docker compose -f docker-compose-queue.yml restart
```

### Problem: Services not starting

```bash
# Check logs for errors
docker compose -f docker-compose-queue.yml logs

# Check specific service
docker logs pdf-service-1

# Rebuild from scratch
docker compose -f docker-compose-queue.yml down -v
docker compose -f docker-compose-queue.yml build --no-cache
docker compose -f docker-compose-queue.yml up -d
```

---

## 📊 Monitoring Commands

```bash
# View all logs in real-time
docker compose -f docker-compose-queue.yml logs -f

# View specific service logs
docker logs -f pdf-worker-1
docker logs -f pdf-worker-2
docker logs -f queue-monitor

# Check container status
docker compose -f docker-compose-queue.yml ps

# Check resource usage
docker stats pdf-worker-1 pdf-worker-2 pdf-redis

# Access queue monitor web UI
# Open in browser: http://YOUR_SERVER_IP:3004
```

---

## 🔄 Common Operations

### Restart Services
```bash
docker compose -f docker-compose-queue.yml restart
```

### Stop Services
```bash
docker compose -f docker-compose-queue.yml down
```

### Update and Redeploy
```bash
# Pull latest code (if using git)
git pull

# Redeploy
./deploy-user-notifications.sh
```

### Clean Everything and Start Fresh
```bash
docker compose -f docker-compose-queue.yml down -v
docker system prune -a
./deploy-user-notifications.sh
```

---

## 📞 Quick Support Checklist

If something isn't working, gather this info:

1. **Service Status**:
   ```bash
   docker compose -f docker-compose-queue.yml ps
   ```

2. **Recent Logs**:
   ```bash
   docker compose -f docker-compose-queue.yml logs --tail=50
   ```

3. **Environment Config**:
   ```bash
   cat pdf-service/.env | grep -E "(LARAVEL_URL|REDIS_HOST|NODE_ENV)"
   ```

4. **Laravel Reachability**:
   ```bash
   curl -I http://127.0.0.1:8000
   ```

5. **Notification Test**:
   ```bash
   curl -X POST http://127.0.0.1:8000/api/queue/notification/job-failed \
     -H "Content-Type: application/json" \
     -d '{"jobType":"pdf","invoiceNumber":"TEST","errorMessage":"Test","tenantId":"app_imploy_com_au","userId":1}'
   ```

---

**Last Updated**: October 10, 2025  
**Feature**: User-Specific Queue Failure Notifications  
**Deployment Script**: `deploy-user-notifications.sh`

