using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Azure.Core;
using Azure.Identity;

namespace DevOpsDiario;

/// <summary>Un work item con los campos que usa la consola.</summary>
public sealed record Elemento(int Id, string Tipo, string Titulo, string Estado, string? AsignadoA, string Iteracion, string Area);

/// <summary>Sprint actual del equipo.</summary>
public sealed record Sprint(string Nombre, string Ruta, DateTime? Inicio, DateTime? Fin);

/// <summary>Azure DevOps REST 7.1 con el inicio de sesión de Microsoft Entra ID del usuario.</summary>
public sealed class AzureDevOps
{
    /// <summary>Recurso de Azure DevOps en Microsoft Entra ID.</summary>
    private const string Scope = "499b84ac-1321-427f-aa17-267ca6975798/.default";
    private const string Api = "api-version=7.1";
    private static readonly string[] Campos =
        ["System.Id", "System.WorkItemType", "System.Title", "System.State", "System.AssignedTo", "System.IterationPath", "System.AreaPath"];

    private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(60) };
    private readonly TokenCredential credencial;
    private readonly Configuracion config;

    /// <summary>Usuario conectado: nombre para mostrar y cuenta (correo) para asignar.</summary>
    public string MiNombre { get; private set; } = string.Empty;
    public string MiCuenta { get; private set; } = string.Empty;

    private AzureDevOps(TokenCredential credencial, Configuracion config)
    {
        this.credencial = credencial;
        this.config = config;
    }

    private string Org => $"https://dev.azure.com/{Uri.EscapeDataString(config.Organizacion)}";
    private string Proy => $"{Org}/{Uri.EscapeDataString(config.Proyecto)}";

    /// <summary>
    /// Inicia sesión en el tenant configurado. La primera vez abre el navegador; después reutiliza la sesión guardada
    /// (cifrada por Windows) hasta que venza. "--codigo" usa código de dispositivo; "--cli" usa la sesión de Azure CLI.
    /// </summary>
    public static async Task<AzureDevOps> ConectarAsync(Configuracion config, string[] args)
    {
        TokenCredential credencial;
        if (args.Contains("--cli"))
        {
            credencial = new AzureCliCredential(new AzureCliCredentialOptions { TenantId = config.TenantId });
        }
        else
        {
            var registro = Path.Combine(Configuracion.Carpeta, $"sesion-{config.TenantId}.json");
            var cache = new TokenCachePersistenceOptions { Name = "devops-diario" };
            AuthenticationRecord? guardado = null;
            if (File.Exists(registro))
            {
                await using var leer = File.OpenRead(registro);
                guardado = await AuthenticationRecord.DeserializeAsync(leer);
            }

            var contexto = new TokenRequestContext([Scope]);
            Func<Task<AuthenticationRecord>> iniciarSesion;
            if (args.Contains("--codigo"))
            {
                var porCodigo = new DeviceCodeCredential(new DeviceCodeCredentialOptions
                {
                    TenantId = config.TenantId, TokenCachePersistenceOptions = cache, AuthenticationRecord = guardado,
                    DeviceCodeCallback = (codigo, _) => { Console.WriteLine(codigo.Message); return Task.CompletedTask; },
                });
                credencial = porCodigo;
                iniciarSesion = () => porCodigo.AuthenticateAsync(contexto);
            }
            else
            {
                var navegador = new InteractiveBrowserCredential(new InteractiveBrowserCredentialOptions
                {
                    TenantId = config.TenantId, TokenCachePersistenceOptions = cache, AuthenticationRecord = guardado,
                });
                credencial = navegador;
                iniciarSesion = () => navegador.AuthenticateAsync(contexto);
            }
            if (guardado is null)
            {
                Console.WriteLine("Inicie sesión con su cuenta de Microsoft…");
                var nuevo = await iniciarSesion();
                Directory.CreateDirectory(Configuracion.Carpeta);
                await using var escribir = File.Create(registro);
                await nuevo.SerializeAsync(escribir);
            }
        }
        return new AzureDevOps(credencial, config);
    }

    // ---------------------------------------------------------------------------------------------------------- datos

    /// <summary>Organizaciones de Azure DevOps del usuario en este tenant.</summary>
    public async Task<List<string>> OrganizacionesAsync()
    {
        var perfil = await GetAsync("https://app.vssps.visualstudio.com/_apis/profile/profiles/me?" + Api);
        var id = perfil?["id"]?.GetValue<string>();
        var cuentas = await GetAsync($"https://app.vssps.visualstudio.com/_apis/accounts?memberId={id}&{Api}");
        return Nombres(cuentas, "accountName");
    }

    public async Task<List<string>> ProyectosAsync() => Nombres(await GetAsync($"{Org}/_apis/projects?$top=500&{Api}"), "name");

    public async Task<List<string>> EquiposAsync() =>
        Nombres(await GetAsync($"{Org}/_apis/projects/{Uri.EscapeDataString(config.Proyecto)}/teams?$top=500&{Api}"), "name");

    /// <summary>Quién está conectado en la organización (para "asignado a mí" y para asignar las tareas).</summary>
    public async Task CargarUsuarioAsync()
    {
        var datos = await GetAsync($"{Org}/_apis/connectionData");
        var usuario = datos?["authenticatedUser"];
        MiNombre = usuario?["providerDisplayName"]?.GetValue<string>() ?? string.Empty;
        MiCuenta = usuario?["properties"]?["Account"]?["$value"]?.GetValue<string>() ?? string.Empty;
    }

    public async Task<Sprint?> SprintActualAsync()
    {
        var datos = await GetAsync($"{Proy}/{Uri.EscapeDataString(config.Equipo)}/_apis/work/teamsettings/iterations?$timeframe=current&{Api}");
        var s = datos?["value"]?.AsArray().FirstOrDefault();
        if (s is null)
        {
            return null;
        }
        return new Sprint(s["name"]!.GetValue<string>(), s["path"]!.GetValue<string>(),
            Fecha(s["attributes"]?["startDate"]), Fecha(s["attributes"]?["finishDate"]));
    }

    /// <summary>Ids que devuelve una consulta WIQL del proyecto.</summary>
    public async Task<List<int>> ConsultarAsync(string wiql)
    {
        var cuerpo = new JsonObject { ["query"] = wiql }.ToJsonString();
        var datos = await EnviarAsync(HttpMethod.Post, $"{Proy}/_apis/wit/wiql?{Api}", cuerpo, "application/json");
        return datos?["workItems"]?.AsArray().Select(w => w!["id"]!.GetValue<int>()).ToList() ?? [];
    }

    public async Task<List<Elemento>> ElementosAsync(IEnumerable<int> ids)
    {
        var lista = new List<Elemento>();
        foreach (var grupo in ids.Distinct().Chunk(200))
        {
            var datos = await GetAsync($"{Org}/_apis/wit/workitems?ids={string.Join(',', grupo)}&fields={string.Join(',', Campos)}&{Api}");
            foreach (var w in datos?["value"]?.AsArray() ?? [])
            {
                var f = w!["fields"]!;
                lista.Add(new Elemento(
                    w["id"]!.GetValue<int>(),
                    f["System.WorkItemType"]?.GetValue<string>() ?? string.Empty,
                    f["System.Title"]?.GetValue<string>() ?? string.Empty,
                    f["System.State"]?.GetValue<string>() ?? string.Empty,
                    f["System.AssignedTo"]?["uniqueName"]?.GetValue<string>(),
                    f["System.IterationPath"]?.GetValue<string>() ?? string.Empty,
                    f["System.AreaPath"]?.GetValue<string>() ?? string.Empty));
            }
        }
        return lista.OrderBy(e => e.Id).ToList();
    }

    /// <summary>Hijos directos de un work item (sus tareas).</summary>
    public async Task<List<Elemento>> HijosAsync(int id)
    {
        var datos = await GetAsync($"{Org}/_apis/wit/workitems/{id}?$expand=relations&{Api}");
        var ids = (datos?["relations"]?.AsArray() ?? [])
            .Where(r => r?["rel"]?.GetValue<string>() == "System.LinkTypes.Hierarchy-Forward")
            .Select(r => int.Parse(r!["url"]!.GetValue<string>().Split('/').Last()))
            .ToList();
        return ids.Count == 0 ? [] : await ElementosAsync(ids);
    }

    /// <summary>
    /// Campo donde van las horas de una tarea: el de la variable DEVOPS_DIARIO_CAMPO_HORAS o, si no está, el primero que
    /// tenga el tipo Task de este proceso entre Completed Work (Agile, CMMI) y Remaining Work (Scrum). Null: ninguno.
    /// </summary>
    public async Task<(string Campo, string Nombre)?> CampoHorasAsync(string? preferido)
    {
        var campos = (await GetAsync($"{Proy}/_apis/wit/workitemtypes/Task/fields?{Api}"))?["value"]?.AsArray() ?? [];
        var disponibles = campos.Where(c => c is not null)
            .ToDictionary(c => c!["referenceName"]!.GetValue<string>(), c => c!["name"]!.GetValue<string>(), StringComparer.OrdinalIgnoreCase);
        string[] candidatos = preferido is null
            ? ["Microsoft.VSTS.Scheduling.CompletedWork", "Microsoft.VSTS.Scheduling.RemainingWork"]
            : [preferido];
        foreach (var campo in candidatos)
        {
            if (disponibles.TryGetValue(campo, out var nombre))
            {
                return (campo, nombre);
            }
        }
        return null;
    }

    /// <summary>
    /// Crea una tarea hija del work item, asignada al usuario, en el mismo sprint y área que el padre, con sus horas en
    /// el campo indicado (sin campo, sin horas).
    /// </summary>
    public async Task<int> CrearTareaAsync(Elemento padre, string titulo, decimal horas, string? campoHoras)
    {
        var parche = new JsonArray
        {
            Campo("System.Title", titulo),
            Campo("System.AssignedTo", MiCuenta),
            Campo("System.IterationPath", padre.Iteracion),
            Campo("System.AreaPath", padre.Area),
            new JsonObject
            {
                ["op"] = "add", ["path"] = "/relations/-",
                ["value"] = new JsonObject { ["rel"] = "System.LinkTypes.Hierarchy-Reverse", ["url"] = $"{Org}/_apis/wit/workItems/{padre.Id}" },
            },
        };
        if (campoHoras is not null && horas > 0)
        {
            parche.Add(new JsonObject { ["op"] = "add", ["path"] = $"/fields/{campoHoras}", ["value"] = horas });
        }
        var datos = await EnviarAsync(HttpMethod.Post, $"{Proy}/_apis/wit/workitems/$Task?{Api}", parche.ToJsonString(), "application/json-patch+json");
        return datos!["id"]!.GetValue<int>();
    }

    /// <summary>
    /// Crea un PBI (el tipo de requerimiento del proceso: Product Backlog Item, User Story…) en el sprint, en el área por
    /// defecto del equipo, asignado al usuario y en el estado indicado. Devuelve el PBI creado.
    /// </summary>
    public async Task<Elemento> CrearPbiAsync(string titulo, Sprint sprint, string estado)
    {
        var categoria = await GetAsync($"{Proy}/_apis/wit/workitemtypecategories/Microsoft.RequirementCategory?{Api}");
        var tipo = categoria?["defaultWorkItemType"]?["name"]?.GetValue<string>()
            ?? throw new InvalidOperationException("No encontré el tipo de PBI del proceso.");
        var area = (await GetAsync($"{Proy}/{Uri.EscapeDataString(config.Equipo)}/_apis/work/teamsettings/teamfieldvalues?{Api}"))
            ?["defaultValue"]?.GetValue<string>() ?? config.Proyecto;
        var parche = new JsonArray
        {
            Campo("System.Title", titulo),
            Campo("System.AssignedTo", MiCuenta),
            Campo("System.IterationPath", sprint.Ruta),
            Campo("System.AreaPath", area),
            Campo("System.State", estado),
        };
        var datos = await EnviarAsync(HttpMethod.Post, $"{Proy}/_apis/wit/workitems/${Uri.EscapeDataString(tipo)}?{Api}",
            parche.ToJsonString(), "application/json-patch+json");
        var id = datos!["id"]!.GetValue<int>();
        return (await ElementosAsync([id])).Single();
    }

    /// <summary>Texto seguro dentro de una consulta WIQL.</summary>
    public static string Wiql(string texto) => texto.Replace("'", "''");

    // ---------------------------------------------------------------------------------------------------------- http

    private static JsonObject Campo(string campo, string valor) => new() { ["op"] = "add", ["path"] = $"/fields/{campo}", ["value"] = valor };

    private static List<string> Nombres(JsonNode? datos, string campo) =>
        (datos?["value"]?.AsArray() ?? []).Select(v => v![campo]!.GetValue<string>()).Order(StringComparer.OrdinalIgnoreCase).ToList();

    private static DateTime? Fecha(JsonNode? valor) => valor is null ? null : DateTime.Parse(valor.GetValue<string>()[..10]);

    private Task<JsonNode?> GetAsync(string url) => EnviarAsync(HttpMethod.Get, url, null, null);

    private async Task<JsonNode?> EnviarAsync(HttpMethod metodo, string url, string? cuerpo, string? tipo)
    {
        var token = await credencial.GetTokenAsync(new TokenRequestContext([Scope]), CancellationToken.None);
        using var solicitud = new HttpRequestMessage(metodo, url);
        solicitud.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        if (cuerpo is not null)
        {
            solicitud.Content = new StringContent(cuerpo, Encoding.UTF8);
            solicitud.Content.Headers.ContentType = new MediaTypeHeaderValue(tipo!);
        }
        using var respuesta = await http.SendAsync(solicitud);
        var texto = await respuesta.Content.ReadAsStringAsync();
        var esJson = respuesta.Content.Headers.ContentType?.MediaType?.Contains("json") == true;
        if (respuesta.IsSuccessStatusCode && esJson)
        {
            return texto.Length == 0 ? null : JsonNode.Parse(texto);
        }
        string? motivo = null;
        if (esJson)
        {
            try { motivo = JsonNode.Parse(texto)?["message"]?.GetValue<string>(); } catch (System.Text.Json.JsonException) { }
        }
        throw new InvalidOperationException((int)respuesta.StatusCode switch
        {
            401 or 403 or 203 => "Azure DevOps no aceptó su sesión o no tiene permiso en esa organización.",
            404 => $"No se encontró en Azure DevOps: {motivo ?? new Uri(url).AbsolutePath}",
            var codigo => $"Azure DevOps respondió {codigo}. {motivo}".Trim(),
        });
    }
}
