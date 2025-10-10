# Supervisor Deployment Guide

This guide explains how to deploy the PDF service with Supervisor for uninterrupted queue processing.

## ✨ Features

### 1. **Graceful Error Handling**
- Failed PDF/email jobs **don't stop the batch**
- Each job is retried once (2 total attempts)
- Errors are logged to Redis for review
- Failed jobs are kept in the queue for debugging

### 2. **Supervisor Process Management**
- Auto-restart workers if they crash
- 2 worker processes for parallel processing
- Queue monitor runs alongside workers
- All processes managed in one container

### 3. **Error Notification System**
- Errors stored in Redis with timestamps
- API endpoint to retrieve failed jobs
- Includes invoice number, error message, recipient email
- Errors expire after 7 days

## 🚀 Deployment

### On AlmaLinux Server:

```bash
cd ~

# Pull latest code
git pull origin main  # or scp updated files

# Stop existing services
docker compose -f docker-compose-queue.yml down

# Build with Supervisor
docker compose -f docker-compose-queue-supervisor.yml build --no-cache

# Start services
docker compose -f docker-compose-queue-supervisor.yml up -d
```

### Configure SMTP (Required for Email):

```bash
cd ~/pdf-service
nano .env
```

Add SMTP credentials:
```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM="Imploy <noreply@imploy.com.au>"
```

## 📊 Monitoring

### Check Supervisor Status:
```bash
docker exec -it pdf-service-supervised supervisorctl status
```

Output:
```
pdf-worker-1    RUNNING   pid 10, uptime 0:01:23
pdf-worker-2    RUNNING   pid 11, uptime 0:01:23
queue-monitor   RUNNING   pid 12, uptime 0:01:23
```

### View Worker Logs:
```bash
# All logs
docker compose -f docker-compose-queue-supervisor.yml logs -f

# Specific worker
docker exec -it pdf-service-supervised tail -f /var/log/supervisor/pdf-worker-1.log

# Queue monitor
docker exec -it pdf-service-supervised tail -f /var/log/supervisor/queue-monitor.log
```

### View Queue Dashboard:
```
http://62.72.57.236:3004
```

### Get Recent Errors:
```bash
# All errors for tenant
curl http://62.72.57.236:3001/queue/errors/app_imploy_com_au

# Errors for specific batch
curl http://62.72.57.236:3001/queue/errors/app_imploy_com_au/batch-20251010-142033-C1Ag2Q

# Limit results
curl "http://62.72.57.236:3001/queue/errors/app_imploy_com_au?limit=10"
```

Response:
```json
{
  "success": true,
  "tenantId": "app_imploy_com_au",
  "batchId": "batch-...",
  "count": 2,
  "errors": [
    {
      "jobType": "email",
      "invoiceNumber": "INV-2025100001",
      "errorMessage": "No billing email found",
      "recipient": null,
      "timestamp": "2025-10-10T14:20:33.000Z",
      "batchId": "batch-20251010-142033-C1Ag2Q"
    }
  ]
}
```

## 🔧 Supervisor Commands

### Restart All Workers:
```bash
docker exec -it pdf-service-supervised supervisorctl restart all
```

### Restart Single Worker:
```bash
docker exec -it pdf-service-supervised supervisorctl restart pdf-worker-1
```

### Stop/Start:
```bash
docker exec -it pdf-service-supervised supervisorctl stop pdf-worker-1
docker exec -it pdf-service-supervised supervisorctl start pdf-worker-1
```

### Reload Configuration:
```bash
docker exec -it pdf-service-supervised supervisorctl reread
docker exec -it pdf-service-supervised supervisorctl update
```

## 📈 How It Works

### 1. **Batch Processing**
- Laravel sends 10 invoice emails
- Each job added to Redis queue
- Workers process jobs in parallel
- If job 3 fails, workers continue with job 4, 5, etc.

### 2. **Error Handling**
```
Job 1: ✅ Success (PDF + Email sent)
Job 2: ✅ Success
Job 3: ❌ Failed (No email address) → Logged to Redis, batch continues
Job 4: ✅ Success
Job 5: ❌ Failed (SMTP error) → Retry once, if fails again → Logged to Redis
...
Job 10: ✅ Success
```

### 3. **Error Recovery**
- Failed jobs stay in Redis "failed" queue
- View via queue dashboard
- Manually retry if needed
- Check error logs for details

## 🎯 Benefits

1. **Uninterrupted Processing**: One failed email doesn't stop other emails
2. **Auto-Recovery**: Workers restart automatically if they crash
3. **Visibility**: View all errors in one place
4. **Debugging**: Failed jobs kept for analysis
5. **Scalability**: Add more workers by editing supervisord.conf

## 🔍 Troubleshooting

### Workers Not Starting:
```bash
docker exec -it pdf-service-supervised cat /var/log/supervisor/supervisord.log
```

### Check Redis Connection:
```bash
docker exec -it pdf-redis redis-cli ping
```

### Test Email Configuration:
```bash
curl http://62.72.57.236:3001/email/verify/app_imploy_com_au
```

### View All Failed Jobs:
```bash
curl http://62.72.57.236:3001/queue/errors/app_imploy_com_au?limit=100
```

## 📝 Configuration

Edit `docker/pdf-service/supervisord.conf` to:
- Add more workers
- Adjust log levels
- Change restart policies
- Modify resource limits

Example - Add 3rd worker:
```ini
[program:pdf-worker-3]
command=node worker.js
directory=/app
environment=WORKER_ID="worker-3",...
autostart=true
autorestart=true
...
```

Then reload:
```bash
docker compose -f docker-compose-queue-supervisor.yml restart pdf-service
```

