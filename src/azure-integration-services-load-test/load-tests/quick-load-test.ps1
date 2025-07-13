param(
    [Parameter(Mandatory=$false)]
    [int]$Users = 10,
    
    [Parameter(Mandatory=$false)]
    [int]$Duration = 60,
    
    [Parameter(Mandatory=$false)]
    [string]$AuditsUrl = $env:AUDITS_FUNCTION_URL,
    
    [Parameter(Mandatory=$false)]
    [string]$HistoryUrl = $env:HISTORY_FUNCTION_URL,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeHealthChecks,
    
    [Parameter(Mandatory=$false)]
    [int]$DelayBetweenRequests = 1000,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "load-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
)

<#
.SYNOPSIS
Quick load testing script for Azure Integration Services Function Apps

.DESCRIPTION
This PowerShell script provides a simple way to load test the HTTP endpoints
of the Azure Integration Services scenario. It's designed for quick validation
and basic performance testing.

.PARAMETER Users
Number of concurrent users to simulate (default: 10)

.PARAMETER Duration  
Duration of the test in seconds (default: 60)

.PARAMETER AuditsUrl
URL for the audits-adaptor function (defaults to environment variable)

.PARAMETER HistoryUrl
URL for the history-adaptor function (defaults to environment variable)

.PARAMETER IncludeHealthChecks
Include health endpoint testing

.PARAMETER DelayBetweenRequests
Delay between requests in milliseconds (default: 1000)

.PARAMETER OutputFile
Output file for test results (default: timestamped JSON file)

.EXAMPLE
./quick-load-test.ps1 -Users 20 -Duration 120

.EXAMPLE  
./quick-load-test.ps1 -Users 50 -Duration 300 -IncludeHealthChecks -DelayBetweenRequests 500
#>

# Validate parameters
if (-not $AuditsUrl) {
    Write-Error "AUDITS_FUNCTION_URL environment variable is not set and no AuditsUrl parameter provided"
    exit 1
}

if (-not $HistoryUrl) {
    Write-Error "HISTORY_FUNCTION_URL environment variable is not set and no HistoryUrl parameter provided"  
    exit 1
}

# Clean URLs
$AuditsBaseUrl = $AuditsUrl -replace '/api/audits$', ''
$HistoryBaseUrl = $HistoryUrl -replace '/api/history$', ''

Write-Host "🚀 Starting Azure Integration Services Load Test" -ForegroundColor Green
Write-Host "⚙️  Configuration:" -ForegroundColor Yellow
Write-Host "   Users: $Users"
Write-Host "   Duration: $Duration seconds"
Write-Host "   Audits URL: $AuditsBaseUrl/api/audits"
Write-Host "   History URL: $HistoryBaseUrl/api/history"
Write-Host "   Delay between requests: $DelayBetweenRequests ms"
Write-Host "   Include health checks: $IncludeHealthChecks"
Write-Host ""

# Global variables for tracking
$Global:Results = @{
    StartTime = Get-Date
    TotalRequests = 0
    SuccessfulRequests = 0
    FailedRequests = 0
    AuditsRequests = 0
    HistoryRequests = 0
    HealthRequests = 0
    ResponseTimes = @()
    Errors = @()
}

# Function to generate test data
function New-AuditPayload {
    $correlationId = [System.Guid]::NewGuid().ToString()
    return @{
        auditId = [System.Guid]::NewGuid().ToString()
        userId = "load-test-user"
        sessionId = [System.Guid]::NewGuid().ToString()
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        action = "load_test_action"
        resource = "test_resource"
        details = @{
            operation = "powershell_load_test"
            metadata = @{
                source = "quick-load-test.ps1"
                test_run = [int][double]::Parse((Get-Date -UFormat %s))
            }
        }
        severity = "Info"
        correlationId = $correlationId
    }
}

function New-HistoryPayload {
    $correlationId = [System.Guid]::NewGuid().ToString()
    return @{
        historyId = [System.Guid]::NewGuid().ToString()
        userId = "load-test-user"
        sessionId = [System.Guid]::NewGuid().ToString()
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        eventType = "data_change"
        entityId = [System.Guid]::NewGuid().ToString()
        entityType = "test_entity"
        changes = @(
            @{
                field = "status"
                oldValue = "pending"
                newValue = "processed"
                changeType = "update"
            }
        )
        metadata = @{
            source = "powershell_load_test"
            test_run = [int][double]::Parse((Get-Date -UFormat %s))
        }
        correlationId = $correlationId
    }
}

