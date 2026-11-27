namespace DevOpsDiario;

/// <summary>
/// Lo que se ajusta. El tenant y el prefijo vienen de variables de entorno (globales de Windows o
/// Properties/launchSettings.json); lo demás se cambia aquí.
/// </summary>
public static class Reglas
{
    /// <summary>Tenant de Microsoft Entra ID donde está Azure DevOps. Variable: DEVOPS_DIARIO_TENANT_ID.</summary>
    public static string TenantId => Variable("DEVOPS_DIARIO_TENANT_ID") ?? string.Empty;

    /// <summary>
    /// Prefijo que llevan las tareas de los PBI en Committed (no los PBI: a todos se les crea su tarea).
    /// Variable: DEVOPS_DIARIO_PREFIJO (también se acepta el nombre viejo DEVOPS_DIARIO_PREFIJO_PBI).
    /// </summary>
    public static string Prefijo => Variable("DEVOPS_DIARIO_PREFIJO") ?? Variable("DEVOPS_DIARIO_PREFIJO_PBI") ?? string.Empty;

    /// <summary>
    /// Título de la tarea de un PBI en Committed, con {fecha}, {prefijo} y {pbi} (el título del PBI).
    /// Variable: DEVOPS_DIARIO_FORMATO_TAREA. Sin ella: "{fecha} {prefijo} Se trabaja en {pbi}".
    /// </summary>
    public static string FormatoTareaPbi => Variable("DEVOPS_DIARIO_FORMATO_TAREA") ?? "{fecha} {prefijo} Se trabaja en {pbi}";

    /// <summary>
    /// Campo de horas de las tareas (nombre de referencia). Variable: DEVOPS_DIARIO_CAMPO_HORAS. Sin ella se usa el
    /// que tenga el proceso: Completed Work o, si no existe (Scrum), Remaining Work.
    /// </summary>
    public static string? CampoHoras => Variable("DEVOPS_DIARIO_CAMPO_HORAS");

    /// <summary>Horas de un día: la tarea del Daily más las de los PBI suman esto.</summary>
    public const decimal HorasDia = 7.50m;

    /// <summary>Horas de la tarea del Daily.</summary>
    public const decimal HorasDaily = 0.25m;

    /// <summary>Con hasta este número de tareas de PBI en un día, las horas se reparten solas; con más, se preguntan.</summary>
    public const int RepartoAutomaticoHasta = 2;

    /// <summary>Las horas que se reparten solas se redondean a este bloque (un cuarto de hora).</summary>
    public const decimal BloqueHoras = 0.25m;

    /// <summary>Opcionales: si se definen, no se pregunta organización, proyecto ni equipo.</summary>
    public static string? Organizacion => Variable("DEVOPS_DIARIO_ORGANIZACION");
    public static string? Proyecto => Variable("DEVOPS_DIARIO_PROYECTO");
    public static string? Equipo => Variable("DEVOPS_DIARIO_EQUIPO");

    /// <summary>Formato de la fecha en los títulos (26/11/2026).</summary>
    public const string FormatoFecha = "dd/MM/yyyy";

    /// <summary>Título exacto del PBI del sprint donde va la tarea diaria de cada persona.</summary>
    public const string TituloPbiDaily = "Daily";

    /// <summary>Estado de los PBI que reciben tarea.</summary>
    public const string EstadoPbi = "Committed";

    /// <summary>true = solo los PBI asignados a usted; false = todos los PBI del sprint en ese estado.</summary>
    public const bool SoloPbiAsignadosAMi = true;

    /// <summary>Título de la tarea en el PBI Daily.</summary>
    public static string TituloTareaDaily(string fecha) => $"{fecha} Daily";

    /// <summary>
    /// En la ventana el título es fecha + prefijo + título del PBI, con el prefijo editable. Este es el que propone:
    /// lo que hay en FormatoTareaPbi entre la fecha y el PBI (sin variables, "HU… Se trabaja en").
    /// </summary>
    public static string PrefijoEditable =>
        string.Join(' ', FormatoTareaPbi.Replace("{fecha}", " ").Replace("{pbi}", " ").Replace("{prefijo}", Prefijo)
            .Split(' ', StringSplitOptions.RemoveEmptyEntries));

    /// <summary>Título de una tarea armado en la ventana: fecha + prefijo + título del PBI.</summary>
    public static string TituloConPrefijo(string fecha, string prefijo, string tituloPbi) =>
        string.Join(' ', $"{fecha} {prefijo} {tituloPbi}".Split(' ', StringSplitOptions.RemoveEmptyEntries));

    /// <summary>Título de la tarea en un PBI en Committed, según FormatoTareaPbi (sin espacios dobles si no hay prefijo).</summary>
    public static string TituloTareaPbi(string fecha, string tituloPbi) =>
        string.Join(' ', FormatoTareaPbi.Replace("{fecha}", fecha).Replace("{prefijo}", Prefijo).Replace("{pbi}", tituloPbi.Trim())
            .Split(' ', StringSplitOptions.RemoveEmptyEntries));

    /// <summary>Valor de la variable, o null si no está o está vacía.</summary>
    private static string? Variable(string nombre) =>
        Environment.GetEnvironmentVariable(nombre) is { Length: > 0 } valor && !valor.StartsWith('<') ? valor.Trim() : null;
}
