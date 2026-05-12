#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates API policies to add Application Insights logging
#>

# Get current subscription ID from Azure CLI
$subscriptionId = (az account show --query id -o tsv)
$resourceGroup = "rg-apim-monitoring"
$apimName = "your-apim-instance"

Write-Host "Adding Application Insights logging to API policies..." -ForegroundColor Cyan
Write-Host ""

# Weather API
Write-Host "[1/6] Updating Weather API..." -ForegroundColor Yellow
$weatherPolicy = @'
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="weather-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.Request Id)" />
      <metadata name="ClientIP" value="@(context.Request.IpAddress)" />
    </trace>
    <cache-lookup vary-by-developer="false" vary-by-developer-groups="false" downstream-caching-type="none" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        var city = context.Request.MatchedParameters["city"];
        return new JObject(
          new JProperty("city", city),
          new JProperty("temperature", 72),
          new JProperty("conditions", "Sunny"),
          new JProperty("humidity", 45),
          new JProperty("cached", true)
        ).ToString();
      }</set-body>
    </return-response>
    <cache-store duration="300" />
    <trace source="weather-api" severity="information">
      <message>@("Response: " + context.Response.StatusCode.ToString())</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault&lt;DateTime&gt;("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
    <trace source="weather-api" severity="error">
      <message>@("Error: " + context.LastError.Message)</message>
    </trace>
  </on-error>
</policies>
'@

$body = @{ properties = @{ value = $weatherPolicy; format = "xml" } } | ConvertTo-Json -Depth 10
az rest --method put --uri "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/weather-api/policies/policy?api-version=2023-05-01-preview" --body $body | Out-Null

if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ Updated successfully" -ForegroundColor Green }
else { Write-Host "  ✗ Failed" -ForegroundColor Red }

# Product Search API
Write-Host "[2/6] Updating Product Search API..." -ForegroundColor Yellow
$productPolicy = @'
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="product-search-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
    </trace>
    <rate-limit calls="10" renewal-period="60" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("query", "laptop"),
          new JProperty("results", 3)
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="product-search-api" severity="information">
      <message>@("Response: " + context.Response.StatusCode.ToString())</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault&lt;DateTime&gt;("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
    <trace source="product-search-api" severity="warning">
      <message>@("Rate limit exceeded")</message>
    </trace>
  </on-error>
</policies>
'@

$body = @{ properties = @{ value = $productPolicy; format = "xml" } } | ConvertTo-Json -Depth 10
az rest --method put --uri "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/product-search-api/policies/policy?api-version=2023-05-01-preview" --body $body | Out-Null

if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ Updated successfully" -ForegroundColor Green }
else { Write-Host "  ✗ Failed" -ForegroundColor Red }

# User Validation API
Write-Host "[3/6] Updating User Validation API..." -ForegroundColor Yellow
$userPolicy = @'
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="user-validation-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
    </trace>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("userId", "user123"),
          new JProperty("valid", true)
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="user-validation-api" severity="information">
      <message>@("Response: " + context.Response.StatusCode.ToString())</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault&lt;DateTime&gt;("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'@

$body = @{ properties = @{ value = $userPolicy; format = "xml" } } | ConvertTo-Json -Depth 10
az rest --method put --uri "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/user-validation-api/policies/policy?api-version=2023-05-01-preview" --body $body | Out-Null

if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ Updated successfully" -ForegroundColor Green }
else { Write-Host "  ✗ Failed" -ForegroundColor Red }

# Currency Conversion API
Write-Host "[4/6] Updating Currency Conversion API..." -ForegroundColor Yellow
$currencyPolicy = @'
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="currency-conversion-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
    </trace>
    <cache-lookup-value key="exchange-rates" variable-name="rates" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("from", "USD"),
          new JProperty("to", "EUR"),
          new JProperty("converted", 92.50)
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="currency-conversion-api" severity="information">
      <message>@("Response: " + context.Response.StatusCode.ToString())</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault&lt;DateTime&gt;("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'@

$body = @{ properties = @{ value = $currencyPolicy; format = "xml" } } | ConvertTo-Json -Depth 10
az rest --method put --uri "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/currency-conversion-api/policies/policy?api-version=2023-05-01-preview" --body $body | Out-Null

if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ Updated successfully" -ForegroundColor Green }
else { Write-Host "  ✗ Failed" -ForegroundColor Red }

# Health Monitor API
Write-Host "[5/6] Updating Health Monitor API..." -ForegroundColor Yellow
$healthPolicy = @'
<policies>
  <inbound>
    <base />
    <trace source="health-monitor-api" severity="information">
      <message>Health check requested</message>
    </trace>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("status", "healthy"),
          new JProperty("timestamp", DateTime.UtcNow.ToString())
        ).ToString();
      }</set-body>
    </return-response>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'@

$body = @{ properties = @{ value = $healthPolicy; format = "xml" } } | ConvertTo-Json -Depth 10
az rest --method put --uri "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/health-monitor-api/policies/policy?api-version=2023-05-01-preview" --body $body | Out-Null

if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ Updated successfully" -ForegroundColor Green }
else { Write-Host "  ✗ Failed" -ForegroundColor Red }

# Delay Simulator API
Write-Host "[6/6] Updating Delay Simulator API..." -ForegroundColor Yellow
$delayPolicy = @'
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <set-variable name="delay" value="@(Convert.ToInt32(context.Request.Url.Query.GetValueOrDefault("delay", "1000")))" />
    <trace source="delay-simulator-api" severity="information">
      <message>@("Simulating delay: " + context.Variables.GetValueOrDefault&lt;int&gt;("delay").ToString() + "ms")</message>
    </trace>
    <wait for="@(TimeSpan.FromMilliseconds(context.Variables.GetValueOrDefault&lt;int&gt;("delay")))" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("message", "Simulated response"),
          new JProperty("requestedDelay", context.Variables.GetValueOrDefault&lt;int&gt;("delay"))
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="delay-simulator-api" severity="information">
      <message>@("Delay completed")</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault&lt;DateTime&gt;("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'@

$body = @{ properties = @{ value = $delayPolicy; format = "xml" } } | ConvertTo-Json -Depth 10
az rest --method put --uri "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/delay-simulator-api/policies/policy?api-version=2023-05-01-preview" --body $body | Out-Null

if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ Updated successfully" -ForegroundColor Green}
else { Write-Host "  ✗ Failed" -ForegroundColor Red }

Write-Host ""
Write-Host "✓ Logging policies updated!" -ForegroundColor Green
Write-Host ""
Write-Host "Your APIs now log to Application Insights 'appi-$apimName':" -ForegroundColor White
Write-Host "  - Request details (method, URL, IP)" -ForegroundColor Gray
Write-Host "  - Response status codes" -ForegroundColor Gray
Write-Host "  - Request duration" -ForegroundColor Gray
Write-Host "  - Custom trace messages" -ForegroundColor Gray
Write-Host ""
Write-Host "View logs in Azure Portal:" -ForegroundColor White
Write-Host "  Portal → Application Insights → appi-$apimName → Logs" -ForegroundColor Cyan
Write-Host ""
Write-Host "Sample query:" -ForegroundColor White
Write-Host "  traces | where message contains 'Request'" -ForegroundColor Gray
Write-Host ""
