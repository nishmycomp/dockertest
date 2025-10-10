# Troubleshooting PDF Service Workers

## Quick Diagnosis

### Check Worker Status (AlmaLinux Server)

SSH into your server and run:

```bash
# Check all PDF service containers
docker ps -a | grep pdf

# Check worker logs specifically
docker logs pdf-worker-1 --tail=50
docker logs pdf-worker-2 --tail=50

# Check if workers are running
docker ps | grep worker
```

## Common Issues & Solutions

### 1. Worker Stopped or Crashed

**Symptoms:**
- Worker container shows as "Exited" instead of "Up"
- No jobs being processed
- Queue dashboard shows jobs stuck in "waiting"

**Check:**
```bash
docker ps -a | grep worker
```

**Fix:**
```bash
# Restart specific worker
docker restart pdf-worker-1

# Or restart all workers
docker restart pdf-worker-1 pdf-worker-2
```

### 2. Worker Running But Not Processing Jobs

**Symptoms:**
- Worker container is "Up" but jobs aren't being processed
- No error logs

**Check:**
```bash
# View worker logs in real-time
docker logs -f pdf-worker-1

# Check Redis connection
docker exec pdf-worker-1 redis-cli -h redis ping
```

**Common Causes:**
- Redis connection lost
- Worker crashed silently
- Bull queue stuck

**Fix:**
```bash
# Full restart of queue system
cd /path/to/docker
docker-compose -f docker-compose-queue.yml restart
```

### 3. Out of Memory (OOM) Killed

**Symptoms:**
- Worker randomly stops
- Docker logs show "OOMKilled"
- System running slow

**Check:**
```bash
# Check container resource usage
docker stats

# Check worker exit code
docker inspect pdf-worker-1 | grep -A 5 State
```

**Fix:**
```bash
# Increase memory limits in docker-compose-queue.yml
# Change:
#   memory: 2G
# To:
#   memory: 4G

# Then restart
docker-compose -f docker-compose-queue.yml down
docker-compose -f docker-compose-queue.yml up -d
```

### 4. Chromium/Puppeteer Crashes

**Symptoms:**
- Worker logs show "Target closed" errors
- "Protocol error" messages
- PDF generation fails intermittently

**Check:**
```bash
docker logs pdf-worker-1 | grep -i "error\|crash\|target"
```

**Fix:**
```bash
# Increase shared memory
# Edit docker-compose-queue.yml:
shm_size: '2gb'

# Restart workers
docker-compose -f docker-compose-queue.yml restart pdf-worker-1 pdf-worker-2
```

### 5. Worker Can't Connect to Redis

**Symptoms:**
- Worker logs show "ECONNREFUSED" or "Redis connection error"
- Queue not processing

**Check:**
```bash
# Check if Redis is running
docker ps | grep redis

# Test Redis connection
docker exec -it pdf-redis redis-cli ping
# Should return: PONG
```

**Fix:**
```bash
# Restart Redis
docker restart pdf-redis

# Wait a few seconds, then restart workers
sleep 5
docker restart pdf-worker-1 pdf-worker-2
```

## Monitoring Commands

### Real-time Worker Monitoring

```bash
# Watch all PDF service containers
watch -n 2 'docker ps | grep pdf'

# Monitor worker logs live (in separate terminals)
docker logs -f pdf-worker-1
docker logs -f pdf-worker-2

# Check queue stats
curl http://localhost:3004/api/stats
```

### Check Queue Health

```bash
# Access Redis CLI
docker exec -it pdf-redis redis-cli

# In Redis CLI:
KEYS bull:*          # See all queues
LLEN bull:pdf:waiting   # Check waiting jobs
LLEN bull:pdf:active    # Check active jobs
LLEN bull:pdf:completed # Check completed jobs
LLEN bull:pdf:failed    # Check failed jobs
```

### View Queue Monitor Dashboard

```bash
# Open in browser
http://your-server-ip:3004

# Or if using Nginx:
http://your-server-ip:8080/queue
```

## Complete Reset (Nuclear Option)

If workers are completely stuck and nothing works:

