namespace KadsiBridge;

/// <summary>What iTop sends for a ticket tagged KADSI (see extensiones/kadsi-devops/main.kadsi-devops.php).</summary>
public sealed record TicketRequest(
    string? Source,
    string? TicketClass,
    int TicketId,
    string? Ref,
    string? Title,
    string? DescriptionHtml,
    int? Priority,
    string? Organization,
    string? Caller,
    string? Service,
    string? TicketUrl);

/// <summary>Answer to iTop: the work item (created now or found) and the sprint it went to.</summary>
public sealed record WorkItemResult(int WorkItemId, string Url, string Iteration, bool Created, string Message);

/// <summary>Error answer, readable in iTop's async task log.</summary>
public sealed record ErrorResult(string Message);
