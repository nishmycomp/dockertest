#!/bin/bash

echo "🚀 Deploying Worker Fix to AlmaLinux Server"
echo "============================================"
echo ""

# Configuration
PROJECT_DIR="/root/docker"

echo "1️⃣ Stopping current workers..."
docker compose -f ${PROJECT_DIR}/docker-compose-queue.yml stop pdf-worker-1 pdf-worker-2

echo ""
echo "2️⃣ Rebuilding worker containers with new configuration..."
docker compose -f ${PROJECT_DIR}/docker-compose-queue.yml build --no-cache pdf-worker-1 pdf-worker-2

echo ""
echo "3️⃣ Starting workers with fixes..."
docker compose -f ${PROJECT_DIR}/docker-compose-queue.yml up -d pdf-worker-1 pdf-worker-2

echo ""
echo "4️⃣ Waiting for workers to initialize..."
sleep 10

echo ""
echo "5️⃣ Checking worker status..."
docker ps | grep pdf-worker

echo ""
echo "6️⃣ Checking worker logs..."
echo "Worker-1:"
docker logs pdf-worker-1 --tail=20

echo ""
echo "Worker-2:"
docker logs pdf-worker-2 --tail=20

echo ""
echo "7️⃣ Checking Redis queue..."
WAITING=$(docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:waiting 2>/dev/null || echo "0")
ACTIVE=$(docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:active 2>/dev/null || echo "0")
FAILED=$(docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:failed 2>/dev/null || echo "0")

echo "Waiting jobs: $WAITING"
echo "Active jobs: $ACTIVE"
echo "Failed jobs: $FAILED"

echo ""
echo "============================================"
echo "✅ Deployment complete!"
echo ""
echo "Changes applied:"
echo "  • Added 1GB shared memory for Chromium"
echo "  • Increased memory limit from 2GB to 4GB"
echo "  • Removed code volume mount (more stable)"
echo "  • Added PUPPETEER_EXECUTABLE_PATH"
echo ""
echo "Monitor workers:"
echo "  docker logs -f pdf-worker-1"
echo ""
echo "Check queue stats:"
echo "  curl http://localhost:3004/api/stats | python3 -m json.tool"

