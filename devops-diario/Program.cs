using System.Globalization;
using DevOpsDiario;

// Consola de Azure DevOps para el día a día:
//   1. Mis IDs de hoy: work items asignados a usted con la fecha de hoy en el título.
//   2. Crear IDs del día: su tarea en el PBI "Daily" y una tarea por cada PBI en Committed (ayer, hoy o ambos),
//      sin duplicar, mostrando todo antes de crear.
// Uso: dotnet run            (inicia sesión con Microsoft en el navegador)
//      dotnet run -- --codigo (sin navegador: código de dispositivo)
//      dotnet run -- --cli    (usa la sesión de "az login")

Console.OutputEncoding = System.Text.Encoding.UTF8;
var config = Configuracion.Cargar();

try
{
    // El tenant (y, si se definen, organización, proyecto y equipo) vienen de variables de entorno: ver Reglas.cs.
    config.TenantId = Reglas.TenantId;
    if (!Guid.TryParse(config.TenantId, out _))
    {
        Error("Falta la variable DEVOPS_DIARIO_TENANT_ID con el tenant ID de Microsoft Entra donde está su Azure DevOps.");
        Console.WriteLine("Defínala una vez (variable global de Windows) y abra otra consola:");
        Console.WriteLine("  setx DEVOPS_DIARIO_TENANT_ID \"<tenant id>\"");
        Console.WriteLine("o en Properties\\launchSettings.json (copie launchSettings.example.json).");
        return 1;
    }
    config.Organizacion = Reglas.Organizacion ?? config.Organizacion;
    config.Proyecto = Reglas.Proyecto ?? config.Proyecto;
    config.Equipo = Reglas.Equipo ?? config.Equipo;

    var devops = await AzureDevOps.ConectarAsync(config, args);
    if (string.IsNullOrEmpty(config.Organizacion) || string.IsNullOrEmpty(config.Proyecto) || string.IsNullOrEmpty(config.Equipo))
    {
        await ElegirDatosAsync(devops, config);
    }
    await devops.CargarUsuarioAsync();

    while (true)
    {
        Console.WriteLine();
        Console.WriteLine($"Azure DevOps — {config.Organizacion} / {config.Proyecto} / {config.Equipo} — {devops.MiNombre}");
        Console.WriteLine($"  1. Mis IDs de hoy ({Texto(DateTime.Today)})");
        Console.WriteLine("  2. Crear IDs del día (Daily + PBI en " + Reglas.EstadoPbi + ")");
        Console.WriteLine("  3. Cambiar organización, proyecto o equipo");
        Console.WriteLine("  0. Salir");
        var opcion = Preguntar("Opción");
        try
        {
            switch (opcion)
            {
                case "1": await MisIdsAsync(devops); break;
                case "2": await CrearIdsAsync(devops); break;
                case "3": await ElegirDatosAsync(devops, config); await devops.CargarUsuarioAsync(); break;
                case "0": return 0;
                default: Console.WriteLine("Opción no válida."); break;
            }
        }
        catch (InvalidOperationException error)
        {
            Error(error.Message);
        }
    }
}
catch (EndOfStreamException)
{
    return 0;
}
catch (Exception error) when (error is InvalidOperationException or Azure.Identity.AuthenticationFailedException)
{
    Error(error.Message);
    return 1;
}

// ------------------------------------------------------------------------------------------------------ opción 1

static async Task MisIdsAsync(AzureDevOps devops)
{
    var fecha = Preguntar($"Fecha [{Texto(DateTime.Today)}]");
    if (fecha.Length == 0)
    {
        fecha = Texto(DateTime.Today);
    }
    var ids = await devops.ConsultarAsync(
        "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.AssignedTo] = @Me " +
        $"AND [System.Title] CONTAINS '{AzureDevOps.Wiql(fecha)}' AND [System.State] <> 'Removed' ORDER BY [System.Id]");
    var elementos = await devops.ElementosAsync(ids);
    if (elementos.Count == 0)
    {
        Console.WriteLine($"No tiene IDs con la fecha {fecha}.");
        return;
    }
    Console.WriteLine();
    foreach (var e in elementos)
    {
        Console.WriteLine($"  {e.Id,-8} {e.Tipo,-22} {e.Estado,-12} {e.Titulo}");
    }
    Console.WriteLine();
    Console.WriteLine($"IDs ({elementos.Count}): {string.Join(", ", elementos.Select(e => e.Id))}");
}

