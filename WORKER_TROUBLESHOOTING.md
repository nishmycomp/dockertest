# PDF Worker Troubleshooting Guide

## Issue: Worker-1 Stops Processing Jobs After One Job

### Symptoms
From your logs:
```
✅ Email job added to queue: 19, 20, 21, 22
✅ Worker processes job 19
📡 Received SIGTERM, shutting down gracefully...
🛑 Stopping worker...
✅ Worker restarts
✅ Worker processes job 20
📡 Received SIGTERM, shutting down gracefully...
```

### Root Causes

#### 1. Docker Volume Mount Issues
**Problem**: Using `- ./pdf-service:/app` in docker-compose can cause issues if files are modified while the container is running.

**Solution**: 
```yaml
# Option A: Remove volume mount for workers (rebuild required for code changes)
pdf-worker-1:
  volumes:
    # - ./pdf-service:/app  # REMOVE THIS
    - pdf_storage:/app/storage  # Keep only storage

# Option B: Use nodemon for auto-reload (development only)
command: ["npx", "nodemon", "worker.js"]
```

#### 2. Puppeteer Browser Crashes
**Problem**: Chromium might be crashing after processing each job.

**Check logs for**:
```
⚠️  Browser disconnected
Target closed
Protocol error
```

**Solution**: Add shared memory and proper flags in docker-compose:
```yaml
pdf-worker-1:
  shm_size: '1gb'  # Add this
  environment:
    - PUPPETEER_ARGS=--no-sandbox,--disable-setuid-sandbox,--disable-dev-shm-usage
```

#### 3. Memory Limits
**Problem**: Worker exceeds 2GB memory limit.

**Check**: Run diagnostic script
```bash
bash docker/diagnose-worker-issues.sh
```

**Solution**: Increase memory limit
```yaml
deploy:
  resources:
    limits:
      memory: 4G  # Increase from 2G
```

#### 4. Unhandled Promise Rejections
**Problem**: Email sending or PDF generation fails without proper error handling.

**Check worker.js logs** for:
```
💥 Unhandled Rejection
💥 Uncaught Exception
```

**Solution**: Already implemented in worker.js, but verify queue-manager.js handles errors properly.

#### 5. Bull Queue Configuration Issues
**Problem**: Queue not configured for continuous processing.

**Check Redis**:
```bash
docker exec pdf-redis redis-cli --scan --pattern "bull:*"
docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:waiting
```

### Quick Fix Commands

#### On AlmaLinux Server:

```bash
# 1. Check worker status
docker ps -a | grep pdf-worker

# 2. Check worker logs
docker logs pdf-worker-1 --tail=100
docker logs pdf-worker-2 --tail=100

# 3. Check resource usage
docker stats pdf-worker-1 --no-stream

# 4. Restart workers
docker restart pdf-worker-1 pdf-worker-2

# 5. Check queue in Redis
docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:waiting
docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:active
docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:failed

# 6. Check for stalled jobs
docker exec pdf-redis redis-cli keys "bull:app.imploy.com.au:email:stalled"

# 7. View queue stats
curl http://localhost:3004/api/stats | python3 -m json.tool
```

### Recommended Fix

**Update `docker/docker-compose-queue.yml`:**

```yaml
pdf-worker-1:
  build:
    context: ./pdf-service
    dockerfile: Dockerfile.simple
  container_name: pdf-worker-1
  command: ["node", "worker.js"]
  shm_size: '1gb'  # ADD THIS - Important for Chromium
  environment:
    - NODE_ENV=production
    - REDIS_HOST=redis
    - REDIS_PORT=6379
    - WORKER_ID=worker-1
    - LARAVEL_URL=${LARAVEL_URL:-http://127.0.0.1:8000}
    - LARAVEL_API_TOKEN=${LARAVEL_API_TOKEN}
    - PUPPETEER_ARGS=--no-sandbox,--disable-setuid-sandbox,--disable-dev-shm-usage
  volumes:
    # REMOVE CODE VOLUME - Only keep storage
    # - ./pdf-service:/app  # COMMENT OUT THIS LINE
    - pdf_storage:/app/storage
  depends_on:
    - redis
  restart: unless-stopped
  deploy:
    resources:
      limits:
        memory: 4G  # INCREASE from 2G
      reservations:
        memory: 1G  # INCREASE from 512M
```

**Then redeploy:**
```bash
cd /path/to/docker
docker compose -f docker-compose-queue.yml down
docker compose -f docker-compose-queue.yml build --no-cache pdf-worker-1 pdf-worker-2
docker compose -f docker-compose-queue.yml up -d
```

### Monitor Worker Health

```bash
# Watch logs in real-time
docker logs -f pdf-worker-1

# Watch all workers
docker logs -f pdf-worker-1 pdf-worker-2 2>&1 | grep "📧\|✅\|❌\|💥"

# Monitor queue
watch -n 5 'curl -s http://localhost:3004/api/stats | python3 -m json.tool'
```

### Check If Jobs Are Stuck

```bash
# SSH to server
ssh root@62.72.57.236

# Check waiting jobs
docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:waiting

# If jobs are stuck, try:
docker restart pdf-worker-1 pdf-worker-2

# Or flush failed/stalled jobs
docker exec pdf-redis redis-cli del "bull:app.imploy.com.au:email:failed"
docker exec pdf-redis redis-cli del "bull:app.imploy.com.au:email:stalled"
```

### Permanent Solution

For production, consider using **Supervisor** (already implemented):

```bash
cd /root/docker
docker compose -f docker-compose-queue-supervisor.yml down
docker compose -f docker-compose-queue-supervisor.yml build --no-cache
docker compose -f docker-compose-queue-supervisor.yml up -d
```

This runs all workers in a single container with Supervisor managing process restarts.

### Success Indicators

Worker is healthy when you see:
```
🚀 PDF Worker started: worker-1-xxxx
🔄 Worker is running and processing jobs...
✅ Browser initialized for PDF generation
📧 Sending email for tenant...
✅ Email sent successfully
```

**WITHOUT** seeing:
```
📡 Received SIGTERM
🛑 Stopping worker...
```

Unless you manually stopped it.

