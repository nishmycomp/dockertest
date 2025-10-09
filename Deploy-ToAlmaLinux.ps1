#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy PDF Service to AlmaLinux server

.DESCRIPTION
    This script automates the deployment of the PDF generation service to an AlmaLinux server.
    It handles file transfer, Docker setup, and service configuration.

.PARAMETER Host
    SSH hostname or IP address of the AlmaLinux server

.PARAMETER User
    SSH username for authentication

.PARAMETER Port
    SSH port number (default: 22)

.PARAMETER Path
    Deployment path on the server (default: /opt/pdf-service)

.PARAMETER SkipDockerCheck
    Skip Docker installation verification

.EXAMPLE
    .\Deploy-ToAlmaLinux.ps1 -Host 192.168.1.100 -User root

.EXAMPLE
    .\Deploy-ToAlmaLinux.ps1 -Host server.com -User deploy -Port 2222 -Path /home/deploy/pdf-service

.NOTES
    Requires: SSH client (OpenSSH) or PuTTY/pscp
    Version: 1.0.0
    Author: PDF Service Team
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="SSH hostname or IP address")]
    [string]$Host,
    
    [Parameter(Mandatory=$true, HelpMessage="SSH username")]
    [string]$User,
    
    [Parameter(Mandatory=$false, HelpMessage="SSH port")]
    [int]$Port = 22,
    
    [Parameter(Mandatory=$false, HelpMessage="Deployment path on server")]
    [string]$Path = "/opt/pdf-service",
    
    [Parameter(Mandatory=$false, HelpMessage="Skip Docker installation check")]
    [switch]$SkipDockerCheck
)

# Helper functions
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Blue
}

# Start deployment
Write-Header "PDF Service Deployment to AlmaLinux"

Write-Info "Target Server: $User@${Host}:$Port"
Write-Info "Deployment Path: $Path"
Write-Host ""

# Check if pdf-service directory exists
if (-not (Test-Path "./pdf-service")) {
    Write-Error "pdf-service directory not found in current directory"
    Write-Info "Please run this script from the 'docker' directory"
    exit 1
}

# Check for SSH client
Write-Header "Checking Prerequisites"

$sshCommand = Get-Command ssh -ErrorAction SilentlyContinue
if (-not $sshCommand) {
    Write-Error "SSH client not found"
    Write-Info "Please install OpenSSH client:"
    Write-Host "  Settings > Apps > Optional Features > Add a feature > OpenSSH Client"
    exit 1
}
Write-Success "SSH client found: $($sshCommand.Source)"

# Step 1: Test SSH connection
Write-Header "Step 1: Testing SSH Connection"

try {
    $result = ssh -p $Port -o ConnectTimeout=10 "$User@$Host" "echo 'SSH connection successful'" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "SSH connection established"
    } else {
        throw "Connection failed"
    }
} catch {
    Write-Error "Failed to connect to server"
    Write-Info "Please verify:"
    Write-Host "  - Host: $Host"
    Write-Host "  - User: $User"
    Write-Host "  - Port: $Port"
    exit 1
}

# Step 2: Check/Install Docker
if (-not $SkipDockerCheck) {
    Write-Header "Step 2: Checking Docker Installation"
    
    $dockerCheck = ssh -p $Port "$User@$Host" "command -v docker || echo ''" 2>$null
    
    if ([string]::IsNullOrWhiteSpace($dockerCheck)) {
        Write-Warning "Docker not found. Installing Docker..."
        
        $installScript = @'
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
'@
        
        ssh -p $Port "$User@$Host" $installScript
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker installed successfully"
        } else {
            Write-Error "Failed to install Docker"
            exit 1
        }
    } else {
        Write-Success "Docker is already installed"
        $version = ssh -p $Port "$User@$Host" "docker --version"
        Write-Host "  $version"
    }
} else {
    Write-Warning "Skipping Docker installation check"
}

# Step 3: Create deployment directory
Write-Header "Step 3: Creating Deployment Directory"

ssh -p $Port "$User@$Host" "sudo mkdir -p $Path && sudo chown ${User}:${User} $Path"
if ($LASTEXITCODE -eq 0) {
    Write-Success "Created directory: $Path"
} else {
    Write-Error "Failed to create directory"
    exit 1
}

# Step 4: Copy files to server
Write-Header "Step 4: Copying Files to Server"

Write-Info "Uploading pdf-service files..."

# Use SCP to copy files
scp -P $Port -r ./pdf-service/* "$User@${Host}:$Path/"

if ($LASTEXITCODE -eq 0) {
    Write-Success "Files uploaded successfully"
} else {
    Write-Error "Failed to upload files"
    exit 1
}

# Step 5: Configure environment
Write-Header "Step 5: Configuring Environment"

Write-Info "Setting up .env file for production..."

$configScript = @"
cd $Path

# Backup existing .env if present
if [ -f .env ]; then
    cp .env .env.backup.`$(date +%Y%m%d_%H%M%S)
    echo "Backed up existing .env file"
fi

# Update .env for production
sed -i 's/NODE_ENV=.*/NODE_ENV=production/' .env
sed -i 's|PUPPETEER_EXECUTABLE_PATH=.*|PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser|' .env
sed -i 's/# PUPPETEER_EXECUTABLE_PATH=/PUPPETEER_EXECUTABLE_PATH=/' .env