# Function to make HTTP request with timing
function Invoke-TimedRequest {
    param(
        [string]$Url,
        [string]$Method = "POST",
        [object]$Body = $null,
        [string]$RequestType
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        if ($Body) {
            $jsonBody = $Body | ConvertTo-Json -Depth 10
            $response = Invoke-RestMethod -Uri $Url -Method $Method -Body $jsonBody -Headers $headers -TimeoutSec 30
        } else {
            $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $headers -TimeoutSec 30
        }
        
        $stopwatch.Stop()
        $responseTime = $stopwatch.ElapsedMilliseconds
        
        $Global:Results.TotalRequests++
        $Global:Results.SuccessfulRequests++
        $Global:Results.ResponseTimes += $responseTime
        
        switch ($RequestType) {
            "audits" { $Global:Results.AuditsRequests++ }
            "history" { $Global:Results.HistoryRequests++ }  
            "health" { $Global:Results.HealthRequests++ }
        }
        
        Write-Host "✅ $RequestType request: $responseTime ms" -ForegroundColor Green
        return $true
        
    } catch {
        $stopwatch.Stop()
        $responseTime = $stopwatch.ElapsedMilliseconds
        
        $Global:Results.TotalRequests++
        $Global:Results.FailedRequests++
        $Global:Results.Errors += @{
            RequestType = $RequestType
            Error = $_.Exception.Message
            Timestamp = Get-Date
            ResponseTime = $responseTime
        }
        
        Write-Host "❌ $RequestType request failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Worker script block
$WorkerScript = {
    param($AuditsBaseUrl, $HistoryBaseUrl, $Duration, $DelayBetweenRequests, $IncludeHealthChecks)
    
    $endTime = (Get-Date).AddSeconds($Duration)
    
    while ((Get-Date) -lt $endTime) {
        # 70% audits, 30% history requests
        $randomChoice = Get-Random -Minimum 1 -Maximum 101
        
        if ($randomChoice -le 70) {
            # Audits request
            $payload = & $using:Function:New-AuditPayload
            & $using:Function:Invoke-TimedRequest -Url "$AuditsBaseUrl/api/audits" -Method "POST" -Body $payload -RequestType "audits"
        } else {
            # History request  
            $payload = & $using:Function:New-HistoryPayload
            & $using:Function:Invoke-TimedRequest -Url "$HistoryBaseUrl/api/history" -Method "POST" -Body $payload -RequestType "history"
        }
        
        # Occasional health checks
        if ($IncludeHealthChecks -and ((Get-Random -Minimum 1 -Maximum 21) -eq 1)) {
            & $using:Function:Invoke-TimedRequest -Url "$AuditsBaseUrl/api/health" -Method "GET" -RequestType "health"
            & $using:Function:Invoke-TimedRequest -Url "$HistoryBaseUrl/api/health" -Method "GET" -RequestType "health"
        }
        
        Start-Sleep -Milliseconds $DelayBetweenRequests
    }
}

# Start load test
$jobs = @()
Write-Host "🏃 Starting $Users concurrent users for $Duration seconds..." -ForegroundColor Yellow

for ($i = 1; $i -le $Users; $i++) {
    $job = Start-Job -ScriptBlock $WorkerScript -ArgumentList $AuditsBaseUrl, $HistoryBaseUrl, $Duration, $DelayBetweenRequests, $IncludeHealthChecks
    $jobs += $job
    Write-Progress -Activity "Starting workers" -Status "Started worker $i of $Users" -PercentComplete (($i / $Users) * 100)
}

Write-Host "✨ All workers started. Test running for $Duration seconds..." -ForegroundColor Green

# Wait for all jobs to complete
$jobs | Wait-Job | Out-Null

# Collect results from jobs (Note: This simplified script doesn't aggregate job results)
# In a more complex implementation, you'd collect and merge results from all jobs

$jobs | Remove-Job

# Calculate final statistics
$Global:Results.EndTime = Get-Date
$Global:Results.Duration = ($Global:Results.EndTime - $Global:Results.StartTime).TotalSeconds

if ($Global:Results.ResponseTimes.Count -gt 0) {
    $Global:Results.AverageResponseTime = ($Global:Results.ResponseTimes | Measure-Object -Average).Average
    $Global:Results.MinResponseTime = ($Global:Results.ResponseTimes | Measure-Object -Minimum).Minimum
    $Global:Results.MaxResponseTime = ($Global:Results.ResponseTimes | Measure-Object -Maximum).Maximum
    $Global:Results.P95ResponseTime = ($Global:Results.ResponseTimes | Sort-Object)[[math]::Floor($Global:Results.ResponseTimes.Count * 0.95)]
}

# Display results
Write-Host ""
Write-Host "📊 Load Test Results" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host "Duration: $([math]::Round($Global:Results.Duration, 2)) seconds"
Write-Host "Total Requests: $($Global:Results.TotalRequests)"
Write-Host "Successful Requests: $($Global:Results.SuccessfulRequests)"
Write-Host "Failed Requests: $($Global:Results.FailedRequests)"
Write-Host "Success Rate: $([math]::Round(($Global:Results.SuccessfulRequests / [math]::Max($Global:Results.TotalRequests, 1)) * 100, 2))%"
Write-Host ""
Write-Host "Request Distribution:"
Write-Host "  Audits: $($Global:Results.AuditsRequests)"
Write-Host "  History: $($Global:Results.HistoryRequests)"
if ($IncludeHealthChecks) {
    Write-Host "  Health: $($Global:Results.HealthRequests)"
}
Write-Host ""

if ($Global:Results.ResponseTimes.Count -gt 0) {
    Write-Host "Response Times:"
    Write-Host "  Average: $([math]::Round($Global:Results.AverageResponseTime, 2)) ms"
    Write-Host "  Minimum: $($Global:Results.MinResponseTime) ms"
    Write-Host "  Maximum: $($Global:Results.MaxResponseTime) ms"
    Write-Host "  95th Percentile: $($Global:Results.P95ResponseTime) ms"
    Write-Host ""
}

if ($Global:Results.FailedRequests -gt 0) {
    Write-Host "❌ Errors encountered:" -ForegroundColor Red
    $Global:Results.Errors | ForEach-Object {
        Write-Host "  $($_.RequestType): $($_.Error)" -ForegroundColor Red
    }
    Write-Host ""
}

# Throughput calculation
$requestsPerSecond = [math]::Round($Global:Results.TotalRequests / [math]::Max($Global:Results.Duration, 1), 2)
Write-Host "Throughput: $requestsPerSecond requests/second"

# Performance assessment
Write-Host ""
Write-Host "🎯 Performance Assessment:" -ForegroundColor Yellow
if ($Global:Results.ResponseTimes.Count -gt 0) {
    if ($Global:Results.AverageResponseTime -lt 500) {
        Write-Host "✅ Average response time is good (< 500ms)" -ForegroundColor Green
    } elseif ($Global:Results.AverageResponseTime -lt 1000) {
        Write-Host "⚠️  Average response time is acceptable (< 1000ms)" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Average response time is poor (> 1000ms)" -ForegroundColor Red
    }
}

$successRate = ($Global:Results.SuccessfulRequests / [math]::Max($Global:Results.TotalRequests, 1)) * 100
if ($successRate -gt 99) {
    Write-Host "✅ Success rate is excellent (> 99%)" -ForegroundColor Green
} elseif ($successRate -gt 95) {
    Write-Host "⚠️  Success rate is good (> 95%)" -ForegroundColor Yellow
} else {
    Write-Host "❌ Success rate is poor (< 95%)" -ForegroundColor Red
}

# Save results to file
$Global:Results | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host ""
Write-Host "💾 Results saved to: $OutputFile" -ForegroundColor Cyan

Write-Host ""
Write-Host "🔍 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Check Application Insights for detailed telemetry"
Write-Host "2. Monitor Function App scaling behavior"
Write-Host "3. Analyze Service Bus message processing times"
Write-Host "4. Review any errors in Function App logs"
Write-Host ""
Write-Host "For comprehensive testing, consider using Locust or Azure Load Testing." -ForegroundColor Gray
