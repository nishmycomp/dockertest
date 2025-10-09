#!/bin/bash

##############################################################################
# PDF Service - AlmaLinux Deployment Script
# 
# This script automates the deployment of the PDF service to AlmaLinux
#
# Usage:
#   ./deploy-to-almalinux.sh [options]
#
# Options:
#   --host <hostname>       SSH hostname or IP
#   --user <username>       SSH username
#   --port <port>           SSH port (default: 22)
#   --path <path>           Deployment path on server (default: /opt/pdf-service)
#   --skip-docker-check     Skip Docker installation check
#   --help                  Show this help message
##############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SSH_PORT=22
DEPLOY_PATH="/opt/pdf-service"
SKIP_DOCKER_CHECK=false

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to print section header
print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

# Function to show usage
show_usage() {
    cat << EOF
PDF Service - AlmaLinux Deployment Script

Usage:
    $0 --host <hostname> --user <username> [options]

Required:
    --host <hostname>       SSH hostname or IP address
    --user <username>       SSH username

Optional:
    --port <port>           SSH port (default: 22)
    --path <path>           Deployment path (default: /opt/pdf-service)
    --skip-docker-check     Skip Docker installation verification
    --help                  Show this help message

Examples:
    $0 --host 192.168.1.100 --user root
    $0 --host server.com --user deploy --port 2222 --path /home/deploy/pdf-service

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            SSH_HOST="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --port)
            SSH_PORT="$2"
            shift 2
            ;;
        --path)
            DEPLOY_PATH="$2"
            shift 2
            ;;
        --skip-docker-check)
            SKIP_DOCKER_CHECK=true
            shift
            ;;
        --help)
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$SSH_HOST" ] || [ -z "$SSH_USER" ]; then
    print_error "Missing required arguments"
    show_usage
fi

# Check if pdf-service directory exists
if [ ! -d "./pdf-service" ]; then
    print_error "pdf-service directory not found in current directory"
    print_info "Please run this script from the 'docker' directory"
    exit 1
fi

print_header "PDF Service Deployment to AlmaLinux"

print_info "Target Server: $SSH_USER@$SSH_HOST:$SSH_PORT"
print_info "Deployment Path: $DEPLOY_PATH"
echo ""

# Step 1: Test SSH connection
print_header "Step 1: Testing SSH Connection"

if ssh -p "$SSH_PORT" -o ConnectTimeout=10 "$SSH_USER@$SSH_HOST" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    print_success "SSH connection established"
else
    print_error "Failed to connect to server"
    print_info "Please verify:"
    echo "  - Host: $SSH_HOST"
    echo "  - User: $SSH_USER"
    echo "  - Port: $SSH_PORT"
    exit 1
fi

# Step 2: Check/Install Docker
if [ "$SKIP_DOCKER_CHECK" = false ]; then
    print_header "Step 2: Checking Docker Installation"
    
    DOCKER_CHECK=$(ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "command -v docker" || echo "")
    
    if [ -z "$DOCKER_CHECK" ]; then
        print_warning "Docker not found. Installing Docker..."
        
        ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" << 'EOF'
            # Remove old Docker versions
            sudo yum remove -y docker docker-client docker-client-latest docker-common \
                docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            
            # Install dependencies
            sudo yum install -y yum-utils device-mapper-persistent-data lvm2
            
            # Add Docker repository
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            
            # Start Docker
            sudo systemctl start docker
            sudo systemctl enable docker
            
            # Verify installation
            docker --version
EOF
        
        if [ $? -eq 0 ]; then
            print_success "Docker installed successfully"
        else
            print_error "Failed to install Docker"
            exit 1
        fi
    else
        print_success "Docker is already installed"
        ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "docker --version"
    fi
else
    print_warning "Skipping Docker installation check"
fi

# Step 3: Create deployment directory
print_header "Step 3: Creating Deployment Directory"

ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "sudo mkdir -p $DEPLOY_PATH && sudo chown $SSH_USER:$SSH_USER $DEPLOY_PATH"
print_success "Created directory: $DEPLOY_PATH"

# Step 4: Copy files to server
print_header "Step 4: Copying Files to Server"

print_info "Uploading pdf-service files..."
rsync -avz -e "ssh -p $SSH_PORT" --progress \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude '*.log' \
    ./pdf-service/ "$SSH_USER@$SSH_HOST:$DEPLOY_PATH/"

if [ $? -eq 0 ]; then
    print_success "Files uploaded successfully"
else
    print_error "Failed to upload files"
    exit 1
fi

# Step 5: Configure environment
print_header "Step 5: Configuring Environment"