echo ""
echo "Current .env configuration:"
grep -v "LARAVEL_API_TOKEN" .env || true
"@

ssh -p $Port "$User@$Host" $configScript
Write-Success "Environment configured for production"

# Step 6: Build Docker image
Write-Header "Step 6: Building Docker Image"

Write-Info "Building PDF service Docker image (this may take a few minutes)..."

ssh -p $Port "$User@$Host" "cd $Path && docker build -t pdf-service:latest ."

if ($LASTEXITCODE -eq 0) {
    Write-Success "Docker image built successfully"
} else {
    Write-Error "Failed to build Docker image"
    exit 1
}

# Step 7: Stop existing container
Write-Header "Step 7: Stopping Existing Container"

$containerExists = ssh -p $Port "$User@$Host" "docker ps -a -q -f name=pdf-service" 2>$null

if (-not [string]::IsNullOrWhiteSpace($containerExists)) {
    Write-Info "Stopping and removing existing container..."
    ssh -p $Port "$User@$Host" "docker stop pdf-service && docker rm pdf-service"
    Write-Success "Existing container removed"
} else {
    Write-Info "No existing container found"
}

# Step 8: Start new container
Write-Header "Step 8: Starting PDF Service Container"

$runScript = @"
cd $Path

docker run -d \
    --name pdf-service \
    --restart unless-stopped \
    -p 3001:3001 \
    --env-file .env \
    -v $Path/logs:/app/logs \
    pdf-service:latest
"@

ssh -p $Port "$User@$Host" $runScript

if ($LASTEXITCODE -eq 0) {
    Write-Success "PDF service container started"
} else {
    Write-Error "Failed to start container"
    exit 1
}

# Step 9: Verify deployment
Write-Header "Step 9: Verifying Deployment"

Write-Info "Waiting for service to start..."
Start-Sleep -Seconds 5

# Check container status
$containerStatus = ssh -p $Port "$User@$Host" "docker ps -f name=pdf-service --format '{{.Status}}'" 2>$null

if (-not [string]::IsNullOrWhiteSpace($containerStatus)) {
    Write-Success "Container is running: $containerStatus"
} else {
    Write-Error "Container is not running"
    Write-Info "Checking logs..."
    ssh -p $Port "$User@$Host" "docker logs --tail 50 pdf-service"
    exit 1
}

# Test health endpoint
Write-Info "Testing health endpoint..."
$healthCheck = ssh -p $Port "$User@$Host" "curl -s http://localhost:3001/health || echo 'FAILED'"

if ($healthCheck -like "*healthy*") {
    Write-Success "Health check passed: $healthCheck"
} else {
    Write-Warning "Health check failed or service not ready yet"
    Write-Info "Service may need more time to initialize"
}

# Step 10: Configure firewall
Write-Header "Step 10: Firewall Configuration"

Write-Info "Checking firewall status..."

$firewallActive = ssh -p $Port "$User@$Host" "sudo systemctl is-active firewalld 2>/dev/null || echo 'inactive'"

if ($firewallActive -eq "active") {
    Write-Info "Firewalld is active. Opening port 3001..."
    ssh -p $Port "$User@$Host" @"
sudo firewall-cmd --permanent --add-port=3001/tcp
sudo firewall-cmd --reload
"@
    Write-Success "Port 3001 opened in firewall"
} else {
    Write-Info "Firewalld is not active - no firewall changes needed"
}

# Final summary
Write-Header "Deployment Summary"

Write-Success "PDF Service deployed successfully!"
Write-Host ""
Write-Info "Service Details:"
Write-Host "  • Container Name: pdf-service" -ForegroundColor Gray
Write-Host "  • Port: 3001" -ForegroundColor Gray
Write-Host "  • Status: Running" -ForegroundColor Gray
Write-Host "  • Location: $Path" -ForegroundColor Gray
Write-Host ""
Write-Info "Useful Commands:"
Write-Host "  • View logs:        ssh $User@$Host 'docker logs -f pdf-service'" -ForegroundColor Gray
Write-Host "  • Restart service:  ssh $User@$Host 'docker restart pdf-service'" -ForegroundColor Gray
Write-Host "  • Stop service:     ssh $User@$Host 'docker stop pdf-service'" -ForegroundColor Gray
Write-Host "  • Check status:     ssh $User@$Host 'docker ps -f name=pdf-service'" -ForegroundColor Gray
Write-Host "  • Health check:     curl http://${Host}:3001/health" -ForegroundColor Gray
Write-Host ""
Write-Info "Next Steps:"
Write-Host "  1. Update Laravel .env with PDF_SERVICE_URL=http://${Host}:3001" -ForegroundColor Gray
Write-Host "  2. Configure Nginx reverse proxy (recommended for production)" -ForegroundColor Gray
Write-Host "  3. Set up SSL/TLS certificate" -ForegroundColor Gray
Write-Host "  4. Monitor logs: docker logs -f pdf-service" -ForegroundColor Gray
Write-Host ""

Write-Header "Deployment Complete!"

exit 0

