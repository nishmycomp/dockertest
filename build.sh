#!/bin/bash

# Build script for Invoice PDF Service
# Usage: ./build.sh [options]
#   -t, --tag TAG        Specify image tag (default: latest)
#   -p, --push          Push to registry after build
#   -h, --help          Show this help message

set -e

# Default values
TAG="latest"
PUSH=false
IMAGE_NAME="invoice-pdf-service"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -p|--push)
            PUSH=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./build.sh [options]"
            echo "Options:"
            echo "  -t, --tag TAG     Specify image tag (default: latest)"
            echo "  -p, --push       Push to registry after build"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "========================================="
echo "Building Invoice PDF Service"
echo "========================================="
echo "Image: $IMAGE_NAME:$TAG"
echo "Push to registry: $PUSH"
echo "========================================="

# Build the image
echo "Building Docker image..."
cd pdf-service
docker build -t $IMAGE_NAME:$TAG .

# Tag as latest if not already
if [ "$TAG" != "latest" ]; then
    echo "Tagging as latest..."
    docker tag $IMAGE_NAME:$TAG $IMAGE_NAME:latest
fi

echo "Build completed successfully!"
docker images | grep $IMAGE_NAME

# Push if requested
if [ "$PUSH" = true ]; then
    echo "Pushing to registry..."
    docker push $IMAGE_NAME:$TAG
    if [ "$TAG" != "latest" ]; then
        docker push $IMAGE_NAME:latest
    fi
    echo "Push completed!"
fi

echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "To run the service:"
echo "  docker run -d -p 3000:3000 $IMAGE_NAME:$TAG"
echo ""
echo "Or use docker-compose:"
echo "  docker-compose up -d"
echo "========================================="

