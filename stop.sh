#!/bin/bash

# Stop script for Invoice PDF Service

set -e

echo "========================================="
echo "Stopping Invoice PDF Service"
echo "========================================="

docker-compose down

echo ""
echo "Service stopped successfully!"
echo ""
echo "To remove volumes as well:"
echo "  docker-compose down -v"
echo ""
echo "To restart:"
echo "  ./start.sh"
echo "========================================="

