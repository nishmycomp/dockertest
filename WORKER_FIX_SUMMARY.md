# Worker Restart Issue - Fix Summary

## Changes Made

### Modified: `docker/docker-compose-queue.yml`

**For both `pdf-worker-1` and `pdf-worker-2`:**

#### 1. Added Shared Memory
```yaml
shm_size: '1gb'  # NEW - Required for Chromium/Puppeteer
```
**Why**: Chromium needs shared memory (`/dev/shm`) to run properly. Without this, it crashes frequently.

#### 2. Increased Memory Limits
```yaml
deploy:
  resources:
    limits:
      memory: 4G      # Changed from 2G
    reservations:
      memory: 1G      # Changed from 512M
```
**Why**: PDF generation with Puppeteer can use significant memory, especially when processing multiple jobs.

#### 3. Removed Code Volume Mount
```yaml
volumes:
  # - ./pdf-service:/app  # REMOVED
  - pdf_storage:/app/storage  # Kept only storage
```
**Why**: Mounting code as a volume can cause Node.js to crash when files change. Now code is baked into the image.

#### 4. Added Puppeteer Path
```yaml
environment:
  - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser  # NEW
```
**Why**: Ensures workers use the correct Chromium binary.

## What This Fixes

### Before:
```
✅ Worker processes 1 job
📡 Received SIGTERM
🛑 Worker stops
✅ Worker restarts
✅ Worker processes 1 job
📡 Received SIGTERM
🛑 Worker stops
[Cycle repeats]
```

### After:
```
✅ Worker processes job 1
✅ Worker processes job 2
✅ Worker processes job 3
✅ Worker processes job 4
[Continues indefinitely]
```

## Deployment Steps

### On Your Local Machine:

1. **Commit and push changes:**
```bash
git add docker/docker-compose-queue.yml
git add docker/deploy-worker-fix.sh
git add docker/diagnose-worker-issues.sh
git add docker/WORKER_TROUBLESHOOTING.md
git add docker/WORKER_FIX_SUMMARY.md
git commit -m "Fix worker restart issue - add shared memory and increase limits"
git push
```

### On AlmaLinux Server (62.72.57.236):

2. **Pull latest changes:**
```bash
ssh root@62.72.57.236
cd /root/docker
git pull
```

3. **Run deployment script:**
```bash
chmod +x deploy-worker-fix.sh
./deploy-worker-fix.sh
```

**OR manually:**
```bash
cd /root/docker
docker compose -f docker-compose-queue.yml down
docker compose -f docker-compose-queue.yml build --no-cache pdf-worker-1 pdf-worker-2
docker compose -f docker-compose-queue.yml up -d
```

4. **Verify workers are running:**
```bash
docker logs -f pdf-worker-1
```

You should see:
```
🚀 PDF Worker started: worker-1-xxxx
🔄 Worker is running and processing jobs...
✅ Browser initialized for PDF generation
📧 Sending email for tenant...
✅ Email sent successfully
📧 Sending email for tenant...
✅ Email sent successfully
[Continues without SIGTERM]
```

## Testing

### Send Test Emails:
```bash
# From Laravel app - send multiple invoices
# Workers should process all of them without restarting
```

### Monitor Queue:
```bash
# Check queue stats
curl http://localhost:3004/api/stats | python3 -m json.tool

# Check Redis directly
docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:waiting
docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:active
```

### Watch Workers:
```bash
# Watch both workers
docker logs -f pdf-worker-1 pdf-worker-2 2>&1 | grep "📧\|✅"
```

## Files Created/Modified

1. ✅ `docker/docker-compose-queue.yml` - **MODIFIED** - Main fix
2. ✅ `docker/deploy-worker-fix.sh` - **NEW** - Deployment script
3. ✅ `docker/diagnose-worker-issues.sh` - **NEW** - Diagnostic tool
4. ✅ `docker/WORKER_TROUBLESHOOTING.md` - **NEW** - Full guide
5. ✅ `docker/WORKER_FIX_SUMMARY.md` - **NEW** - This file
6. ✅ `docker/fix-worker-restart-issue.sh` - **NEW** - Quick fix
7. ✅ `docker/pdf-service/templates/invoice-template.hbs` - **MODIFIED** - Updated PDF template
8. ✅ `docker/pdf-service/email-service.js` - **MODIFIED** - Added formatNumber helper

## Expected Results

- ✅ Workers process jobs continuously without restarting
- ✅ No more SIGTERM signals after each job
- ✅ Queue drains properly
- ✅ Emails send successfully
- ✅ PDFs generate without crashes

## Rollback (If Needed)

If something goes wrong:

```bash
cd /root/docker
git checkout HEAD~1 docker/docker-compose-queue.yml
docker compose -f docker-compose-queue.yml down
docker compose -f docker-compose-queue.yml up -d
```

## Notes

- Workers no longer have live code reload (need rebuild for code changes)
- This is more stable for production
- Memory usage will be higher but within limits
- Chromium will be more stable with dedicated shared memory

## Support

If workers still restart:
1. Run `bash docker/diagnose-worker-issues.sh`
2. Check `docker/WORKER_TROUBLESHOOTING.md`
3. Review logs: `docker logs pdf-worker-1 --tail=100`