```bash
# Stop everything
docker-compose -f docker-compose-queue.yml down

# Remove old data (⚠️ This deletes queue data!)
docker volume rm docker_redis_data
docker volume rm docker_pdf_storage

# Rebuild and restart
docker-compose -f docker-compose-queue.yml build --no-cache
docker-compose -f docker-compose-queue.yml up -d

# Check logs
docker-compose -f docker-compose-queue.yml logs -f
```

## Supervisor-Managed Workers

If using the Supervisor setup (all in one container):

```bash
# Check Supervisor status
docker exec pdf-service-supervisor supervisorctl status

# Restart specific worker
docker exec pdf-service-supervisor supervisorctl restart pdf-worker-1

# Restart all processes
docker exec pdf-service-supervisor supervisorctl restart all

# View worker logs
docker exec pdf-service-supervisor tail -f /var/log/supervisor/pdf-worker-1_stdout.log
```

## Debugging Specific Issues

### Worker 1 Stopped But Worker 2 Running

This usually means:
1. Worker 1 crashed
2. Out of memory for that specific worker
3. Process terminated by OS

**Solution:**
```bash
# Check why it stopped
docker logs pdf-worker-1 --tail=100

# Look for:
# - "OOM" (out of memory)
# - "SIGKILL" (killed by OS)
# - JavaScript errors
# - "Target closed" (Chromium crash)

# Restart
docker restart pdf-worker-1
```

### Both Workers Stopped

This usually means:
1. Redis crashed
2. Network issue
3. All workers out of memory
4. Docker daemon issue

**Solution:**
```bash
# Check Redis first
docker ps | grep redis

# If Redis is down
docker restart pdf-redis
sleep 5

# Restart workers
docker restart pdf-worker-1 pdf-worker-2
```

## Prevention

### Set Up Health Checks

Add to `docker-compose-queue.yml`:

```yaml
pdf-worker-1:
  # ... existing config
  healthcheck:
    test: ["CMD", "node", "-e", "process.exit(0)"]
    interval: 30s
    timeout: 10s
    retries: 3
  restart: unless-stopped
```

### Set Up Alerts

Monitor and get notified:

```bash
# Create monitoring script: /usr/local/bin/monitor-workers.sh
#!/bin/bash
while true; do
    if ! docker ps | grep -q "pdf-worker-1.*Up"; then
        echo "Worker 1 is down! Restarting..." | mail -s "PDF Worker Alert" admin@example.com
        docker restart pdf-worker-1
    fi
    if ! docker ps | grep -q "pdf-worker-2.*Up"; then
        echo "Worker 2 is down! Restarting..." | mail -s "PDF Worker Alert" admin@example.com
        docker restart pdf-worker-2
    fi
    sleep 60
done
```

### Resource Monitoring

```bash
# Add to crontab to log resource usage
*/5 * * * * docker stats --no-stream | grep pdf >> /var/log/pdf-workers-stats.log
```

## Quick Restart Script

Save as `restart-workers.sh`:

```bash
#!/bin/bash
echo "🔄 Restarting PDF Workers..."

# Stop workers
docker stop pdf-worker-1 pdf-worker-2

# Wait a moment
sleep 2

# Start workers
docker start pdf-worker-1 pdf-worker-2

# Check status
sleep 3
docker ps | grep worker

echo "✅ Workers restarted. Check logs with:"
echo "   docker logs -f pdf-worker-1"
echo "   docker logs -f pdf-worker-2"
```

Make it executable:
```bash
chmod +x restart-workers.sh
./restart-workers.sh
```

## Log Analysis

Find common errors:

```bash
# Check for errors in last hour
docker logs pdf-worker-1 --since 1h | grep -i error

# Count error types
docker logs pdf-worker-1 | grep -i error | sort | uniq -c

# Find crashes
docker logs pdf-worker-1 | grep -i "crash\|killed\|segfault"

# Check for memory issues
docker logs pdf-worker-1 | grep -i "memory\|heap\|oom"
```

## Contact Points

If issue persists:
1. Check queue monitor: `http://server:3004`
2. Check main server logs: `docker logs pdf-service-1`
3. Check Redis: `docker exec pdf-redis redis-cli ping`
4. Full system restart: `docker-compose -f docker-compose-queue.yml restart`

