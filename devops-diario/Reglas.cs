namespace DevOpsDiario;

/// <summary>
/// Lo que se ajusta a mano. Todo lo demás se descubre solo (organización, proyecto, equipo y sprint).
/// </summary>
public static class Reglas
{
    // >>> AQUÍ VA SU PREFIJO <<<
    // Solo los PBI cuyo título empieza con este texto reciben su tarea "Se trabaja en …". Los demás se muestran como
    // omitidos. Cámbielo por el prefijo de sus historias de usuario (no se distingue mayúsculas de minúsculas).
    public const string PrefijoPbi = "HU";

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
}
