using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services
            .AddApplicationInsightsTelemetryWorkerService()
            .ConfigureFunctionsApplicationInsights();
    })
    .Build();

host.Run();
