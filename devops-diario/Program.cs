using System.Globalization;
using DevOpsDiario;

// Consola de Azure DevOps para el día a día:
//   1. Mis IDs de hoy: work items asignados a usted con la fecha de hoy en el título.
//   2. Crear IDs del día: su tarea en el PBI "Daily" y una tarea por cada PBI en Committed (ayer, hoy o ambos),
//      sin duplicar, con las horas del día repartidas (7,50: Daily 0,25 y el resto en los PBI), mostrando todo antes de crear.
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

    var aCrear = new List<Tarea>();
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
        Planear(devops, daily, await devops.HijosAsync(daily.Id), fechas, Reglas.TituloTareaDaily, true, aCrear, yaExisten);
    }

    // PBI en Committed: a cada uno, una tarea por día con el formato de Reglas.TituloTareaPbi.
    var pbis = await devops.ElementosAsync(await devops.ConsultarAsync(
        $"SELECT [System.Id] FROM WorkItems WHERE {enSprint} AND [System.WorkItemType] IN GROUP 'Microsoft.RequirementCategory' " +
        $"AND [System.State] = '{AzureDevOps.Wiql(Reglas.EstadoPbi)}' AND [System.Title] <> '{AzureDevOps.Wiql(Reglas.TituloPbiDaily)}'" +
        (Reglas.SoloPbiAsignadosAMi ? " AND [System.AssignedTo] = @Me" : string.Empty) + " ORDER BY [System.Id]"));
    if (pbis.Count == 0)
    {
        Aviso($"No tiene PBI en {Reglas.EstadoPbi} en {sprint.Nombre}.");
    }
    foreach (var pbi in pbis)
    {
        Planear(devops, pbi, await devops.HijosAsync(pbi.Id), fechas, f => Reglas.TituloTareaPbi(f, pbi.Titulo), false, aCrear, yaExisten);
    }

    Console.WriteLine();
    if (yaExisten.Count > 0)
    {
        Console.WriteLine($"Ya existen (no se crean): {yaExisten.Count}");
        yaExisten.ForEach(y => Console.WriteLine($"  = {y}"));
    }
    if (aCrear.Count == 0)
    {
        Console.WriteLine("No hay nada que crear: todo está al día.");
        return;
    }

    // Horas: el Daily lleva las suyas y las tareas de PBI de cada día se reparten lo que queda de la jornada.
    var campo = await devops.CampoHorasAsync(Reglas.CampoHoras);
    if (campo is null)
    {
        Aviso("El tipo Task de este proyecto no tiene campo de horas (Completed Work ni Remaining Work): se crean sin horas.");
    }
    else
    {
        foreach (var dia in aCrear.GroupBy(t => t.Fecha))
        {
            RepartirHoras(dia.Key, dia.Where(t => t.EsDaily).ToList(), dia.Where(t => !t.EsDaily).ToList(),
                yaExisten.Any(y => y.Contains(Texto(dia.Key), StringComparison.Ordinal)));
        }
    }

    // Revisión antes de crear.
    Console.WriteLine();
    Console.WriteLine($"Se van a crear {aCrear.Count} tarea(s), asignadas a {devops.MiNombre}" + (campo is null ? ":" : $", con las horas en {campo.Value.Nombre}:"));
    foreach (var dia in aCrear.GroupBy(t => t.Fecha))
    {
        foreach (var t in dia)
        {
            Console.WriteLine($"  + en {t.Padre.Id,-8} {(campo is null ? string.Empty : Horas(t.Horas) + " h  ")}{t.Titulo}");
        }
        if (campo is not null)
        {
            Console.WriteLine($"    {Texto(dia.Key)}: {Horas(dia.Sum(t => t.Horas))} h nuevas");
        }
    }
    if (!Preguntar("¿Crear? (s/n)").Equals("s", StringComparison.OrdinalIgnoreCase))
    {
        Console.WriteLine("No se creó nada.");
        return;
    }

    var creados = new List<int>();
    foreach (var t in aCrear)
    {
        var id = await devops.CrearTareaAsync(t.Padre, t.Titulo, t.Horas, campo?.Campo);
        creados.Add(id);
        Console.WriteLine($"  ✓ {id} {t.Titulo}");
    }
    Console.WriteLine($"Creados ({creados.Count}): {string.Join(", ", creados)}");
}

