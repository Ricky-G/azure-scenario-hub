<#
.SYNOPSIS
    Generates realistic API traffic to Azure API Management for monitoring and dashboard testing.

.DESCRIPTION
    This script generates varied traffic patterns across multiple API endpoints to populate
    APIM monitoring dashboards with meaningful data. It simulates realistic user behavior
    including cache hits/misses, rate limiting, validation errors, and performance scenarios.

.PARAMETER ApimBaseUrl
    The base URL of your APIM instance (e.g., https://your-apim.azure-api.net)

.PARAMETER SubscriptionKey
    The APIM subscription key for API access

.PARAMETER Duration
    Test duration in minutes. Options: 'quick' (2 min), 'standard' (5 min), 'extended' (15 min), or custom number

.PARAMETER Concurrency
    Number of concurrent virtual users. Options: 'light' (5), 'moderate' (15), 'heavy' (30), or custom number

.PARAMETER ConfigPath
    Path to the configuration JSON file. Default: .\config.json

.PARAMETER ShowProgress
    Display real-time progress and statistics during the test

.EXAMPLE
    .\Start-ApimLoadTest.ps1 -ApimBaseUrl "https://my-apim.azure-api.net" -SubscriptionKey "abc123..." -Duration "standard" -Concurrency "moderate"

.EXAMPLE
    .\Start-ApimLoadTest.ps1 -ApimBaseUrl "https://my-apim.azure-api.net" -SubscriptionKey "abc123..." -Duration 10 -Concurrency 20 -ShowProgress

.NOTES
    Requires PowerShell 7.0 or later for parallel execution support
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApimBaseUrl,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionKey,
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ $_ -in @('quick', 'standard', 'extended') -or ($_ -is [int] -and $_ -gt 0) })]
    $Duration = 'standard',
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ $_ -in @('light', 'moderate', 'heavy') -or ($_ -is [int] -and $_ -gt 0) })]
    $Concurrency = 'moderate',
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json"),
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowProgress
)

#Requires -Version 7.0

# Color output functions
function Write-Header {
    param([string]$Message)
    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Blue
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Initialize
$ErrorActionPreference = 'Continue'
Clear-Host

Write-Header "APIM Load Test Generator"

# Load configuration
Write-Info "Loading configuration from: $ConfigPath"
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse configuration file: $_"
    exit 1
}

# Override config with parameters if provided
if ($ApimBaseUrl) {
    $config.apimBaseUrl = $ApimBaseUrl
}
if ($SubscriptionKey) {
    $config.subscriptionKey = $SubscriptionKey
}

# Validate required configuration
if (-not $config.apimBaseUrl -or $config.apimBaseUrl -eq "https://your-apim-instance.azure-api.net") {
    Write-Warning "APIM Base URL not configured!"
    $config.apimBaseUrl = Read-Host "Enter your APIM Base URL (e.g., https://my-apim.azure-api.net)"
}

if (-not $config.subscriptionKey -or $config.subscriptionKey -eq "your-subscription-key-here") {
    Write-Warning "Subscription Key not configured!"
    $config.subscriptionKey = Read-Host "Enter your APIM Subscription Key" -AsSecureString | ConvertFrom-SecureString -AsPlainText
}

# Resolve duration
if ($Duration -is [string]) {
    $durationMinutes = $config.testDuration.$Duration
    if (-not $durationMinutes) {
        Write-Error "Invalid duration preset: $Duration"
        exit 1
    }
}
else {
    $durationMinutes = [int]$Duration
}

# Resolve concurrency
if ($Concurrency -is [string]) {
    $concurrentUsers = $config.concurrency.$Concurrency
    if (-not $concurrentUsers) {
        Write-Error "Invalid concurrency preset: $Concurrency"
        exit 1
    }
}
else {
    $concurrentUsers = [int]$Concurrency
}

# Calculate test parameters
$testDurationSeconds = $durationMinutes * 60
$endTime = (Get-Date).AddSeconds($testDurationSeconds)