// ------------------------------------------------------------------------------------------------------ opción 2

static async Task CrearIdsAsync(AzureDevOps devops)
{
    var hoy = DateTime.Today;
    var ayer = DiaHabilAnterior(hoy);
    Console.WriteLine($"  1. Ayer ({Texto(ayer)})");
    Console.WriteLine($"  2. Hoy ({Texto(hoy)})");
    Console.WriteLine("  3. Ayer y hoy");
    List<DateTime> fechas = Preguntar("¿Para qué día?") switch
    {
        "1" => [ayer],
        "2" => [hoy],
        "3" => [ayer, hoy],
        _ => [],
    };
    if (fechas.Count == 0)
    {
        Console.WriteLine("Opción no válida.");
        return;
    }

    var sprint = await devops.SprintActualAsync()
        ?? throw new InvalidOperationException("El equipo no tiene un sprint vigente hoy: no hay dónde buscar el Daily ni los PBI.");
    Console.WriteLine($"Sprint: {sprint.Nombre}");
    var enSprint = $"[System.TeamProject] = @project AND [System.IterationPath] = '{AzureDevOps.Wiql(sprint.Ruta)}' AND [System.State] <> 'Removed'";

    var aCrear = new List<(DateTime Fecha, Elemento Padre, string Titulo)>();
    var yaExisten = new List<string>();

    // Daily: una tarea suya por día dentro del PBI "Daily" del sprint.
    var daily = (await devops.ElementosAsync(await devops.ConsultarAsync(
        $"SELECT [System.Id] FROM WorkItems WHERE {enSprint} AND [System.Title] = '{AzureDevOps.Wiql(Reglas.TituloPbiDaily)}' " +
        "AND [System.WorkItemType] <> 'Task' ORDER BY [System.Id]"))).FirstOrDefault();
    if (daily is null)
    {
        Aviso($"No encontré el PBI \"{Reglas.TituloPbiDaily}\" en {sprint.Nombre}: no se crea la tarea del Daily.");
    }
    else
    {
        Planear(devops, daily, await devops.HijosAsync(daily.Id), fechas, Reglas.TituloTareaDaily, aCrear, yaExisten);
    }

    // PBI en Committed: una tarea por día en los que tienen el formato; los demás se muestran como omitidos.
    var pbis = await devops.ElementosAsync(await devops.ConsultarAsync(
        $"SELECT [System.Id] FROM WorkItems WHERE {enSprint} AND [System.WorkItemType] IN GROUP 'Microsoft.RequirementCategory' " +
        $"AND [System.State] = '{AzureDevOps.Wiql(Reglas.EstadoPbi)}' AND [System.Title] <> '{AzureDevOps.Wiql(Reglas.TituloPbiDaily)}'" +
        (Reglas.SoloPbiAsignadosAMi ? " AND [System.AssignedTo] = @Me" : string.Empty) + " ORDER BY [System.Id]"));
    var omitidos = pbis.Where(p => !Reglas.TieneFormato(p.Titulo)).ToList();
    foreach (var pbi in pbis.Where(p => Reglas.TieneFormato(p.Titulo)))
    {
        Planear(devops, pbi, await devops.HijosAsync(pbi.Id), fechas, f => Reglas.TituloTareaPbi(f, pbi.Titulo), aCrear, yaExisten);
    }

    // Revisión antes de crear.
    Console.WriteLine();
    if (yaExisten.Count > 0)
    {
        Console.WriteLine($"Ya existen (no se crean): {yaExisten.Count}");
        yaExisten.ForEach(y => Console.WriteLine($"  = {y}"));
    }
    if (omitidos.Count > 0)
    {
        Console.WriteLine($"PBI en {Reglas.EstadoPbi} sin el formato \"{Reglas.PrefijoPbi}\" (no se les crea nada): {omitidos.Count}");
        omitidos.ForEach(o => Console.WriteLine($"  - {o.Id} {o.Titulo}"));
    }
    if (aCrear.Count == 0)
    {
        Console.WriteLine("No hay nada que crear: todo está al día.");
        return;
    }
    Console.WriteLine($"Se van a crear {aCrear.Count} tarea(s), asignadas a {devops.MiNombre}:");
    foreach (var (_, padre, titulo) in aCrear)
    {
        Console.WriteLine($"  + en {padre.Id,-8} {titulo}");
    }
    if (!Preguntar("¿Crear? (s/n)").Equals("s", StringComparison.OrdinalIgnoreCase))
    {
        Console.WriteLine("No se creó nada.");
        return;
    }

    var creados = new List<int>();
    foreach (var (_, padre, titulo) in aCrear)
    {
        var id = await devops.CrearTareaAsync(padre, titulo);
        creados.Add(id);
        Console.WriteLine($"  ✓ {id} {titulo}");
    }
    Console.WriteLine($"Creados ({creados.Count}): {string.Join(", ", creados)}");
}