/// <summary>Para cada fecha: si el padre ya tiene una tarea suya con esa fecha, se anota como existente; si no, se planea.</summary>
static void Planear(AzureDevOps devops, Elemento padre, List<Elemento> hijos, List<DateTime> fechas, Func<string, string> titulo,
    bool esDaily, List<Tarea> aCrear, List<string> yaExisten)
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
            aCrear.Add(new Tarea(fecha, padre, titulo(texto), esDaily));
        }
    }
}

/// <summary>
/// Horas de un día. El Daily lleva Reglas.HorasDaily; las tareas de PBI se reparten el resto de Reglas.HorasDia:
/// solas (en cuartos de hora) si son hasta Reglas.RepartoAutomaticoHasta, o preguntando una por una si son más o si
/// ese día ya tenía tareas (para no pasarse de la jornada).
/// </summary>
static void RepartirHoras(DateTime fecha, List<Tarea> daily, List<Tarea> pbis, bool habiaTareas)
{
    daily.ForEach(t => t.Horas = Reglas.HorasDaily);
    if (pbis.Count == 0)
    {
        return;
    }
    var disponible = Reglas.HorasDia - Reglas.HorasDaily;
    if (pbis.Count <= Reglas.RepartoAutomaticoHasta && !habiaTareas)
    {
        // Partes iguales en cuartos de hora; el sobrante de redondear va a la primera.
        var parte = Math.Floor(disponible / pbis.Count / Reglas.BloqueHoras) * Reglas.BloqueHoras;
        pbis.ForEach(t => t.Horas = parte);
        pbis[0].Horas += disponible - parte * pbis.Count;
        return;
    }

    Console.WriteLine();
    Console.WriteLine($"Horas del {Texto(fecha)}: Daily {Horas(Reglas.HorasDaily)} h; quedan {Horas(disponible)} h de {Horas(Reglas.HorasDia)} para {pbis.Count} tarea(s)." +
        (habiaTareas ? " Ese día ya tenía tareas: reste las horas que ya registró." : string.Empty));
    var usadas = 0m;
    for (var i = 0; i < pbis.Count; i++)
    {
        var quedan = disponible - usadas;
        var sugeridas = i == pbis.Count - 1 ? quedan : Math.Floor(quedan / (pbis.Count - i) / Reglas.BloqueHoras) * Reglas.BloqueHoras;
        Console.WriteLine($"  {pbis[i].Titulo}");
        while (true)
        {
            var texto = Preguntar($"    Horas [{Horas(sugeridas)}] (quedan {Horas(quedan)})");
            var horas = texto.Length == 0 ? sugeridas : LeerHoras(texto);
            if (horas is >= 0 && horas <= quedan)
            {
                pbis[i].Horas = horas.Value;
                usadas += horas.Value;
                Console.WriteLine($"    Llevan {Horas(Reglas.HorasDaily + usadas)} de {Horas(Reglas.HorasDia)} h");
                break;
            }
            Console.WriteLine($"    Escriba un número entre 0 y {Horas(quedan)} (por ejemplo 2,5).");
        }
    }
}

static decimal? LeerHoras(string texto) =>
    decimal.TryParse(texto.Replace(',', '.'), NumberStyles.Number, CultureInfo.InvariantCulture, out var horas) ? horas : null;

static string Horas(decimal horas) => horas.ToString("0.00", CultureInfo.GetCultureInfo("es-CR"));

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

/// <summary>Una tarea por crear: el día, el padre, el título, si es la del Daily y sus horas.</summary>
sealed class Tarea(DateTime fecha, Elemento padre, string titulo, bool esDaily)
{
    public DateTime Fecha { get; } = fecha;
    public Elemento Padre { get; } = padre;
    public string Titulo { get; } = titulo;
    public bool EsDaily { get; } = esDaily;
    public decimal Horas { get; set; }
}