# Display test configuration
Write-Host "`n📊 Test Configuration" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  APIM URL:          $($config.apimBaseUrl)" -ForegroundColor White
Write-Host "  Duration:          $durationMinutes minutes" -ForegroundColor White
Write-Host "  Concurrent Users:  $concurrentUsers" -ForegroundColor White
Write-Host "  End Time:          $($endTime.ToString('HH:mm:ss'))" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"

# Statistics tracking
$script:stats = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$script:stats['totalRequests'] = 0
$script:stats['successfulRequests'] = 0
$script:stats['failedRequests'] = 0
$script:stats['cacheHits'] = 0
$script:stats['rateLimitErrors'] = 0
$script:stats['validationErrors'] = 0
$script:stats['startTime'] = Get-Date

# API call function
function Invoke-ApiCall {
    param(
        [string]$Url,
        [string]$Method,
        [object]$Body,
        [hashtable]$Headers,
        [string]$ApiName
    )
    
    try {
        $requestParams = @{
            Uri             = $Url
            Method          = $Method
            Headers         = $Headers
            TimeoutSec      = 30
            SkipHttpErrorCheck = $true
        }
        
        if ($Body -and $Method -eq 'POST') {
            $requestParams['Body'] = ($Body | ConvertTo-Json -Compress)
            $requestParams['ContentType'] = 'application/json'
        }
        
        $response = Invoke-WebRequest @requestParams
        
        # Track statistics
        $script:stats['totalRequests'] = [System.Threading.Interlocked]::Increment([ref]$script:stats['totalRequests'])
        
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            $script:stats['successfulRequests'] = [System.Threading.Interlocked]::Increment([ref]$script:stats['successfulRequests'])
        }
        
        # Track cache hits
        if ($response.Headers -and $response.Headers['X-Cache-Status'] -eq 'Hit') {
            $script:stats['cacheHits'] = [System.Threading.Interlocked]::Increment([ref]$script:stats['cacheHits'])
        }
        
        return @{
            Success = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)
            StatusCode = $response.StatusCode
            ApiName = $ApiName
        }
    }
    catch {
        $script:stats['totalRequests'] = [System.Threading.Interlocked]::Increment([ref]$script:stats['totalRequests'])
        $script:stats['failedRequests'] = [System.Threading.Interlocked]::Increment([ref]$script:stats['failedRequests'])
        
        $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
        
        # Track specific error types
        if ($statusCode -eq 429) {
            $script:stats['rateLimitErrors'] = [System.Threading.Interlocked]::Increment([ref]$script:stats['rateLimitErrors'])
        }
        elseif ($statusCode -in @(400, 422)) {
            $script:stats['validationErrors'] = [System.Threading.Interlocked]::Increment([ref]$script:stats['validationErrors'])
        }
        
        return @{
            Success = $false
            StatusCode = $statusCode
            Error = $_.Exception.Message
            ApiName = $ApiName
        }
    }
}

# Progress display job
$progressJob = $null
if ($ShowProgress) {
    $progressJob = Start-Job -ScriptBlock {
        param($stats, $endTime)
        
        while ((Get-Date) -lt $endTime) {
            Start-Sleep -Seconds 5
            $elapsed = ((Get-Date) - $stats['startTime']).TotalSeconds
            $remaining = ($endTime - (Get-Date)).TotalSeconds
            
            if ($remaining -gt 0) {
                $rps = [math]::Round($stats['totalRequests'] / $elapsed, 2)
                $successRate = if ($stats['totalRequests'] -gt 0) { 
                    [math]::Round(($stats['successfulRequests'] / $stats['totalRequests']) * 100, 2) 
                } else { 0 }
                
                Write-Host "`r[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline
                Write-Host "Requests: $($stats['totalRequests']) " -NoNewline -ForegroundColor Cyan
                Write-Host "| RPS: $rps " -NoNewline -ForegroundColor Green
                Write-Host "| Success: $successRate% " -NoNewline -ForegroundColor Yellow
                Write-Host "| Remaining: $([math]::Round($remaining))s" -NoNewline -ForegroundColor Magenta
            }
        }
    } -ArgumentList $script:stats, $endTime
}

