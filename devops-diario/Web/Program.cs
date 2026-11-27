using System.Diagnostics;
using System.Net.Sockets;
using DevOpsDiario;
using DevOpsDiario.Components;

// Web app local: solo escucha en este equipo (localhost) y abre el navegador. "--sin-navegador" no lo abre.
const string Direccion = "http://localhost:5199";

// Si ya está corriendo, solo se abre el navegador.
if (EstaCorriendo())
{
    AbrirNavegador();
    return;
}

// Sus archivos (wwwroot, blazor.web.js) se buscan junto a la app, no en la carpeta desde donde se abrió.
var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = args, ContentRootPath = AppContext.BaseDirectory });
builder.WebHost.UseUrls(Direccion);
builder.Logging.SetMinimumLevel(LogLevel.Warning);
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
builder.Services.AddSingleton<Sesion>();

var app = builder.Build();
app.UseAntiforgery();
app.MapStaticAssets();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();

if (!args.Contains("--sin-navegador"))
{
    app.Lifetime.ApplicationStarted.Register(AbrirNavegador);
}
Console.WriteLine($"DevOps diario en {Direccion} (cierre esta ventana para detenerlo).");
app.Run();

static void AbrirNavegador() => Process.Start(new ProcessStartInfo(Direccion) { UseShellExecute = true });

static bool EstaCorriendo()
{
    try
    {
        using var cliente = new TcpClient();
        return cliente.ConnectAsync("127.0.0.1", 5199).Wait(300) && cliente.Connected;
    }
    catch (AggregateException)
    {
        return false;
    }
}
