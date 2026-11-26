<#
.SYNOPSIS
  Paso 2 de 2, cuando la empresa YA creó la Azure Function: la deja lista para usar con iTop. No crea la Function,
  ni grupo de recursos, ni almacenamiento.

.DESCRIPTION
  0. Corre validar-function-existente.ps1 con los mismos datos. Si algo falta, se detiene sin cambiar nada.
  1. Identidad administrada (asignada por el sistema), si no estaba activa: con ella la Function entra a Azure DevOps
     por el tenant, sin PAT.
  2. Configuración DevOps__* (organización, proyecto, equipo, tipo de elemento, área, etiquetas). Deja vacío
     DevOps__PersonalAccessToken y no toca las demás configuraciones del administrador.
  3. Compila y publica ItopDevOpsBridge (zip).
  4. Pruebas sin crear nada en Azure DevOps:
       - sin llave, la Function responde 401;
       - con llave y un ticket vacío, responde 400 (está publicada, la llave sirve y valida los datos).
  5. Deja en salida-<app>.local.env la URL, la llave y el bloque listo para config-itop.php (la llave no se imprime).
     Revisa si la identidad ya está en Azure DevOps; si no, imprime lo que el Project Collection Administrator debe hacer.

  Se puede volver a correr: actualiza la configuración y el código.

.EXAMPLE
  # Paso 1 (no cambia nada):
  ./validar-function-existente.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> `
     -Organization MiEmpresa -Project Soporte -Team "Soporte Team"

  # Paso 2 (mismos datos):
  ./configurar-function-existente.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> `
     -Organization MiEmpresa -Project Soporte -Team "Soporte Team"
#>
param(
    [Parameter(Mandatory)] [string] $Subscription,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AppName,
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $Project,
    [Parameter(Mandatory)] [string] $Team,
    [string] $WorkItemType = 'Product Backlog Item',
    [string] $AreaPath = '',
    [string] $Tags = 'DEVOPS',
    # Solo si Azure DevOps está en OTRO tenant que la Function (ver crear-acceso-entre-tenants.ps1): el tenant de la
    # organización y el Application (client) ID del registro de aplicación que confía en la identidad de la Function.
    [string] $DevOpsTenantId = '',
    [string] $DevOpsClientId = '',
    # Alternativa al registro de aplicación: la Function entra con un token personal (PAT) de Azure DevOps. Se pide en
    # pantalla (no queda en el historial). Permiso mínimo del PAT: Work Items (Read & write).
    [switch] $UsarPat,
    [securestring] $Pat,
    # Clases de iTop que se envían (Incident; agregue UserRequest si también aplica a requerimientos).
    [string[]] $ITopClasses = @('Incident'),
    # Compatibilidad con la versión anterior del script: solo valida.
    [switch] $SoloVerificar
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
# PAT: se pide una vez y se usa solo en memoria.
if ($UsarPat -and -not $Pat) { $Pat = Read-Host 'Pegue el PAT de Azure DevOps (no se muestra)' -AsSecureString }
$patTexto = if ($Pat) { [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Pat)) } else { '' }

function Invoke-Az { az @args; if ($LASTEXITCODE -ne 0) { throw "Falló: az $($args -join ' ')" } }
$datos = @{
    Subscription = $Subscription; ResourceGroup = $ResourceGroup; AppName = $AppName; Organization = $Organization
    Project = $Project; Team = $Team; WorkItemType = $WorkItemType; AreaPath = $AreaPath; Tags = $Tags
    DevOpsTenantId = $DevOpsTenantId; DevOpsClientId = $DevOpsClientId
}
if ($Pat) { $datos.Pat = $Pat }

Write-Host '0/5 Validación (validar-function-existente.ps1)…'
& (Join-Path $here 'validar-function-existente.ps1') @datos
if ($LASTEXITCODE -ne 0) { Write-Host ''; Write-Host 'No se cambió nada. Corrija lo que falta y vuelva a correr este script.' -ForegroundColor Red; exit 1 }
if ($SoloVerificar) { exit 0 }

Write-Host ''
Write-Host '1/5 Identidad administrada…'
$principalId = az functionapp identity show --name $AppName --resource-group $ResourceGroup --query principalId -o tsv 2>$null
if ($patTexto -and -not $principalId) {
    Write-Host '  Con PAT no hace falta: se deja como está.'
} elseif (-not $principalId) {
    $principalId = az functionapp identity assign --name $AppName --resource-group $ResourceGroup --query principalId -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $principalId) { throw 'No se pudo activar la identidad administrada: pídale al administrador que la active (Identidad › Asignada por el sistema › Activado).' }
    Write-Host "  Activada. Object ID $principalId"
} else {
    Write-Host "  Ya estaba activa. Object ID $principalId"
}

