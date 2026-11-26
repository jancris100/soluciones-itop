# Detiene el entorno local de iTop (solo los procesos de esta carpeta).
$root = $PSScriptRoot
Get-CimInstance Win32_Process -Filter "Name = 'httpd.exe' OR Name = 'mysqld.exe'" |
    Where-Object { $_.CommandLine -like "*$root*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "Detenido $($_.Name) ($($_.ProcessId))" }
