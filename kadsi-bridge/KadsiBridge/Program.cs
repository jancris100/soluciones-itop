using Azure.Core;
using Azure.Identity;
using KadsiBridge;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

var builder = FunctionsApplication.CreateBuilder(args);
builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

builder.Services.AddOptions<DevOpsOptions>()
    .Bind(builder.Configuration.GetSection("DevOps"))
    .Validate(options => options.Organization.Length > 0 && options.Project.Length > 0 && options.Team.Length > 0,
        "Configure DevOps__Organization, DevOps__Project and DevOps__Team.")
    .ValidateOnStart();

// In Azure: the Function's managed identity. Locally: the developer's Azure CLI / Visual Studio login.
builder.Services.AddSingleton<TokenCredential>(provider =>
{
    var options = provider.GetRequiredService<IOptions<DevOpsOptions>>().Value;
    return new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        ManagedIdentityClientId = string.IsNullOrWhiteSpace(options.ManagedIdentityClientId) ? null : options.ManagedIdentityClientId,
        TenantId = string.IsNullOrWhiteSpace(options.TenantId) ? null : options.TenantId,
        ExcludeInteractiveBrowserCredential = true,
    });
});
builder.Services.AddHttpClient<DevOpsClient>(client => client.Timeout = TimeSpan.FromSeconds(20));

builder.Build().Run();
