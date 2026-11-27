using System.Text.Json;

namespace DevOpsDiario;

/// <summary>
/// Organización, proyecto y equipo elegidos. Se guardan en el perfil de Windows del usuario
/// (%LOCALAPPDATA%\devops-diario\config.json), nunca en el repositorio. El tenant viene de una variable de entorno.
/// </summary>
public sealed class Configuracion
{
    /// <summary>Viene de la variable DEVOPS_DIARIO_TENANT_ID; no se guarda.</summary>
    [System.Text.Json.Serialization.JsonIgnore]
    public string TenantId { get; set; } = string.Empty;
    public string Organizacion { get; set; } = string.Empty;
    public string Proyecto { get; set; } = string.Empty;
    public string Equipo { get; set; } = string.Empty;

    /// <summary>Último prefijo que usó la ventana en cada PBI (por id), para proponerlo la próxima vez.</summary>
    public Dictionary<int, string> Prefijos { get; set; } = [];

    public static string Carpeta { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "devops-diario");

    private static string Archivo => Path.Combine(Carpeta, "config.json");

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static Configuracion Cargar()
    {
        if (!File.Exists(Archivo))
        {
            return new Configuracion();
        }
        return JsonSerializer.Deserialize<Configuracion>(File.ReadAllText(Archivo)) ?? new Configuracion();
    }

    public void Guardar()
    {
        Directory.CreateDirectory(Carpeta);
        File.WriteAllText(Archivo, JsonSerializer.Serialize(this, Json));
    }
}
