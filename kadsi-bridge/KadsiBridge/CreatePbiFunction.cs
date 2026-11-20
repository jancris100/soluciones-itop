using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace KadsiBridge;

/// <summary>
/// POST /api/kadsi/pbi (function key in x-functions-key): iTop sends a ticket tagged KADSI; the work item is created in
/// the team's current sprint, or the existing one is returned (one work item per ticket). The answer goes back to iTop,
/// which stores the number and link in the ticket, so Azure never needs to reach iTop.
/// </summary>
public sealed class CreatePbiFunction(DevOpsClient devOps, Microsoft.Extensions.Options.IOptions<DevOpsOptions> options, ILogger<CreatePbiFunction> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function("CreatePbi")]
    public async Task<IActionResult> RunAsync(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "kadsi/pbi")] HttpRequest request,
        CancellationToken cancellationToken)
    {
        TicketRequest? ticket;
        try
        {
            ticket = await JsonSerializer.DeserializeAsync<TicketRequest>(request.Body, Json, cancellationToken);
        }
        catch (JsonException)
        {
            return new BadRequestObjectResult(new ErrorResult("El cuerpo no es un JSON válido."));
        }
        if (WorkItemBuilder.Validate(ticket) is { } problem)
        {
            return new BadRequestObjectResult(new ErrorResult(problem));
        }

        var tag = WorkItemBuilder.TicketTag(ticket!);
        try
        {
            logger.LogInformation("KADSI ticket {Ref} ({Class} #{Id}) received", ticket!.Ref, ticket.TicketClass, ticket.TicketId);

            if (await devOps.FindByTagAsync(tag, cancellationToken) is { } existing)
            {
                logger.LogInformation("Ticket {Ref} already has work item {WorkItem}", ticket.Ref, existing.Id);
                return new OkObjectResult(new WorkItemResult(existing.Id, devOps.WebUrl(existing.Id), existing.Iteration, Created: false,
                    $"El ticket ya tenía el elemento {existing.Id}."));
            }

            var (iteration, isSprint) = await devOps.CurrentIterationAsync(cancellationToken);
            var area = string.IsNullOrWhiteSpace(options.Value.AreaPath) ? await devOps.DefaultAreaAsync(cancellationToken) : options.Value.AreaPath;
            var id = await devOps.CreateAsync(WorkItemBuilder.CreatePatch(ticket, options.Value, iteration, area), cancellationToken);

            logger.LogInformation("Work item {WorkItem} created for ticket {Ref} in {Iteration}", id, ticket.Ref, iteration);
            var message = isSprint ? $"Creado en {iteration}." : "No hay sprint activo: quedó en el backlog del equipo.";
            return new ObjectResult(new WorkItemResult(id, devOps.WebUrl(id), iteration, Created: true, message)) { StatusCode = StatusCodes.Status201Created };
        }
        catch (DevOpsException exception)
        {
            logger.LogWarning("Ticket {Ref} not sent to Azure DevOps (transient: {Transient}): {Reason}", ticket!.Ref, exception.Transient, exception.Message);
            // 503 = iTop retries later; 422 = configuration or permission problem, retrying alone will not fix it.
            return new ObjectResult(new ErrorResult(exception.Message)) { StatusCode = exception.Transient ? StatusCodes.Status503ServiceUnavailable : StatusCodes.Status422UnprocessableEntity };
        }
    }
}
