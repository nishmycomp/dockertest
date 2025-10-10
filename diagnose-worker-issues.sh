#!/bin/bash

echo "🔍 Diagnosing PDF Worker Issues"
echo "================================"
echo ""

# Check if running
echo "1️⃣ Checking container status..."
docker ps -a | grep pdf-worker

echo ""
echo "2️⃣ Checking worker-1 resource usage..."
docker stats pdf-worker-1 --no-stream

echo ""
echo "3️⃣ Checking worker-1 restart count..."
docker inspect pdf-worker-1 | grep -A 3 "RestartCount"

echo ""
echo "4️⃣ Checking worker-1 exit code..."
docker inspect pdf-worker-1 | grep -A 10 "State"

echo ""
echo "5️⃣ Checking Redis connection..."
docker exec pdf-redis redis-cli ping

echo ""
echo "6️⃣ Checking queue stats..."
curl -s http://localhost:3004/api/stats | python3 -m json.tool

echo ""
echo "7️⃣ Last 50 lines of worker-1 logs..."
docker logs pdf-worker-1 --tail=50

echo ""
echo "8️⃣ Checking for OOM (Out of Memory) kills..."
dmesg | grep -i "killed process" | grep -i "pdf-worker" | tail -5

echo ""
echo "9️⃣ Checking Docker events for worker-1..."
docker events --since 30m --filter container=pdf-worker-1 --until 1s

echo ""
echo "🔟 Checking Bull queue health in Redis..."
docker exec pdf-redis redis-cli --scan --pattern "bull:app.imploy.com.au:*" | head -20

echo ""
echo "================================"
echo "✅ Diagnostics complete!"