Write-Success "Starting load test with $concurrentUsers concurrent users..."
Write-Info "Test will run until: $($endTime.ToString('HH:mm:ss'))`n"

# Main load generation loop - ForEach-Object -Parallel blocks until all complete
1..$concurrentUsers | ForEach-Object -Parallel {
    $localConfig = $using:config
    $localEndTime = $using:endTime
    $localStats = $using:stats
    
    # Import the Invoke-ApiCall function in the parallel scope
    function Invoke-ApiCall {
        param(
            [string]$Url,
            [string]$Method,
            [object]$Body,
            [hashtable]$Headers,
            [string]$ApiName
        )
        
        try {
            $requestParams = @{
                Uri                = $Url
                Method             = $Method
                Headers            = $Headers
                TimeoutSec         = 30
                SkipHttpErrorCheck = $true
            }
            
            if ($Body -and $Method -eq 'POST') {
                $requestParams['Body'] = ($Body | ConvertTo-Json -Compress)
                $requestParams['ContentType'] = 'application/json'
            }
            
            $response = Invoke-WebRequest @requestParams
            
            $localStats['totalRequests'] = [System.Threading.Interlocked]::Increment([ref]$localStats['totalRequests'])
            
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                $localStats['successfulRequests'] = [System.Threading.Interlocked]::Increment([ref]$localStats['successfulRequests'])
            }
            
            if ($response.Headers -and $response.Headers['X-Cache-Status'] -eq 'Hit') {
                $localStats['cacheHits'] = [System.Threading.Interlocked]::Increment([ref]$localStats['cacheHits'])
            }
            
            return @{ Success = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300); StatusCode = $response.StatusCode; ApiName = $ApiName }
        }
        catch {
            $localStats['totalRequests'] = [System.Threading.Interlocked]::Increment([ref]$localStats['totalRequests'])
            $localStats['failedRequests'] = [System.Threading.Interlocked]::Increment([ref]$localStats['failedRequests'])
            
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
            
            if ($statusCode -eq 429) {
                $localStats['rateLimitErrors'] = [System.Threading.Interlocked]::Increment([ref]$localStats['rateLimitErrors'])
            }
            elseif ($statusCode -in @(400, 422)) {
                $localStats['validationErrors'] = [System.Threading.Interlocked]::Increment([ref]$localStats['validationErrors'])
            }
            
            return @{ Success = $false; StatusCode = $statusCode; Error = $_.Exception.Message; ApiName = $ApiName }
        }
    }
    
    $headers = @{
        'Ocp-Apim-Subscription-Key' = $localConfig.subscriptionKey
        'Content-Type' = 'application/json'
    }
    
    # Generate weighted random API selection
    $apiWeights = @()
    foreach ($apiKey in $localConfig.apis.PSObject.Properties.Name) {
        $apiWeights += @{
            Name   = $apiKey
            Weight = $localConfig.apis.$apiKey.weight
        }
    }
    
    while ((Get-Date) -lt $localEndTime) {
        # Select random API based on weights
        $totalWeight = ($apiWeights | Measure-Object -Property Weight -Sum).Sum
        $random = Get-Random -Minimum 0 -Maximum $totalWeight
        $cumulative = 0
        $selectedApi = $null
        
        foreach ($api in $apiWeights) {
            $cumulative += $api.Weight
            if ($random -lt $cumulative) {
                $selectedApi = $api.Name
                break
            }
        }
        
        if (-not $selectedApi) { continue }
        
        $apiConfig = $localConfig.apis.$selectedApi
        $url = $localConfig.apimBaseUrl
        
        # Execute API-specific logic
        switch ($selectedApi) {
            'weather' {
                $city = $apiConfig.cities | Get-Random
                $url += $apiConfig.path.Replace('{city}', $city)
                Invoke-ApiCall -Url $url -Method $apiConfig.method -Headers $headers -ApiName 'Weather'
            }
            'productSearch' {
                $query = $apiConfig.queries | Get-Random
                $url += "$($apiConfig.path)?q=$($query.q)&category=$($query.category)"
                Invoke-ApiCall -Url $url -Method $apiConfig.method -Headers $headers -ApiName 'ProductSearch'
            }
            'userValidation' {
                $testData = $apiConfig.testData | Get-Random
                $url += $apiConfig.path
                Invoke-ApiCall -Url $url -Method $apiConfig.method -Body $testData -Headers $headers -ApiName 'UserValidation'
            }
            'currencyConvert' {
                $conversion = $apiConfig.conversions | Get-Random
                $url += "$($apiConfig.path)?from=$($conversion.from)&to=$($conversion.to)&amount=$($conversion.amount)"
                Invoke-ApiCall -Url $url -Method $apiConfig.method -Headers $headers -ApiName 'CurrencyConvert'
            }
            'health' {
                $url += $apiConfig.path
                Invoke-ApiCall -Url $url -Method $apiConfig.method -Headers $headers -ApiName 'Health'
            }
            'delaySimulator' {
                $scenario = $apiConfig.scenarios | Get-Random
                $url += "$($apiConfig.path)?delay=$($scenario.delay)&status=$($scenario.status)"
                Invoke-ApiCall -Url $url -Method $apiConfig.method -Headers $headers -ApiName 'DelaySimulator'
            }
        }
        
        # Random delay between requests (100ms to 2000ms) to simulate realistic user behavior
        Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 2000)
    }
} -ThrottleLimit $concurrentUsers

