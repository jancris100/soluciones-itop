# Ejecuta una vez las tareas de fondo de iTop (webservices/cron.php): notificaciones, SLA de tickets, limpieza, etc.
# En producción se programa cada 5 minutos. Aquí se corre a mano o con el Programador de tareas de Windows.
$root = $PSScriptRoot
$env:PATH = (Join-Path $root 'entorno\php') + ';' + $env:PATH
$credenciales = Get-Content (Join-Path $root 'entorno\credenciales.local.env') |
    Where-Object { $_ -match '^[A-Z_]+=' } |
    ForEach-Object { $k, $v = $_ -split '=', 2; @{ $k = $v } } |
    ForEach-Object { $_ } | ForEach-Object -Begin { $h = @{} } -Process { $h += $_ } -End { $h }
Push-Location (Join-Path $root 'itop\webservices')
try {
    & (Join-Path $root 'entorno\php\php.exe') cron.php "--auth_user=$($credenciales.ITOP_ADMIN_USER)" "--auth_pwd=$($credenciales.ITOP_ADMIN_PASSWORD)" --verbose=1
}
finally {
    Pop-Location
}
