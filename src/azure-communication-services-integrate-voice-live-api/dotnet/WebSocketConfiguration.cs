using Microsoft.AspNetCore.Builder;

public static class WebSocketConfiguration
{
    public static void ConfigureWebSockets(this WebApplicationBuilder builder)
    {
        // Configure WebSocket options
        builder.Services.Configure<WebSocketOptions>(options =>
        {
            options.KeepAliveInterval = TimeSpan.FromSeconds(120);
            options.ReceiveBufferSize = 4 * 1024; // 4KB
        });
        
        // Add CORS to allow ACS to connect
        builder.Services.AddCors(options =>
        {
            options.AddPolicy("AllowACS", policy =>
            {
                policy.AllowAnyOrigin()
                      .AllowAnyMethod()
                      .AllowAnyHeader();
            });
        });
    }
    
    public static void UseWebSocketConfiguration(this WebApplication app)
    {
        // Enable CORS
        app.UseCors("AllowACS");
        
        // Enable WebSockets with proper configuration
        app.UseWebSockets(new WebSocketOptions
        {
            KeepAliveInterval = TimeSpan.FromSeconds(120),
            ReceiveBufferSize = 4 * 1024
        });
    }
}