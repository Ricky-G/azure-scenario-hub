// ========================================
// API Management APIs Module
// ========================================
// This module creates all sample APIs with their policies

@description('The name of the API Management service')
param apimServiceName string

// ============
// Variables
// ============

var weatherApiPolicyXml = '''
<policies>
  <inbound>
    <base />
    <cache-lookup vary-by-developer="false" vary-by-developer-groups="false">
      <vary-by-query-parameter>city</vary-by-query-parameter>
    </cache-lookup>
    <set-variable name="city" value="@(context.Request.MatchedParameters["city"])" />
    <set-variable name="temperature" value="@(new Random().Next(10, 30))" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <set-header name="X-Cache-Status" exists-action="override">
      <value>@(context.Variables.ContainsKey("cached") ? "HIT" : "MISS")</value>
    </set-header>
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        var city = context.Variables.GetValueOrDefault<string>("city", "Unknown");
        var temp = context.Variables.GetValueOrDefault<int>("temperature", 20);
        return new JObject(
          new JProperty("city", city),
          new JProperty("temperature", temp + 0.5),
          new JProperty("conditions", "Partly Cloudy"),
          new JProperty("humidity", new Random().Next(40, 80)),
          new JProperty("timestamp", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")),
          new JProperty("cached", context.Variables.ContainsKey("cached"))
        ).ToString();
      }</set-body>
    </return-response>
    <cache-store duration="60" />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

var productSearchApiPolicyXml = '''
<policies>
  <inbound>
    <base />
    <rate-limit calls="10" renewal-period="60" />
    <quota calls="100" renewal-period="86400" />
    <set-variable name="searchQuery" value="@(context.Request.Url.Query.GetValueOrDefault("q", "all"))" />
    <set-variable name="category" value="@(context.Request.Url.Query.GetValueOrDefault("category", "general"))" />
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
      <set-header name="X-RateLimit-Remaining" exists-action="override">
        <value>@(context.Response.Headers.GetValueOrDefault("Rate-Limit-Remaining","9"))</value>
      </set-header>
      <set-body>@{
        var query = context.Variables.GetValueOrDefault<string>("searchQuery", "all");
        var category = context.Variables.GetValueOrDefault<string>("category", "general");
        return new JObject(
          new JProperty("query", query),
          new JProperty("category", category),
          new JProperty("results", 3),
          new JProperty("products", new JArray(
            new JObject(
              new JProperty("id", "PROD-001"),
              new JProperty("name", "Professional Laptop"),
              new JProperty("price", 1299.99),
              new JProperty("inStock", true)
            ),
            new JObject(
              new JProperty("id", "PROD-002"),
              new JProperty("name", "Wireless Mouse"),
              new JProperty("price", 29.99),
              new JProperty("inStock", true)
            ),
            new JObject(
              new JProperty("id", "PROD-003"),
              new JProperty("name", "USB-C Hub"),
              new JProperty("price", 49.99),
              new JProperty("inStock", false)
            )
          )),
          new JProperty("rateLimit", new JObject(
            new JProperty("remaining", 8),
            new JProperty("resetIn", 45)
          ))
        ).ToString();
      }</set-body>
    </return-response>
  </outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="429" reason="Too Many Requests" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("error", "Rate limit exceeded"),
          new JProperty("message", "You have exceeded the allowed number of requests. Please try again later."),
          new JProperty("retryAfter", 60)
        ).ToString();
      }</set-body>
    </return-response>
  </on-error>
</policies>
'''

var userValidationApiPolicyXml = '''
<policies>
  <inbound>
    <base />
    <set-variable name="requestBody" value="@(context.Request.Body.As<JObject>(preserveContent: true))" />
    <choose>
      <when condition="@(context.Request.Body == null || context.Request.Body.As<JObject>(preserveContent: true) == null)">
        <return-response>
          <set-status code="400" reason="Bad Request" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>@{
            return new JObject(
              new JProperty("valid", false),
              new JProperty("error", "Invalid request body"),
              new JProperty("message", "Request body must be valid JSON")
            ).ToString();
          }</set-body>
        </return-response>
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
        var body = context.Variables.GetValueOrDefault<JObject>("requestBody");
        var email = body?.GetValue("email")?.ToString() ?? "";
        var username = body?.GetValue("username")?.ToString() ?? "";
        var age = body?.GetValue("age")?.Value<int?>() ?? 0;
        
        var isValid = !string.IsNullOrEmpty(email) && 
                      !string.IsNullOrEmpty(username) && 
                      username.Length >= 3 && 
                      age >= 18;
        
        var emailDomain = email.Contains("@") ? email.Split('@')[1] : "unknown";
        
        return new JObject(
          new JProperty("valid", isValid),
          new JProperty("username", username),
          new JProperty("emailDomain", emailDomain),
          new JProperty("validationTime", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")),
          new JProperty("checks", new JObject(
            new JProperty("emailFormat", email.Contains("@") ? "passed" : "failed"),
            new JProperty("usernameLength", username.Length >= 3 ? "passed" : "failed"),
            new JProperty("ageRequirement", age >= 18 ? "passed" : "failed")
          ))
        ).ToString();
      }</set-body>
    </return-response>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