/// <summary>Para cada fecha: si el padre ya tiene una tarea suya con esa fecha, se anota como existente; si no, se planea.</summary>
static void Planear(AzureDevOps devops, Elemento padre, List<Elemento> hijos, List<DateTime> fechas, Func<string, string> titulo,
    List<(DateTime, Elemento, string)> aCrear, List<string> yaExisten)
{
    foreach (var fecha in fechas)
    {
        var texto = Texto(fecha);
        var existente = hijos.FirstOrDefault(h => h.Titulo.Contains(texto, StringComparison.Ordinal)
            && string.Equals(h.AsignadoA, devops.MiCuenta, StringComparison.OrdinalIgnoreCase));
        if (existente is not null)
        {
            yaExisten.Add($"{existente.Id} {existente.Titulo}");
        }
        else
        {
            aCrear.Add((fecha, padre, titulo(texto)));
        }
    }
}

// ------------------------------------------------------------------------------------------------------ datos

static async Task ElegirDatosAsync(AzureDevOps devops, Configuracion config)
{
    config.Organizacion = Elegir("Organización", await devops.OrganizacionesAsync());
    config.Proyecto = Elegir("Proyecto", await devops.ProyectosAsync());
    config.Equipo = Elegir("Equipo", await devops.EquiposAsync());
    config.Guardar();
}

static string Elegir(string que, List<string> opciones)
{
    if (opciones.Count == 0)
    {
        throw new InvalidOperationException($"Su cuenta no tiene ningún(a) {que.ToLowerInvariant()} en este tenant.");
    }
    if (opciones.Count == 1)
    {
        Console.WriteLine($"{que}: {opciones[0]}");
        return opciones[0];
    }
    Console.WriteLine($"{que}:");
    for (var i = 0; i < opciones.Count; i++)
    {
        Console.WriteLine($"  {i + 1}. {opciones[i]}");
    }
    while (true)
    {
        if (int.TryParse(Preguntar("Número"), out var n) && n >= 1 && n <= opciones.Count)
        {
            return opciones[n - 1];
        }
    }
}

// ------------------------------------------------------------------------------------------------------ utilidades

static string Texto(DateTime fecha) => fecha.ToString(Reglas.FormatoFecha, CultureInfo.InvariantCulture);

/// <summary>"Ayer" es el día hábil anterior: un lunes, el viernes.</summary>
static DateTime DiaHabilAnterior(DateTime dia)
{
    var anterior = dia.AddDays(-1);
    while (anterior.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday)
    {
        anterior = anterior.AddDays(-1);
    }
    return anterior;
}

static string Preguntar(string texto)
{
    Console.Write($"{texto}: ");
    // Sin más entrada (ventana cerrada o entrada redirigida que se acabó): se termina.
    return (Console.ReadLine() ?? throw new EndOfStreamException()).Trim();
}

static void Aviso(string texto)
{
    Console.ForegroundColor = ConsoleColor.Yellow;
    Console.WriteLine(texto);
    Console.ResetColor();
}

static void Error(string texto)
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine(texto);
    Console.ResetColor();
}
