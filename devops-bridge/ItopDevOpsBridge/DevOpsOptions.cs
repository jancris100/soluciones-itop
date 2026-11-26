namespace ItopDevOpsBridge;

/// <summary>
/// Configuration section <c>DevOps</c> (app settings <c>DevOps__Organization</c>, …). Changing company means changing
/// these values only, never the code.
/// </summary>
public sealed class DevOpsOptions
{
    /// <summary>Organization name: the part after https://dev.azure.com/.</summary>
    public string Organization { get; set; } = string.Empty;

    public string Project { get; set; } = string.Empty;

    /// <summary>Team whose current sprint receives the work items (sprints belong to a team).</summary>
    public string Team { get; set; } = string.Empty;

    /// <summary>"Product Backlog Item" (Scrum), "User Story" (Agile) or "Issue" (Basic).</summary>
    public string WorkItemType { get; set; } = "Product Backlog Item";

    /// <summary>Area of the work items; empty = the team's default area.</summary>
    public string? AreaPath { get; set; }

    /// <summary>Extra tags, separated by ';'. The ticket reference (iTop-I-000123) is always added.</summary>
    public string Tags { get; set; } = "DEVOPS";

    /// <summary>Client id of a user-assigned managed identity; empty = the system-assigned one (or the developer's login locally).</summary>
    public string? ManagedIdentityClientId { get; set; }

    /// <summary>
    /// Entra ID tenant of the organization. Needed with <see cref="ClientId"/> (organization in another tenant), or locally
    /// when the developer's login has several tenants.
    /// </summary>
    public string? TenantId { get; set; }

    /// <summary>
    /// Only when the organization is in ANOTHER tenant than the Function: application (client) id of a multitenant app
    /// registration, in the Function's tenant, that trusts the Function's managed identity (federated credential). The
    /// Function signs in to <see cref="TenantId"/> as that application, with no secret. Empty = the managed identity itself.
    /// </summary>
    public string? ClientId { get; set; }

    /// <summary>
    /// Only for organizations NOT connected to Entra ID (tests): a personal access token with "Work Items: Read &amp; write".
    /// In the company it stays empty and the managed identity is used.
    /// </summary>
    public string? PersonalAccessToken { get; set; }

    public string BaseUrl => $"https://dev.azure.com/{Uri.EscapeDataString(Organization)}";
}
