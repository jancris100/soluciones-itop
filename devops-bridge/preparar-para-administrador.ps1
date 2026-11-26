<#
.SYNOPSIS
  Para cuando usted NO tiene permiso de escritura sobre la Function: valida, compila y deja en la carpeta
  para-administrador/ todo lo que su administrador necesita para configurar y publicar. No cambia nada en Azure.

.DESCRIPTION
  1. Corre validar-function-existente.ps1 con los mismos datos (con -UsarPat prueba el PAT). Si algo falta, se detiene.
  2. Compila ItopDevOpsBridge y deja el paquete:  para-administrador/ItopDevOpsBridge.zip
  3. Deja la configuración DevOps__*:         para-administrador/configuracion.json   (sin el PAT)
  4. Deja las instrucciones con los comandos: para-administrador/INSTRUCCIONES.txt
  El PAT no se escribe en ningún archivo: el administrador lo agrega aparte (usted se lo da de forma segura, o lo pega
  usted en su sesión). Entregue la carpeta al administrador; cuando termine, pruebe con probar-function.ps1.

.EXAMPLE
  ./preparar-para-administrador.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> `
     -Organization <org> -Project "<proyecto>" -Team "<equipo>" -UsarPat
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
    [string] $DevOpsTenantId = '',
    [string] $DevOpsClientId = '',
    [switch] $UsarPat,
    [string[]] $ITopClasses = @('Incident')
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$datos = @{
    Subscription = $Subscription; ResourceGroup = $ResourceGroup; AppName = $AppName; Organization = $Organization
    Project = $Project; Team = $Team; WorkItemType = $WorkItemType; AreaPath = $AreaPath; Tags = $Tags
    DevOpsTenantId = $DevOpsTenantId; DevOpsClientId = $DevOpsClientId
}
if ($UsarPat) { $datos.UsarPat = $true }

Write-Host '1/4 Validación (validar-function-existente.ps1)…'
& (Join-Path $here 'validar-function-existente.ps1') @datos
if ($LASTEXITCODE -ne 0) { Write-Host ''; Write-Host 'Corrija lo que falta y vuelva a correr este script.' -ForegroundColor Red; exit 1 }

$salida = Join-Path $here 'para-administrador'
Remove-Item $salida -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $salida | Out-Null

Write-Host ''
Write-Host '2/4 Compilación…'
$publish = Join-Path $here 'publish'
Remove-Item $publish -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish (Join-Path $here 'ItopDevOpsBridge\ItopDevOpsBridge.csproj') -c Release -o $publish --nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación.' }
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath (Join-Path $salida 'ItopDevOpsBridge.zip')
Write-Host '  para-administrador\ItopDevOpsBridge.zip'

Write-Host '3/4 Configuración…'
# Mismo formato que "Edición avanzada" del portal y que acepta az (--settings @archivo).
$config = @(
    @{ name = 'DevOps__Organization'; value = $Organization; slotSetting = $false }
    @{ name = 'DevOps__Project'; value = $Project; slotSetting = $false }
    @{ name = 'DevOps__Team'; value = $Team; slotSetting = $false }
    @{ name = 'DevOps__WorkItemType'; value = $WorkItemType; slotSetting = $false }
    @{ name = 'DevOps__AreaPath'; value = $AreaPath; slotSetting = $false }
    @{ name = 'DevOps__Tags'; value = $Tags; slotSetting = $false }
    @{ name = 'DevOps__TenantId'; value = $(if ($UsarPat) { '' } else { $DevOpsTenantId }); slotSetting = $false }
    @{ name = 'DevOps__ClientId'; value = $(if ($UsarPat) { '' } else { $DevOpsClientId }); slotSetting = $false }
)
ConvertTo-Json -InputObject $config | Set-Content (Join-Path $salida 'configuracion.json') -Encoding utf8
Write-Host '  para-administrador\configuracion.json'

Write-Host '4/4 Instrucciones…'
$g = "--name $AppName --resource-group $ResourceGroup"
$clases = ($ITopClasses | ForEach-Object { "'$_'" }) -join ', '
$pasoPat = if ($UsarPat) {
@"
2. El PAT (lo da $((az account show --query user.name -o tsv 2>$null)) de forma segura; no viene en ningún archivo):
     Portal: Function › Settings › Environment variables › App settings › + Add
       Name:  DevOps__PersonalAccessToken
       Value: <el PAT>
     o por consola:
       az functionapp config appsettings set $g --settings "DevOps__PersonalAccessToken=<el PAT>" -o none
"@
} else {
@"
2. Sin PAT: la Function entra con su identidad$(if ($DevOpsClientId) { " y el registro de aplicación $DevOpsClientId" }). Si existe la configuración
   DevOps__PersonalAccessToken, bórrela.
"@
}
@"
iTop → Azure DevOps: configurar y publicar la Function $AppName
================================================================
Necesita: Website Contributor (o Contributor) sobre la Function y Azure CLI con sesión en la suscripción:
  az login
  az account set --subscription "$Subscription"

Desde esta carpeta (para-administrador):

1. Configuración DevOps__* (no borra ni cambia las demás configuraciones):
     az functionapp config appsettings set $g --settings "@configuracion.json" -o none
   o en el portal: Function › Settings › Environment variables › Advanced edit, y agregar las entradas de
   configuracion.json.

$pasoPat
3. Publicar el código:
     az functionapp deployment source config-zip $g --src ItopDevOpsBridge.zip

4. Llave de la Function (para iTop): entregarla de forma segura a quien configura iTop.
     az functionapp function keys list $g --function-name CreatePbi --query default -o tsv
   o en el portal: Function › Functions › CreatePbi › Function Keys › default.

5. Comprobar: con la Function publicada, quien la configuró corre
     ./probar-function.ps1 -Subscription "$Subscription" -ResourceGroup $ResourceGroup -AppName $AppName
   (pide la llave en pantalla): sin llave debe dar 401 y con llave, 400.

Bloque para iTop, conf/production/config-itop.php (dentro de `$MyModuleSettings):
  'itop-devops' => array(
      'function_url' => 'https://<dominio de la Function>/api/itop/pbi',
      'function_key' => '<llave del paso 4>',
      'tag_code' => 'DEVOPS',
      'tag_attcode' => 'tags',
      'classes' => array($clases),
      'timeout' => 30,
  ),
Y dentro de `$MySettings:
  'async_task_retries' => array('AsyncItopDevOps' => array('max_retries' => 6, 'retry_delay' => 300, 'exponential_delay' => true)),
"@ | Set-Content (Join-Path $salida 'INSTRUCCIONES.txt') -Encoding utf8
Write-Host '  para-administrador\INSTRUCCIONES.txt'

Write-Host ''
Write-Host "Listo. Entregue la carpeta $salida a su administrador." -ForegroundColor Green
if ($UsarPat) { Write-Host 'El PAT no está en la carpeta: déselo aparte, de forma segura (no por correo ni chat).' -ForegroundColor Yellow }
Write-Host 'Cuando publique, pruebe con probar-function.ps1.'