var currencyConversionApiPolicyXml = '''
<policies>
  <inbound>
    <base />
    <cache-lookup-value key="exchange-rates" variable-name="rates" />
    <choose>
      <when condition="@(!context.Variables.ContainsKey("rates"))">
        <set-variable name="rates" value="@{
          return new JObject(
            new JProperty("USD_EUR", 0.925),
            new JProperty("USD_GBP", 0.79),
            new JProperty("USD_JPY", 149.50),
            new JProperty("EUR_USD", 1.081),
            new JProperty("GBP_USD", 1.266)
          );
        }" />
        <cache-store-value key="exchange-rates" value="@((JObject)context.Variables["rates"])" duration="300" />
      </when>
    </choose>
    <set-variable name="fromCurrency" value="@(context.Request.Url.Query.GetValueOrDefault("from", "USD").ToUpper())" />
    <set-variable name="toCurrency" value="@(context.Request.Url.Query.GetValueOrDefault("to", "EUR").ToUpper())" />
    <set-variable name="amount" value="@(Convert.ToDouble(context.Request.Url.Query.GetValueOrDefault("amount", "100")))" />
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
        var rates = context.Variables.GetValueOrDefault<JObject>("rates");
        var from = context.Variables.GetValueOrDefault<string>("fromCurrency");
        var to = context.Variables.GetValueOrDefault<string>("toCurrency");
        var amount = context.Variables.GetValueOrDefault<double>("amount");
        
        var rateKey = from + "_" + to;
        var rate = rates?.GetValue(rateKey)?.Value<double?>() ?? 1.0;
        var converted = Math.Round(amount * rate, 2);
        
        return new JObject(
          new JProperty("from", from),
          new JProperty("to", to),
          new JProperty("amount", amount),
          new JProperty("converted", converted),
          new JProperty("exchangeRate", rate),
          new JProperty("timestamp", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")),
          new JProperty("cached", context.Variables.ContainsKey("rates"))
        ).ToString();
      }</set-body>
    </return-response>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

var healthMonitorApiPolicyXml = '''
<policies>
  <inbound>
    <base />
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
          new JProperty("version", "1.0.0"),
          new JProperty("services", new JObject(
            new JProperty("api", "operational"),
            new JProperty("cache", "operational")
          )),
          new JProperty("responseTime", 12)
        ).ToString();
      }</set-body>
    </return-response>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

