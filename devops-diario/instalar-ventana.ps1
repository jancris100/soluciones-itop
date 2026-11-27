<#
.SYNOPSIS
  Compila la ventana de devops-diario como devops-diario.exe y crea un acceso directo en el escritorio.

.DESCRIPTION
  Deja la app en %LOCALAPPDATA%\devops-diario\app (fuera del repositorio) y el acceso directo "DevOps diario".
  Vuelva a correrlo después de un git pull para actualizarla. Necesita el runtime de escritorio de .NET 10 y WebView2
  (vienen con Visual Studio / Windows 11).
#>
$ErrorActionPreference = 'Stop'
$proyecto = Join-Path $PSScriptRoot 'Ventana\DevOpsDiario.Ventana.csproj'
$destino = Join-Path $env:LOCALAPPDATA 'devops-diario\app'

Get-Process devops-diario -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'Compilando la ventana…'
dotnet publish $proyecto -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $destino --nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación.' }

$exe = Join-Path $destino 'devops-diario.exe'
$acceso = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DevOps diario.lnk'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($acceso)
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = $destino
$lnk.Description = 'Tareas del día en Azure DevOps'
$lnk.Save()

Write-Host "Listo: $exe" -ForegroundColor Green
Write-Host "Acceso directo en el escritorio: DevOps diario"