Write-Host '2/5 Configuración DevOps__…'
Invoke-Az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup -o none --settings `
    "DevOps__Organization=$Organization" "DevOps__Project=$Project" "DevOps__Team=$Team" `
    "DevOps__WorkItemType=$WorkItemType" "DevOps__AreaPath=$AreaPath" "DevOps__Tags=$Tags" `
    "DevOps__TenantId=$DevOpsTenantId" "DevOps__ClientId=$DevOpsClientId"
if ($patTexto) {
    # El PAT va por un archivo temporal (no en la línea de comandos) y se borra enseguida.
    $archivo = Join-Path ([IO.Path]::GetTempPath()) "devops-pat-$([guid]::NewGuid().ToString('N')).json"
    @{ DevOps__PersonalAccessToken = $patTexto } | ConvertTo-Json | Set-Content $archivo -Encoding ascii
    try { Invoke-Az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup -o none --settings "@$archivo" }
    finally { Remove-Item $archivo -Force -ErrorAction SilentlyContinue }
    Write-Host '  PAT cargado en DevOps__PersonalAccessToken: la Function entra con él.'
} else {
    # Sin -UsarPat entra con la identidad administrada (o el registro de aplicación): un PAT que haya quedado se quita.
    $pat = az functionapp config appsettings list --name $AppName --resource-group $ResourceGroup --query "[?name=='DevOps__PersonalAccessToken'].value | [0]" -o tsv 2>$null
    if ($pat) { Invoke-Az functionapp config appsettings delete --name $AppName --resource-group $ResourceGroup --setting-names DevOps__PersonalAccessToken -o none; Write-Host '  Se quitó DevOps__PersonalAccessToken.' }
}
Write-Host "  $Organization / $Project / $Team | $WorkItemType | área $(if ($AreaPath) { $AreaPath } else { '(la del equipo)' }) | etiquetas $Tags"

Write-Host '3/5 Compilación y publicación…'
$publish = Join-Path $here 'publish'
$zip = Join-Path $here 'publish.zip'
Remove-Item $publish, $zip -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish (Join-Path $here 'ItopDevOpsBridge\ItopDevOpsBridge.csproj') -c Release -o $publish --nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación.' }
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip
Invoke-Az functionapp deployment source config-zip --name $AppName --resource-group $ResourceGroup --src $zip -o none
Write-Host '  Publicada.'

Write-Host '4/5 Pruebas (no crean nada en Azure DevOps)…'
$hostName = az functionapp show --name $AppName --resource-group $ResourceGroup --query "properties.defaultHostName || defaultHostName" -o tsv
$url = "https://$hostName/api/itop/pbi"
$key = $null
for ($i = 0; $i -lt 18 -and -not $key; $i++) {
    $key = az functionapp function keys list --name $AppName --resource-group $ResourceGroup --function-name CreatePbi --query default -o tsv 2>$null
    if (-not $key) { $key = az functionapp keys list --name $AppName --resource-group $ResourceGroup --query functionKeys.default -o tsv 2>$null }
    if (-not $key) { Start-Sleep -Seconds 10 }
}
if (-not $key) { throw 'La Function no devolvió su llave después de publicar. Revise en el portal: Funciones › CreatePbi › Claves de función.' }

function Get-Codigo([hashtable] $headers) {
    try {
        return [int](Invoke-WebRequest -Uri $url -Method Post -Body '{}' -ContentType 'application/json' -Headers $headers -UseBasicParsing -TimeoutSec 90).StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}
# Recién publicada, la Function tarda en arrancar (sobre todo en Flex Consumption): se reintenta hasta 3 minutos.
$sinLlave = 0; $conLlave = 0
for ($i = 0; $i -lt 18; $i++) {
    $sinLlave = Get-Codigo @{}
    $conLlave = Get-Codigo @{ 'x-functions-key' = $key }
    if ($sinLlave -eq 401 -and $conLlave -eq 400) { break }
    Start-Sleep -Seconds 10
}
$pruebasOk = $sinLlave -eq 401 -and $conLlave -eq 400
if ($sinLlave -eq 401) { Write-Host '  [OK]    Sin llave responde 401 (protegida).' -ForegroundColor Green }
else { Write-Host "  [FALLA] Sin llave respondió $sinLlave (se esperaba 401)." -ForegroundColor Red }
if ($conLlave -eq 400) { Write-Host '  [OK]    Con llave y un ticket vacío responde 400: ItopDevOpsBridge está publicada y la llave sirve.' -ForegroundColor Green }
else { Write-Host "  [FALLA] Con llave respondió $conLlave (se esperaba 400). Revise los registros de la Function (Log stream / Application Insights)." -ForegroundColor Red }

Write-Host '5/5 Datos para iTop…'
$clases = ($ITopClasses | ForEach-Object { "'$_'" }) -join ', '
$out = Join-Path $here "salida-$AppName.local.env"
@(
    '# Contiene la llave de la Function: guárdelo seguro y bórrelo cuando la haya copiado a iTop. No se versiona.'
    "function_url=$url"
    "function_key=$key"
    "identity_object_id=$principalId"
    ''
    '# Bloque para conf/production/config-itop.php (dentro de $MyModuleSettings):'
    "#   'itop-devops' => array("
    "#       'function_url' => '$url',"
    "#       'function_key' => '<function_key de arriba>',"
    "#       'tag_code' => 'DEVOPS',"
    "#       'tag_attcode' => 'tags',"
    "#       'classes' => array($clases),"
    "#       'timeout' => 30,"
    '#   ),'
    '# Y dentro de $MySettings:'
    "#   'async_task_retries' => array('AsyncItopDevOps' => array('max_retries' => 6, 'retry_delay' => 300, 'exponential_delay' => true)),"
) | Set-Content $out -Encoding utf8
Write-Host "  Guardados en: $out"

# ¿Ya la agregaron en Azure DevOps? (con la sesión de usted; si no tiene acceso a la organización, no se sabe). Con la
# organización en otro tenant, lo que se agrega es el registro de aplicación, con su nombre.
$nombreEnDevOps = $AppName
if ($DevOpsClientId) { $n = az ad app show --id $DevOpsClientId --query displayName -o tsv 2>$null; if ($n) { $nombreEnDevOps = $n } }
$enDevOps = $null
$tenantToken = az account show --query tenantId -o tsv
if ($DevOpsTenantId) { $tenantToken = $DevOpsTenantId }
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --tenant $tenantToken --query accessToken -o tsv 2>$null
if ($token) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ Authorization = "Bearer $token" } `
            -Uri "https://vssps.dev.azure.com/$([uri]::EscapeDataString($Organization))/_apis/identities?searchFilter=General&filterValue=$([uri]::EscapeDataString($nombreEnDevOps))&queryMembership=None&api-version=7.1"
        if ("$($r.Headers['Content-Type'])" -like '*json*') {
            $enDevOps = [bool](@(($r.Content | ConvertFrom-Json).value) | Where-Object { $_.providerDisplayName -eq $nombreEnDevOps -or $_.customDisplayName -eq $nombreEnDevOps })
        }
    } catch { }
}