var delaySimulatorApiPolicyXml = '''
<policies>
  <inbound>
    <base />
    <set-variable name="delay" value="@{
      var delayParam = context.Request.Url.Query.GetValueOrDefault("delay", "1000");
      int delay;
      if (!int.TryParse(delayParam, out delay)) {
        delay = 1000;
      }
      return Math.Min(Math.Max(delay, 100), 5000); // Clamp between 100ms and 5000ms
    }" />
    <set-variable name="statusCode" value="@{
      var statusParam = context.Request.Url.Query.GetValueOrDefault("status", "200");
      int status;
      if (!int.TryParse(statusParam, out status)) {
        status = 200;
      }
      return status;
    }" />
    <wait interval="@(context.Variables.GetValueOrDefault<int>("delay"))" />
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
      <set-header name="X-Simulated-Delay" exists-action="override">
        <value>@(context.Variables.GetValueOrDefault<int>("delay").ToString())</value>
      </set-header>
      <set-body>@{
        var delay = context.Variables.GetValueOrDefault<int>("delay");
        var status = context.Variables.GetValueOrDefault<int>("statusCode");
        
        return new JObject(
          new JProperty("message", "Simulated response"),
          new JProperty("requestedDelay", delay),
          new JProperty("actualDelay", delay),
          new JProperty("statusCode", status),
          new JProperty("timestamp", DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))
        ).ToString();
      }</set-body>
    </return-response>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

// ============
// Existing Resources
// ============

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

// ============
// API Resources
// ============

// 1. Weather Data API
resource weatherApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'weather-api'
  properties: {
    displayName: 'Weather Data API'
    apiRevision: '1'
    description: 'Demonstrates caching policies with mock weather data'
    subscriptionRequired: true
    path: 'weather'
    protocols: [
      'https'
    ]
    isCurrent: true
  }
}

resource weatherApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: weatherApi
  name: 'get-weather'
  properties: {
    displayName: 'Get Weather by City'
    method: 'GET'
    urlTemplate: '/{city}'
    templateParameters: [
      {
        name: 'city'
        description: 'City name'
        type: 'string'
        required: true
      }
    ]
    responses: [
      {
        statusCode: 200
        description: 'Success'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource weatherApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: weatherApi
  name: 'policy'
  properties: {
    value: weatherApiPolicyXml
    format: 'xml'
  }
}

// 2. Product Search API
resource productSearchApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'product-search-api'
  properties: {
    displayName: 'Product Search API'
    apiRevision: '1'
    description: 'Demonstrates rate limiting and quota policies'
    subscriptionRequired: true
    path: 'products'
    protocols: [
      'https'
    ]
    isCurrent: true
  }
}

resource productSearchApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: productSearchApi
  name: 'search-products'
  properties: {
    displayName: 'Search Products'
    method: 'GET'
    urlTemplate: '/search'
    request: {
      queryParameters: [
        {
          name: 'q'
          description: 'Search query'
          type: 'string'
          required: false
        }
        {
          name: 'category'
          description: 'Product category'
          type: 'string'
          required: false
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Success'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 429
        description: 'Too Many Requests'
      }
    ]
  }
}

resource productSearchApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: productSearchApi
  name: 'policy'
  properties: {
    value: productSearchApiPolicyXml
    format: 'xml'
  }
}

// 3. User Validation API
resource userValidationApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'user-validation-api'
  properties: {
    displayName: 'User Validation API'
    apiRevision: '1'
    description: 'Demonstrates request/response transformation and validation'
    subscriptionRequired: true
    path: 'users'
    protocols: [
      'https'
    ]
    isCurrent: true
  }
}

resource userValidationApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: userValidationApi
  name: 'validate-user'
  properties: {
    displayName: 'Validate User'
    method: 'POST'
    urlTemplate: '/validate'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Valid'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 400
        description: 'Bad Request'
      }
    ]
  }
}

resource userValidationApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: userValidationApi
  name: 'policy'
  properties: {
    value: userValidationApiPolicyXml
    format: 'xml'
  }
}

// 4. Currency Conversion API
resource currencyConversionApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'currency-conversion-api'
  properties: {
    displayName: 'Currency Conversion API'
    apiRevision: '1'
    description: 'Demonstrates policy expressions and caching'
    subscriptionRequired: true
    path: 'currency'
    protocols: [
      'https'
    ]
    isCurrent: true
  }
}

resource currencyConversionApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: currencyConversionApi
  name: 'convert-currency'
  properties: {
    displayName: 'Convert Currency'
    method: 'GET'
    urlTemplate: '/convert'
    request: {
      queryParameters: [
        {
          name: 'from'
          description: 'Source currency code'
          type: 'string'
          required: true
        }
        {
          name: 'to'
          description: 'Target currency code'
          type: 'string'
          required: true
        }
        {
          name: 'amount'
          description: 'Amount to convert'
          type: 'number'
          required: true
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Success'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource currencyConversionApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: currencyConversionApi
  name: 'policy'
  properties: {
    value: currencyConversionApiPolicyXml
    format: 'xml'
  }
}

// 5. Health Monitor API
resource healthMonitorApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'health-monitor-api'
  properties: {
    displayName: 'Health Monitor API'
    apiRevision: '1'
    description: 'Health check endpoint for uptime monitoring'
    subscriptionRequired: true
    path: 'health'
    protocols: [
      'https'
    ]
    isCurrent: true
  }
}

resource healthMonitorApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: healthMonitorApi
  name: 'get-health-status'
  properties: {
    displayName: 'Get Health Status'
    method: 'GET'
    urlTemplate: '/status'
    responses: [
      {
        statusCode: 200
        description: 'Healthy'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource healthMonitorApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: healthMonitorApi
  name: 'policy'
  properties: {
    value: healthMonitorApiPolicyXml
    format: 'xml'
  }
}

// 6. Delay Simulator API
resource delaySimulatorApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'delay-simulator-api'
  properties: {
    displayName: 'Delay Simulator API'
    apiRevision: '1'
    description: 'Simulate delays and various response codes for testing'
    subscriptionRequired: true
    path: 'simulate'
    protocols: [
      'https'
    ]
    isCurrent: true
  }
}

resource delaySimulatorApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: delaySimulatorApi
  name: 'simulate-delay'
  properties: {
    displayName: 'Simulate Delay'
    method: 'GET'
    urlTemplate: '/delay'
    request: {
      queryParameters: [
        {
          name: 'delay'
          description: 'Delay in milliseconds (100-5000)'
          type: 'number'
          required: false
          defaultValue: '1000'
        }
        {
          name: 'status'
          description: 'HTTP status code to return'
          type: 'number'
          required: false
          defaultValue: '200'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Success'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource delaySimulatorApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: delaySimulatorApi
  name: 'policy'
  properties: {
    value: delaySimulatorApiPolicyXml
    format: 'xml'
  }
}

// ============
// Outputs
// ============

@description('List of created API IDs')
output apiIds array = [
  weatherApi.id
  productSearchApi.id
  userValidationApi.id
  currencyConversionApi.id
  healthMonitorApi.id
  delaySimulatorApi.id
]

@description('List of created API names')
output apiNames array = [
  weatherApi.name
  productSearchApi.name
  userValidationApi.name
  currencyConversionApi.name
  healthMonitorApi.name
  delaySimulatorApi.name
]
