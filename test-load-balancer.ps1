# Load Balancer Stress Test - 300 PDF Requests
# PowerShell version for Windows

Write-Host "🚀 Load Balancer Stress Test - 300 PDF Requests" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# Check if load balancer is responding
Write-Host "🔍 Checking load balancer health..." -ForegroundColor Yellow
try {
    $healthResponse = Invoke-WebRequest -Uri "http://localhost:8080/health" -UseBasicParsing -TimeoutSec 5
    if ($healthResponse.StatusCode -eq 200) {
        Write-Host "✓ Load balancer is healthy" -ForegroundColor Green
    } else {
        Write-Host "✗ Load balancer returned status: $($healthResponse.StatusCode)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "✗ Load balancer is not responding: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure the PDF services are running on your VM!" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "📊 Starting 300 PDF generation requests..." -ForegroundColor Blue
Write-Host "This will test load distribution across 3 PDF service instances" -ForegroundColor Blue
Write-Host ""

# Create test invoice data
$invoiceData = @{
    invoice = @{
        invoice_number = "TEST-001"
        total_amount = 100
        client_name = "Test Client"
        line_items = @(
            @{
                description = "Test Service"
                quantity = 1
                rate = 100
                amount = 100
            }
        )
    }
} | ConvertTo-Json -Depth 10

# Counters
$successCount = 0
$errorCount = 0
$totalRequests = 300

Write-Host "📊 Sending $totalRequests requests to load balancer..." -ForegroundColor Blue
Write-Host "⏱️  This may take a few minutes..." -ForegroundColor Blue
Write-Host ""

# Start time
$startTime = Get-Date

# Send requests in batches
for ($i = 1; $i -le $totalRequests; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/generate-invoice-pdf" `
            -Method POST `
            -ContentType "application/json" `
            -Body $invoiceData `
            -UseBasicParsing `
            -TimeoutSec 30
        
        if ($response.StatusCode -eq 200) {
            $successCount++
            Write-Host "✓ Request $i`: Success" -ForegroundColor Green
        } else {
            $errorCount++
            Write-Host "✗ Request $i`: Failed (HTTP $($response.StatusCode))" -ForegroundColor Red
        }
    } catch {
        $errorCount++
        Write-Host "✗ Request $i`: Error - $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Progress update every 50 requests
    if ($i % 50 -eq 0) {
        Write-Host "📈 Processed $i/$totalRequests requests..." -ForegroundColor Yellow
    }
    
    # Small delay to avoid overwhelming
    Start-Sleep -Milliseconds 100
}

# End time
$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

Write-Host ""
Write-Host "📊 Test Results:" -ForegroundColor Blue
Write-Host "==============" -ForegroundColor Blue
Write-Host "📊 Total requests: $totalRequests" -ForegroundColor White
Write-Host "✅ Successful: $successCount" -ForegroundColor Green
Write-Host "❌ Failed: $errorCount" -ForegroundColor Red
Write-Host "⏱️  Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor White
Write-Host "📈 Average: $([math]::Round($totalRequests / $duration, 2)) requests/second" -ForegroundColor White

Write-Host ""
Write-Host "🔍 Check service distribution on your VM:" -ForegroundColor Blue
Write-Host "=========================================" -ForegroundColor Blue
Write-Host "Run these commands on your VM to see load distribution:" -ForegroundColor White
Write-Host ""
Write-Host "docker logs pdf-service-1 | grep -c 'Received PDF generation request'" -ForegroundColor Cyan
Write-Host "docker logs pdf-service-2 | grep -c 'Received PDF generation request'" -ForegroundColor Cyan
Write-Host "docker logs pdf-service-3 | grep -c 'Received PDF generation request'" -ForegroundColor Cyan
Write-Host ""

Write-Host "📊 Monitor in real-time on your VM:" -ForegroundColor Blue
Write-Host "===================================" -ForegroundColor Blue
Write-Host "docker compose -f docker-compose-localhost.yml logs -f" -ForegroundColor Cyan
Write-Host ""

Write-Host "🚀 Ready to test! Run this script and watch the magic happen!" -ForegroundColor Green

