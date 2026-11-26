# Arranca el entorno local de iTop: MySQL 8.0.34 (puerto 3307) y Apache con PHP 8.2.26 (http://localhost:8090).
# Todo vive dentro de esta carpeta; no toca XAMPP ni otros servicios.
$root = $PSScriptRoot
$mysql = Join-Path $root 'entorno\mysql\bin\mysqld.exe'
$ini = Join-Path $root 'entorno\my.ini'
$httpdConf = Join-Path $root 'entorno\apache\httpd.conf'
# El PHP de esta carpeta va primero en el PATH: si no, Apache carga las DLL de C:\xampp\php (otra versión de PHP).
$env:PATH = (Join-Path $root 'entorno\php') + ';' + (($env:PATH -split ';' | Where-Object { $_ -notlike '*xampp\php*' }) -join ';')

if (-not (Get-NetTCPConnection -LocalPort 3307 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $mysql -ArgumentList "--defaults-file=`"$ini`"" -WindowStyle Hidden
    Write-Host 'MySQL 8.0.34 iniciando en 127.0.0.1:3307…'
}
if (-not (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath 'C:\xampp\apache\bin\httpd.exe' -ArgumentList "-f `"$httpdConf`"" -WindowStyle Hidden
    Write-Host 'Apache + PHP 8.2.26 iniciando en http://localhost:8090 …'
}
Start-Sleep -Seconds 3
Write-Host 'Listo: http://localhost:8090'
