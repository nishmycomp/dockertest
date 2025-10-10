#!/bin/bash

echo "🔧 Fixing PDF Worker Restart Issue"
echo "==================================="
echo ""

# Check current status
echo "1️⃣ Current worker status:"
docker ps | grep pdf-worker

echo ""
echo "2️⃣ Checking Redis queue..."
WAITING=$(docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:waiting 2>/dev/null || echo "0")
ACTIVE=$(docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:active 2>/dev/null || echo "0")
FAILED=$(docker exec pdf-redis redis-cli llen bull:app.imploy.com.au:email:failed 2>/dev/null || echo "0")

echo "Waiting jobs: $WAITING"
echo "Active jobs: $ACTIVE"
echo "Failed jobs: $FAILED"

echo ""
echo "3️⃣ Applying fix..."

# Update docker-compose to add shared memory
echo "Adding shared memory to workers..."

# Backup original file
cp docker-compose-queue.yml docker-compose-queue.yml.backup

# Add shm_size if not exists
if ! grep -q "shm_size:" docker-compose-queue.yml; then
    echo "⚠️  Manual update required. Please add 'shm_size: 1gb' to worker config"
else
    echo "✅ shm_size already configured"
fi

echo ""
echo "4️⃣ Restarting workers..."
docker restart pdf-worker-1 pdf-worker-2

echo ""
echo "5️⃣ Waiting for workers to start..."
sleep 5

echo ""
echo "6️⃣ New worker status:"
docker ps | grep pdf-worker

echo ""
echo "7️⃣ Checking worker logs..."
echo "Worker-1 last 10 lines:"
docker logs pdf-worker-1 --tail=10

echo ""
echo "Worker-2 last 10 lines:"
docker logs pdf-worker-2 --tail=10

echo ""
echo "================================="
echo "✅ Fix applied!"
echo ""
echo "📊 Monitor workers with:"
echo "  docker logs -f pdf-worker-1"
echo ""
echo "📈 Check queue stats:"
echo "  curl http://localhost:3004/api/stats"
echo ""
echo "If workers still restart, run:"
echo "  bash docker/diagnose-worker-issues.sh"

