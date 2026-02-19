// Add Application Insights logging to existing APIs
@description('Name of the API Management service')
param apimServiceName string
param loggerName string = 'applicationinsights-logger'

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

// Weather API - Updated with logging
resource weatherApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'weather-api'
}

resource weatherApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: weatherApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="weather-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
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
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault<DateTime>("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
    <trace source="weather-api" severity="error">
      <message>@("Error: " + context.LastError.Message)</message>
    </trace>
  </on-error>
</policies>
'''
  }
}

// Product Search API - Updated with logging
resource productSearchApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'product-search-api'
}

resource productSearchApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: productSearchApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="product-search-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
    </trace>
    <rate-limit calls="10" renewal-period="60" />
    <quota calls="100" renewal-period="86400" />
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
          new JProperty("results", 3),
          new JProperty("products", new JArray(
            new JObject(
              new JProperty("id", "PROD-001"),
              new JProperty("name", "Professional Laptop"),
              new JProperty("price", 1299.99)
            )
          ))
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="product-search-api" severity="information">
      <message>@("Response: " + context.Response.StatusCode.ToString())</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault<DateTime>("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="429" reason="Too Many Requests" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>{"error":"Rate limit exceeded"}</set-body>
    </return-response>
    <trace source="product-search-api" severity="warning">
      <message>@("Rate limit exceeded for: " + context.Request.IpAddress)</message>
    </trace>
  </on-error>
</policies>
'''
  }
}

// User Validation API - Updated with logging
resource userValidationApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'user-validation-api'
}

resource userValidationApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: userValidationApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="user-validation-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
    </trace>
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <issuer-signing-keys>
        <key>mockkey123456789</key>
      </issuer-signing-keys>
    </validate-jwt>
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
          new JProperty("email", "user@example.com"),
          new JProperty("valid", true)
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="user-validation-api" severity="information">
      <message>@("Response: " + context.Response.StatusCode.ToString())</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault<DateTime>("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
    <trace source="user-validation-api" severity="error">
      <message>@("JWT validation failed")</message>
    </trace>
  </on-error>
</policies>
'''
  }
}

// Currency Conversion API - Updated with logging
resource currencyConversionApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'currency-conversion-api'
}

resource currencyConversionApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: currencyConversionApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="currency-conversion-api" severity="information">
      <message>@("Request: " + context.Request.Method + " " + context.Request.Url.Path)</message>
      <metadata name="OperationId" value="@(context.RequestId)" />
    </trace>
    <cache-lookup-value key="exchange-rates" variable-name="rates" />
    <choose>
      <when condition="@(!context.Variables.ContainsKey("rates"))">
        <set-variable name="rates" value="@{
          return new JObject(
            new JProperty("USD_EUR", 0.925),
            new JProperty("USD_GBP", 0.79),
            new JProperty("EUR_USD", 1.081)
          );
        }" />
        <cache-store-value key="exchange-rates" value="@((JObject)context.Variables["rates"])" duration="300" />
      </when>
    </choose>
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
          new JProperty("amount", 100),
          new JProperty("converted", 92.50),
          new JProperty("exchangeRate", 0.925)
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="currency-conversion-api" severity="information">
      <message>@("Response: " + context.Response.StatusCode.ToString())</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault<DateTime>("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// Health Monitor API - Updated with logging
resource healthMonitorApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'health-monitor-api'
}

resource healthMonitorApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: healthMonitorApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <trace source="health-monitor-api" severity="information">
      <message>@("Health check request from: " + context.Request.IpAddress)</message>
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
      <set-header name="Cache-Control" exists-action="override">
        <value>no-cache, no-store, must-revalidate</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("status", "healthy"),
          new JProperty("timestamp", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")),
          new JProperty("uptime", "99.99%")
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="health-monitor-api" severity="information">
      <message>Health check passed</message>
      <metadata name="Duration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault<DateTime>("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// Delay Simulator API - Updated with logging
resource delaySimulatorApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' existing = {
  parent: apimService
  name: 'delay-simulator-api'
}

resource delaySimulatorApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: delaySimulatorApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-variable name="RequestTime" value="@(DateTime.UtcNow)" />
    <set-variable name="delay" value="@(Convert.ToInt32(context.Request.Url.Query.GetValueOrDefault("delay", "1000")))" />
    <set-variable name="statusCode" value="@(Convert.ToInt32(context.Request.Url.Query.GetValueOrDefault("status", "200")))" />
    <trace source="delay-simulator-api" severity="information">
      <message>@("Simulating delay: " + context.Variables.GetValueOrDefault<int>("delay").ToString() + "ms")</message>
      <metadata name="RequestedDelay" value="@(context.Variables.GetValueOrDefault<int>("delay").ToString())" />
    </trace>
    <wait for="@(TimeSpan.FromMilliseconds(context.Variables.GetValueOrDefault<int>("delay")))" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <return-response>
      <set-status code="@(context.Variables.GetValueOrDefault<int>("statusCode"))" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("message", "Simulated response"),
          new JProperty("requestedDelay", context.Variables.GetValueOrDefault<int>("delay")),
          new JProperty("statusCode", context.Variables.GetValueOrDefault<int>("statusCode"))
        ).ToString();
      }</set-body>
    </return-response>
    <trace source="delay-simulator-api" severity="information">
      <message>@("Delay completed: " + context.Response.StatusCode.ToString())</message>
      <metadata name="ActualDuration" value="@((DateTime.UtcNow - context.Variables.GetValueOrDefault<DateTime>("RequestTime")).TotalMilliseconds.ToString())" />
    </trace>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

output message string = 'Application Insights logging added to all 6 APIs'
output apis array = [
  'weather-api'
  'product-search-api'
  'user-validation-api'
  'currency-conversion-api'
  'health-monitor-api'
  'delay-simulator-api'
]
