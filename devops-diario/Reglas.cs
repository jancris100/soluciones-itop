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
    /// Solo los PBI cuyo título empieza con este texto reciben su tarea "Se trabaja en …"; los demás se muestran como
    /// omitidos. Variable: DEVOPS_DIARIO_PREFIJO_PBI (sin ella, "HU"). No distingue mayúsculas de minúsculas.
    /// </summary>
    public static string PrefijoPbi => Variable("DEVOPS_DIARIO_PREFIJO_PBI") ?? "HU";

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

    /// <summary>Título de la tarea en un PBI con el prefijo: la fecha, "Se trabaja en" y el título del PBI.</summary>
    public static string TituloTareaPbi(string fecha, string tituloPbi) => $"{fecha} Se trabaja en {tituloPbi}";

    /// <summary>El PBI tiene el formato que recibe tarea.</summary>
    public static bool TieneFormato(string tituloPbi) => tituloPbi.TrimStart().StartsWith(PrefijoPbi, StringComparison.OrdinalIgnoreCase);

    /// <summary>Valor de la variable, o null si no está o está vacía.</summary>
    private static string? Variable(string nombre) =>
        Environment.GetEnvironmentVariable(nombre) is { Length: > 0 } valor && !valor.StartsWith('<') ? valor.Trim() : null;
}
