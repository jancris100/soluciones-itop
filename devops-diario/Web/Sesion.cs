namespace DevOpsDiario;

/// <summary>Conexión a Azure DevOps de la web app: se inicia una vez y la comparten las pestañas del navegador.</summary>
public sealed class Sesion
{
    private readonly SemaphoreSlim candado = new(1, 1);

    public Configuracion Config { get; } = Configuracion.Cargar();
    public AzureDevOps? DevOps { get; private set; }

    /// <summary>Inicia sesión con Microsoft (navegador la primera vez) y carga el usuario si ya hay organización.</summary>
    public async Task ConectarAsync()
    {
        await candado.WaitAsync();
        try
        {
            Config.TenantId = Reglas.TenantId;
            if (!Guid.TryParse(Config.TenantId, out _))
            {
                throw new InvalidOperationException(
                    "Falta la variable DEVOPS_DIARIO_TENANT_ID (tenant de Microsoft Entra de su Azure DevOps). Defínala con setx y vuelva a abrir.");
            }
            Config.Organizacion = Reglas.Organizacion ?? Config.Organizacion;
            Config.Proyecto = Reglas.Proyecto ?? Config.Proyecto;
            Config.Equipo = Reglas.Equipo ?? Config.Equipo;
            DevOps ??= await AzureDevOps.ConectarAsync(Config, []);
            if (Listo && string.IsNullOrEmpty(DevOps.MiCuenta))
            {
                await DevOps.CargarUsuarioAsync();
            }
        }
        finally
        {
            candado.Release();
        }
    }

    public bool Listo => !string.IsNullOrEmpty(Config.Organizacion) && !string.IsNullOrEmpty(Config.Proyecto) && !string.IsNullOrEmpty(Config.Equipo);
}
