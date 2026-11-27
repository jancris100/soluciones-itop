using Microsoft.AspNetCore.Components.WebView.WindowsForms;
using Microsoft.Extensions.DependencyInjection;

namespace DevOpsDiario;

/// <summary>La ventana: un BlazorWebView con la página Inicio.razor.</summary>
public sealed class Principal : Form
{
    public Principal()
    {
        Text = "DevOps diario";
        Width = 1180;
        Height = 820;
        StartPosition = FormStartPosition.CenterScreen;

        var servicios = new ServiceCollection();
        servicios.AddWindowsFormsBlazorWebView();
        servicios.AddSingleton<Sesion>();

        var vista = new BlazorWebView
        {
            Dock = DockStyle.Fill,
            HostPage = "wwwroot/index.html",
            Services = servicios.BuildServiceProvider(),
        };
        vista.RootComponents.Add<Inicio>("#app");
        Controls.Add(vista);
    }
}