# ForEach-Object -Parallel is synchronous and has already completed
Write-Info "Load test completed"

# Stop progress job if running
if ($progressJob) {
    Stop-Job $progressJob -ErrorAction SilentlyContinue
    Remove-Job $progressJob -ErrorAction SilentlyContinue
}

# Final statistics
$durationSeconds = ((Get-Date) - $script:stats['startTime']).TotalSeconds
$avgRPS = [math]::Round($script:stats['totalRequests'] / $durationSeconds, 2)
$successRate = if ($script:stats['totalRequests'] -gt 0) {
    [math]::Round(($script:stats['successfulRequests'] / $script:stats['totalRequests']) * 100, 2)
}
else { 0 }

Write-Header "Load Test Results"

Write-Host "📈 Request Statistics" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  Total Requests:        " -NoNewline; Write-Host $script:stats['totalRequests'] -ForegroundColor White
Write-Host "  Successful:            " -NoNewline; Write-Host "$($script:stats['successfulRequests']) ($successRate%)" -ForegroundColor Green
Write-Host "  Failed:                " -NoNewline; Write-Host $script:stats['failedRequests'] -ForegroundColor Red
Write-Host "  Average RPS:           " -NoNewline; Write-Host $avgRPS -ForegroundColor Yellow
Write-Host "  Test Duration:         " -NoNewline; Write-Host "$([math]::Round($durationSeconds, 2))s" -ForegroundColor White

Write-Host "`n🎯 API Behavior Statistics" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  Cache Hits:            " -NoNewline; Write-Host $script:stats['cacheHits'] -ForegroundColor Cyan
Write-Host "  Rate Limit Errors:     " -NoNewline; Write-Host $script:stats['rateLimitErrors'] -ForegroundColor Yellow
Write-Host "  Validation Errors:     " -NoNewline; Write-Host $script:stats['validationErrors'] -ForegroundColor Magenta

Write-Host "`n"
Write-Success "Load test completed successfully!"
Write-Info "Check your APIM monitoring dashboards for the generated traffic data."
Write-Host ""
