using System.Net;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace KadsiBridge;

/// <summary>Turns an iTop ticket into the Azure DevOps work item fields (pure: no I/O, easy to test).</summary>
public static partial class WorkItemBuilder
{
    /// <summary>Tag that identifies the ticket in Azure DevOps: one work item per ticket, never two.</summary>
    public static string TicketTag(TicketRequest ticket) => $"iTop-{ticket.Ref}";

    /// <summary>Validation of what iTop sends; null when it is fine.</summary>
    public static string? Validate(TicketRequest? ticket)
    {
        if (ticket is null)
        {
            return "El cuerpo debe ser el JSON del ticket.";
        }
        if (string.IsNullOrWhiteSpace(ticket.Ref) || !RefRegex().IsMatch(ticket.Ref))
        {
            return "Falta la referencia del ticket (por ejemplo I-000123).";
        }
        if (string.IsNullOrWhiteSpace(ticket.Title))
        {
            return "Falta el título del ticket.";
        }
        return null;
    }

    /// <summary>iTop priority 1 (critical) … 4 (low) maps to Azure DevOps 1 … 4; anything else to 2.</summary>
    public static int Priority(int? itopPriority) => itopPriority is >= 1 and <= 4 ? itopPriority.Value : 2;

    public static string Title(TicketRequest ticket)
    {
        var title = $"[{ticket.Ref}] {ticket.Title!.Trim()}";
        return title.Length <= 255 ? title : title[..255];
    }

    /// <summary>The ticket description (HTML from iTop) plus a header with its origin and the link back to iTop.</summary>
    public static string Description(TicketRequest ticket)
    {
        var lines = new List<string>
        {
            $"<p><b>Ticket de iTop:</b> {Link(ticket.TicketUrl, ticket.Ref!)}</p>",
        };
        AddLine(lines, "Organización", ticket.Organization);
        AddLine(lines, "Solicitante", ticket.Caller);
        AddLine(lines, "Servicio", ticket.Service);
        lines.Add("<hr/>");
        lines.Add(string.IsNullOrWhiteSpace(ticket.DescriptionHtml) ? "<p>(Sin descripción)</p>" : ticket.DescriptionHtml);
        return string.Join(Environment.NewLine, lines);
    }

    /// <summary>JSON Patch document to create the work item.</summary>
    public static JsonArray CreatePatch(TicketRequest ticket, DevOpsOptions options, string iterationPath, string? areaPath)
    {
        var tags = options.Tags.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Append(TicketTag(ticket)).Distinct(StringComparer.OrdinalIgnoreCase);
        var patch = new JsonArray
        {
            Add("System.Title", Title(ticket)),
            Add("System.Description", Description(ticket)),
            Add("System.Tags", string.Join("; ", tags)),
            Add("Microsoft.VSTS.Common.Priority", Priority(ticket.Priority)),
            Add("System.IterationPath", iterationPath),
        };
        if (!string.IsNullOrWhiteSpace(areaPath))
        {
            patch.Add(Add("System.AreaPath", areaPath));
        }
        if (Uri.TryCreate(ticket.TicketUrl, UriKind.Absolute, out var url) && url.Scheme is "http" or "https")
        {
            patch.Add(new JsonObject
            {
                ["op"] = "add",
                ["path"] = "/relations/-",
                ["value"] = new JsonObject { ["rel"] = "Hyperlink", ["url"] = url.ToString(), ["attributes"] = new JsonObject { ["comment"] = $"Ticket {ticket.Ref} en iTop" } },
            });
        }
        return patch;
    }

    private static JsonObject Add(string field, JsonNode? value) => new() { ["op"] = "add", ["path"] = $"/fields/{field}", ["value"] = value };

    private static void AddLine(List<string> lines, string label, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            lines.Add($"<p><b>{label}:</b> {WebUtility.HtmlEncode(value.Trim())}</p>");
        }
    }

    private static string Link(string? url, string text) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https"
            ? $"<a href=\"{WebUtility.HtmlEncode(uri.ToString())}\">{WebUtility.HtmlEncode(text)}</a>"
            : WebUtility.HtmlEncode(text);

    [GeneratedRegex("^[A-Za-z]{1,10}-\\d{1,12}$")]
    private static partial Regex RefRegex();
}
