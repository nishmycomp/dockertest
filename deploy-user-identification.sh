#!/bin/bash

# Deploy user identification updates to PDF service
# This script updates the PDF service to include appId and uniqueName for user identification

echo "🚀 Deploying user identification updates to PDF service..."

# Stop existing services
echo "📦 Stopping existing PDF services..."
docker compose -f docker-compose-queue.yml down

# Build new images with updated code
echo "🔨 Building updated PDF service images..."
docker compose -f docker-compose-queue.yml build --no-cache pdf-service-1 pdf-service-2 pdf-worker-1 pdf-worker-2

# Start services with updated code
echo "🚀 Starting updated PDF services..."
docker compose -f docker-compose-queue.yml up -d

# Wait for services to be ready
echo "⏳ Waiting for services to initialize..."
sleep 10

# Test the services
echo "🧪 Testing PDF service health..."
curl -s http://localhost:8080/health || echo "❌ Health check failed"

echo "✅ User identification updates deployed successfully!"
echo ""
echo "📋 What was updated:"
echo "  • PDF service now includes appId and uniqueName in batch tracking"
echo "  • Queue manager stores and retrieves app information"
echo "  • Laravel notification system uses app mapping to find correct users"
echo "  • Notifications are sent to the specific user who initiated the operation"
echo ""
echo "🔍 To monitor the system:"
echo "  docker logs -f pdf-worker-1"
echo "  docker logs -f pdf-service-1"
echo ""
echo "📊 Queue monitor: http://localhost:8080/monitor"
