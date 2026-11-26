using ItopDevOpsBridge;
using Xunit;

namespace ItopDevOpsBridge.Tests;

public sealed class WorkItemBuilderTests
{
    private static TicketRequest Ticket(string? title = "Falla al facturar", int? priority = 1, string? url = "https://itop.empresa.com/pages/UI.php?operation=details&class=Incident&id=12") =>
        new("itop", "Incident", 12, "I-000012", title, "<p>No genera la factura <b>08</b></p>", priority, "Empresa S.A.", "Ana <Mora>", "Facturación", url);

    private static readonly DevOpsOptions Options = new() { Organization = "org", Project = "proj", Team = "team", Tags = "DEVOPS; Soporte" };

    [Fact]
    public void Patch_carries_title_with_ref_priority_sprint_tags_and_link_back_to_itop()
    {
        var patch = WorkItemBuilder.CreatePatch(Ticket(), Options, "proj\\Sprint 23", "proj\\Equipo");
        var fields = patch.Where(op => op!["path"]!.GetValue<string>().StartsWith("/fields/", StringComparison.Ordinal))
            .ToDictionary(op => op!["path"]!.GetValue<string>()[8..], op => op!["value"]!.ToString());

        Assert.Equal("[I-000012] Falla al facturar", fields["System.Title"]);
        Assert.Equal("1", fields["Microsoft.VSTS.Common.Priority"]);
        Assert.Equal("proj\\Sprint 23", fields["System.IterationPath"]);
        Assert.Equal("proj\\Equipo", fields["System.AreaPath"]);
        Assert.Equal("DEVOPS; Soporte; iTop-I-000012", fields["System.Tags"]);
        Assert.Contains(patch, op => op!["path"]!.GetValue<string>() == "/relations/-");
    }

    [Fact]
    public void Description_keeps_the_itop_html_and_encodes_the_header_values()
    {
        var description = WorkItemBuilder.Description(Ticket());

        Assert.Contains("<p>No genera la factura <b>08</b></p>", description);
        Assert.Contains("Ana &lt;Mora&gt;", description);
        Assert.Contains("href=\"https://itop.empresa.com/pages/UI.php?operation=details&amp;class=Incident&amp;id=12\"", description);
    }

    [Theory]
    [InlineData(1, 1)]
    [InlineData(4, 4)]
    [InlineData(0, 2)]
    [InlineData(null, 2)]
    public void Itop_priority_maps_to_devops_priority(int? itop, int expected) =>
        Assert.Equal(expected, WorkItemBuilder.Priority(itop));

    [Fact]
    public void Requests_without_ref_or_title_are_refused()
    {
        Assert.NotNull(WorkItemBuilder.Validate(null));
        Assert.NotNull(WorkItemBuilder.Validate(Ticket() with { Ref = "I 12; DROP" }));
        Assert.NotNull(WorkItemBuilder.Validate(Ticket(title: " ")));
        Assert.Null(WorkItemBuilder.Validate(Ticket()));
    }

    [Fact]
    public void Link_back_is_left_out_when_the_url_is_not_http()
    {
        var patch = WorkItemBuilder.CreatePatch(Ticket(url: "javascript:alert(1)"), Options, "proj", null);

        Assert.DoesNotContain(patch, op => op!["path"]!.GetValue<string>() == "/relations/-");
        Assert.DoesNotContain(patch, op => op!["path"]!.GetValue<string>() == "/fields/System.AreaPath");
    }
}
