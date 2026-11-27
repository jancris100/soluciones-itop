<#
.SYNOPSIS
  Instala la web app de devops-diario en esta misma carpeta (devops-diario\app, dentro de source) y crea el acceso
  directo "DevOps diario" en el escritorio.

.DESCRIPTION
  El acceso directo corre la app con dotnet (no hay un .exe propio) y abre el navegador en http://localhost:5199.
  Solo escucha en este equipo. Vuelva a correr este script después de un git pull para actualizarla.
#>
$ErrorActionPreference = 'Stop'
$destino = Join-Path $PSScriptRoot 'app'

# Si está abierta, se cierra para poder reemplazar los archivos.
Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" |
    Where-Object { $_.CommandLine -like '*devops-diario.dll*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Write-Host 'Compilando…'
dotnet publish (Join-Path $PSScriptRoot 'Web\DevOpsDiario.Web.csproj') -c Release -o $destino --nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación.' }

$dotnet = (Get-Command dotnet).Source
$acceso = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DevOps diario.lnk'
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($acceso)
$lnk.TargetPath = $dotnet
$lnk.Arguments = '"' + (Join-Path $destino 'devops-diario.dll') + '"'
$lnk.WorkingDirectory = $destino
$lnk.WindowStyle = 7   # minimizada: la ventanita negra es el servidor; ciérrela para detenerlo
$lnk.Description = 'Tareas del día en Azure DevOps (abre el navegador)'
$lnk.Save()

Write-Host "Instalada en $destino" -ForegroundColor Green
Write-Host 'Acceso directo en el escritorio: DevOps diario (abre http://localhost:5199)'
