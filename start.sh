#!/bin/bash

# Start script for Invoice PDF Service
# Usage: ./start.sh [environment]
#   production  - Start in production mode
#   development - Start in development mode (default)

set -e

ENVIRONMENT=${1:-development}

echo "========================================="
echo "Starting Invoice PDF Service"
echo "Environment: $ENVIRONMENT"
echo "========================================="

case $ENVIRONMENT in
    production|prod)
        echo "Starting production services..."
        docker-compose up -d
        ;;
    development|dev)
        echo "Starting development services..."
        docker-compose up
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        echo "Usage: ./start.sh [production|development]"
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo "Service Started!"
echo "========================================="
echo "Health check: http://localhost:3000/health"
echo "API Endpoint: http://localhost:3000/generate-invoice-pdf"
echo ""
echo "View logs:"
echo "  docker-compose logs -f pdf-service"
echo ""
echo "Stop service:"
echo "  docker-compose down"
echo "========================================="