Write-Host ''
if ($pruebasOk) { Write-Host "Listo. Function: $url" -ForegroundColor Green }
else { Write-Host "La Function quedó configurada y publicada, pero las pruebas no pasaron (arriba). URL: $url" -ForegroundColor Yellow }
Write-Host "Identidad administrada (Object ID): $principalId"
if ($patTexto) {
    Write-Host 'La Function entra a Azure DevOps con el PAT. Cuando venza, créelo de nuevo y vuelva a correr este script con -UsarPat.' -ForegroundColor Green
} elseif ($enDevOps -eq $true) {
    Write-Host "'$nombreEnDevOps' ya está en Azure DevOps. Confirme que tenga acceso Basic y sea Contributor del proyecto." -ForegroundColor Green
} else {
    $estado = if ($enDevOps -eq $false) { 'todavía NO está' } else { 'no pude confirmar si está' }
    Write-Host "'$nombreEnDevOps' $estado en Azure DevOps. Un Project Collection Administrator debe:" -ForegroundColor Yellow
    Write-Host "  1. Organization settings › Users › Add users: buscar '$nombreEnDevOps', acceso Basic."
    Write-Host "  2. Agregarla al proyecto '$Project' como Contributor."
}
Write-Host 'Después: copie los datos de iTop del archivo de salida a config-itop.php y pruebe con un incidente con la etiqueta DEVOPS.'
if (-not $pruebasOk) { exit 1 }