print_info "Setting up .env file for production..."

ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" << EOF
    cd $DEPLOY_PATH
    
    # Backup existing .env if present
    if [ -f .env ]; then
        cp .env .env.backup.\$(date +%Y%m%d_%H%M%S)
        echo "Backed up existing .env file"
    fi
    
    # Update .env for production
    sed -i 's/NODE_ENV=.*/NODE_ENV=production/' .env
    sed -i 's|PUPPETEER_EXECUTABLE_PATH=.*|PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser|' .env
    
    # Uncomment PUPPETEER_EXECUTABLE_PATH if commented
    sed -i 's/# PUPPETEER_EXECUTABLE_PATH=/PUPPETEER_EXECUTABLE_PATH=/' .env
    
    echo ""
    echo "Current .env configuration:"
    grep -v "LARAVEL_API_TOKEN" .env || true
EOF

print_success "Environment configured for production"

# Step 6: Build Docker image
print_header "Step 6: Building Docker Image"

print_info "Building PDF service Docker image (this may take a few minutes)..."

ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" << EOF
    cd $DEPLOY_PATH
    docker build -t pdf-service:latest .
EOF

if [ $? -eq 0 ]; then
    print_success "Docker image built successfully"
else
    print_error "Failed to build Docker image"
    exit 1
fi

# Step 7: Stop existing container (if running)
print_header "Step 7: Stopping Existing Container"

CONTAINER_EXISTS=$(ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "docker ps -a -q -f name=pdf-service" || echo "")

if [ -n "$CONTAINER_EXISTS" ]; then
    print_info "Stopping and removing existing container..."
    ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "docker stop pdf-service && docker rm pdf-service"
    print_success "Existing container removed"
else
    print_info "No existing container found"
fi

# Step 8: Start new container
print_header "Step 8: Starting PDF Service Container"

ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" << EOF
    cd $DEPLOY_PATH
    
    docker run -d \
        --name pdf-service \
        --restart unless-stopped \
        -p 3001:3001 \
        --env-file .env \
        -v $DEPLOY_PATH/logs:/app/logs \
        pdf-service:latest
EOF

if [ $? -eq 0 ]; then
    print_success "PDF service container started"
else
    print_error "Failed to start container"
    exit 1
fi

# Step 9: Verify deployment
print_header "Step 9: Verifying Deployment"

print_info "Waiting for service to start..."
sleep 5

# Check container status
CONTAINER_STATUS=$(ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "docker ps -f name=pdf-service --format '{{.Status}}'" || echo "")

if [ -n "$CONTAINER_STATUS" ]; then
    print_success "Container is running: $CONTAINER_STATUS"
else
    print_error "Container is not running"
    print_info "Checking logs..."
    ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "docker logs --tail 50 pdf-service"
    exit 1
fi

# Test health endpoint
print_info "Testing health endpoint..."
HEALTH_CHECK=$(ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "curl -s http://localhost:3001/health || echo 'FAILED'")

if [[ $HEALTH_CHECK == *"healthy"* ]]; then
    print_success "Health check passed: $HEALTH_CHECK"
else
    print_warning "Health check failed or service not ready yet"
    print_info "Service may need more time to initialize"
fi

# Step 10: Configure firewall (optional)
print_header "Step 10: Firewall Configuration"

print_info "Checking firewall status..."

FIREWALL_ACTIVE=$(ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "sudo systemctl is-active firewalld 2>/dev/null || echo 'inactive'")

if [ "$FIREWALL_ACTIVE" = "active" ]; then
    print_info "Firewalld is active. Opening port 3001..."
    ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" << EOF
        sudo firewall-cmd --permanent --add-port=3001/tcp
        sudo firewall-cmd --reload
EOF
    print_success "Port 3001 opened in firewall"
else
    print_info "Firewalld is not active - no firewall changes needed"
fi

# Final summary
print_header "Deployment Summary"

print_success "PDF Service deployed successfully!"
echo ""
print_info "Service Details:"
echo "  • Container Name: pdf-service"
echo "  • Port: 3001"
echo "  • Status: Running"
echo "  • Location: $DEPLOY_PATH"
echo ""
print_info "Useful Commands:"
echo "  • View logs:        ssh $SSH_USER@$SSH_HOST 'docker logs -f pdf-service'"
echo "  • Restart service:  ssh $SSH_USER@$SSH_HOST 'docker restart pdf-service'"
echo "  • Stop service:     ssh $SSH_USER@$SSH_HOST 'docker stop pdf-service'"
echo "  • Check status:     ssh $SSH_USER@$SSH_HOST 'docker ps -f name=pdf-service'"
echo "  • Health check:     curl http://$SSH_HOST:3001/health"
echo ""
print_info "Next Steps:"
echo "  1. Update Laravel .env with PDF_SERVICE_URL=http://$SSH_HOST:3001"
echo "  2. Configure Nginx reverse proxy (recommended for production)"
echo "  3. Set up SSL/TLS certificate"
echo "  4. Monitor logs: docker logs -f pdf-service"
echo ""

print_header "Deployment Complete!"

exit 0

