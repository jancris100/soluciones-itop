using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Azure.Core;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ItopDevOpsBridge;

/// <summary>A call to Azure DevOps failed. Transient = worth retrying later (iTop's queue retries it).</summary>
public sealed class DevOpsException(string message, bool transient) : Exception(message)
{
    public bool Transient { get; } = transient;
}

/// <summary>
/// Azure DevOps REST API (7.1): current sprint of the team, search by tag and work item creation. Authenticates with a
/// Microsoft Entra ID token (managed identity in Azure, the developer's login locally); a personal access token only
/// when <see cref="DevOpsOptions.PersonalAccessToken"/> is set (organizations not connected to Entra ID).
/// </summary>
public sealed class DevOpsClient(HttpClient http, TokenCredential credential, IOptions<DevOpsOptions> options, ILogger<DevOpsClient> logger)
{
    /// <summary>Azure DevOps resource id in Microsoft Entra ID.</summary>
    private const string Scope = "499b84ac-1321-427f-aa17-267ca6975798/.default";

    private const string ApiVersion = "api-version=7.1";

    private DevOpsOptions Options => options.Value;

    private string ProjectUrl => $"{Options.BaseUrl}/{Uri.EscapeDataString(Options.Project)}";

    private string TeamUrl => $"{ProjectUrl}/{Uri.EscapeDataString(Options.Team)}";

    /// <summary>Path of the team's current sprint, or the project root (backlog) when no sprint is active today.</summary>
    public async Task<(string Path, bool IsSprint)> CurrentIterationAsync(CancellationToken cancellationToken)
    {
        var body = await SendAsync(HttpMethod.Get, $"{TeamUrl}/_apis/work/teamsettings/iterations?$timeframe=current&{ApiVersion}", null, null, cancellationToken);
        var path = body?["value"]?.AsArray().FirstOrDefault()?["path"]?.GetValue<string>();
        return path is null ? (Options.Project, false) : (path, true);
    }

    /// <summary>The team's default area (used when AreaPath is not configured).</summary>
    public async Task<string?> DefaultAreaAsync(CancellationToken cancellationToken)
    {
        var body = await SendAsync(HttpMethod.Get, $"{TeamUrl}/_apis/work/teamsettings/teamfieldvalues?{ApiVersion}", null, null, cancellationToken);
        return body?["defaultValue"]?.GetValue<string>();
    }

    /// <summary>Work item already created for the ticket (tag iTop-&lt;ref&gt;), so a repeated call never duplicates it.</summary>
    public async Task<(int Id, string Iteration)?> FindByTagAsync(string tag, CancellationToken cancellationToken)
    {
        var safeTag = tag.Replace("'", "''", StringComparison.Ordinal);
        var query = new JsonObject
        {
            ["query"] = $"SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.Tags] CONTAINS '{safeTag}' AND [System.State] <> 'Removed' ORDER BY [System.Id]",
        };
        var body = await SendAsync(HttpMethod.Post, $"{ProjectUrl}/_apis/wit/wiql?$top=1&{ApiVersion}", query.ToJsonString(), "application/json", cancellationToken);
        var id = body?["workItems"]?.AsArray().FirstOrDefault()?["id"]?.GetValue<int>();
        if (id is null)
        {
            return null;
        }
        var item = await SendAsync(HttpMethod.Get, $"{Options.BaseUrl}/_apis/wit/workitems/{id}?fields=System.IterationPath&{ApiVersion}", null, null, cancellationToken);
        return (id.Value, item?["fields"]?["System.IterationPath"]?.GetValue<string>() ?? string.Empty);
    }

    public async Task<int> CreateAsync(JsonArray patch, CancellationToken cancellationToken)
    {
        var type = Uri.EscapeDataString(Options.WorkItemType);
        var body = await SendAsync(HttpMethod.Post, $"{ProjectUrl}/_apis/wit/workitems/${type}?{ApiVersion}", patch.ToJsonString(), "application/json-patch+json", cancellationToken);
        return body?["id"]?.GetValue<int>() ?? throw new DevOpsException("Azure DevOps no devolvió el número del elemento creado.", transient: true);
    }

    /// <summary>Address of the work item in the web (what the agent opens from iTop).</summary>
    public string WebUrl(int id) => $"{ProjectUrl}/_workitems/edit/{id}";

    private async Task<JsonNode?> SendAsync(HttpMethod method, string url, string? json, string? contentType, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, url);
        request.Headers.Authorization = await AuthorizationAsync(cancellationToken);
        if (json is not null)
        {
            request.Content = new StringContent(json, Encoding.UTF8);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType!);
        }

        HttpResponseMessage response;
        try
        {
            response = await http.SendAsync(request, cancellationToken);
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
        {
            throw new DevOpsException("No se pudo conectar con Azure DevOps.", transient: true);
        }

        using (response)
        {
            var text = await response.Content.ReadAsStringAsync(cancellationToken);
            if (response.IsSuccessStatusCode)
            {
                return text.Length == 0 ? null : JsonNode.Parse(text);
            }

            // Azure DevOps sends "message" with the reason (field that does not exist, type not in the process…).
            string? reason = null;
            try
            {
                reason = JsonNode.Parse(text)?["message"]?.GetValue<string>();
            }
            catch (System.Text.Json.JsonException)
            {
                // A sign-in page or HTML error: no reason to show.
            }
            logger.LogWarning("Azure DevOps answered {Status} for {Method} {Path}", (int)response.StatusCode, method, new Uri(url).AbsolutePath);
            var status = (int)response.StatusCode;
            throw response.StatusCode switch
            {
                HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden or HttpStatusCode.NonAuthoritativeInformation =>
                    new DevOpsException("Azure DevOps rechazó la identidad: revise que esté agregada a la organización con acceso Basic y permiso para crear elementos.", transient: false),
                HttpStatusCode.NotFound => new DevOpsException($"No se encontró en Azure DevOps la organización, el proyecto o el equipo configurado. {reason}".Trim(), transient: false),
                _ when status == 429 || status >= 500 => new DevOpsException($"Azure DevOps no está disponible ahora ({status}).", transient: true),
                _ => new DevOpsException($"Azure DevOps no aceptó la solicitud ({status}). {reason}".Trim(), transient: false),
            };
        }
    }

    private async Task<AuthenticationHeaderValue> AuthorizationAsync(CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(Options.PersonalAccessToken))
        {
            return new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes(":" + Options.PersonalAccessToken)));
        }
        var token = await credential.GetTokenAsync(new TokenRequestContext([Scope], tenantId: string.IsNullOrWhiteSpace(Options.TenantId) ? null : Options.TenantId), cancellationToken);
        return new AuthenticationHeaderValue("Bearer", token.Token);
    }
}
