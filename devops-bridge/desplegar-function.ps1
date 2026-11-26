<#
.SYNOPSIS
  Crea SOLO la Azure Function ItopDevOpsBridge dentro de recursos que ya existen (los que indique el administrador) y
  publica su código. No crea grupo de recursos, ni almacenamiento, ni registra proveedores.

.DESCRIPTION
  0. Verifica (sin cambiar nada): suscripción, grupo de recursos, cuenta de almacenamiento, proveedor Microsoft.Web,
     que la región admita Flex Consumption con .NET 10 y que esté el SDK de .NET 10. Con -SoloVerificar se detiene aquí.
  1. Function App (plan Flex Consumption, .NET 10 aislado) en el grupo y con el almacenamiento indicados.
     Application Insights: usa el indicado en -AppInsights; si no se indica, Azure crea uno con el nombre de la app
     (o ninguno con -SinAppInsights).
  2. Identidad administrada (asignada por el sistema) para entrar a Azure DevOps por el tenant, sin PAT.
  3. Configuración DevOps__* (organización, proyecto, equipo, tipo de elemento, área, etiquetas).
  4. Compila y publica el código.
  5. Deja la URL y la llave de la Function en salida-<app>.local.env (no se imprime la llave) e imprime el Object ID
     de la identidad, que un Project Collection Administrator agrega en Azure DevOps (acceso Basic + Contributor).

  Se puede volver a correr: si la Function ya existe no la recrea; actualiza la configuración y el código.

.EXAMPLE
  # Primero, solo verificar con los datos que dio el administrador:
  ./desplegar-function.ps1 -Subscription "<id>" -ResourceGroup rg-existente -StorageName stexistente `
     -AppName func-devops-empresa -Organization MiEmpresa -Project Soporte -Team "Soporte Team" -SoloVerificar

  # Luego crear y publicar (mismos datos, sin -SoloVerificar):
  ./desplegar-function.ps1 -Subscription "<id>" -ResourceGroup rg-existente -StorageName stexistente `
     -AppName func-devops-empresa -Organization MiEmpresa -Project Soporte -Team "Soporte Team" -AppInsights appi-existente
#>
param(
    [Parameter(Mandatory)] [string] $Subscription,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $StorageName,
    [Parameter(Mandatory)] [string] $AppName,
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $Project,
    [Parameter(Mandatory)] [string] $Team,
    # Región de la Function; vacía = la del grupo de recursos.
    [string] $Location = '',
    [string] $WorkItemType = 'Product Backlog Item',
    [string] $AreaPath = '',
    [string] $Tags = 'DEVOPS',
    # Nombre de un Application Insights existente (en el mismo grupo) para los logs.
    [string] $AppInsights = '',
    [switch] $SinAppInsights,
    [switch] $SoloVerificar
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
function Invoke-Az { az @args; if ($LASTEXITCODE -ne 0) { throw "Falló: az $($args -join ' ')" } }
$problemas = New-Object System.Collections.Generic.List[string]

Write-Host '0/5 Verificaciones (no cambian nada)…'
Invoke-Az account set --subscription $Subscription | Out-Null
Write-Host "  Suscripción: $(az account show --query name -o tsv) | tenant $(az account show --query tenantId -o tsv) | usuario $(az account show --query user.name -o tsv)"

$rgLocation = az group show --name $ResourceGroup --query location -o tsv 2>$null
if (-not $rgLocation) { $problemas.Add("El grupo de recursos '$ResourceGroup' no existe o no tengo acceso a él.") }
if (-not $Location) { $Location = $rgLocation }
Write-Host "  Grupo de recursos: $ResourceGroup ($rgLocation) | región de la Function: $Location"

if (-not (az storage account show --name $StorageName --resource-group $ResourceGroup --query name -o tsv 2>$null)) {
    $problemas.Add("La cuenta de almacenamiento '$StorageName' no existe en '$ResourceGroup' o no tengo acceso a ella.")
}

if ((az provider show --namespace Microsoft.Web --query registrationState -o tsv 2>$null) -ne 'Registered') {
    $problemas.Add("El proveedor Microsoft.Web no está registrado en la suscripción (lo registra el administrador: az provider register --namespace Microsoft.Web).")
}

if ($Location) {
    $runtimes = az functionapp list-flexconsumption-runtimes --location $Location --runtime dotnet-isolated --query "[].sku.functionAppConfigProperties.runtime.version" -o tsv 2>$null
    if (-not ($runtimes -contains '10.0')) { $problemas.Add("La región '$Location' no ofrece Flex Consumption con .NET 10 (pase otra con -Location).") }
}

if ($AppInsights -and -not (az resource show --resource-group $ResourceGroup --name $AppInsights --resource-type Microsoft.Insights/components --query name -o tsv 2>$null)) {
    $problemas.Add("El Application Insights '$AppInsights' no existe en '$ResourceGroup'.")
}

$sdk = dotnet --list-sdks 2>$null | ForEach-Object { ($_ -split ' ')[0] } | Where-Object { [int]($_.Split('.')[0]) -ge 10 } | Select-Object -Last 1
if (-not $sdk) { $problemas.Add('Falta un SDK de .NET 10 o más nuevo en esta máquina.') }

$existe = [bool](az functionapp show --name $AppName --resource-group $ResourceGroup --query name -o tsv 2>$null)
Write-Host "  Function '$AppName': $(if ($existe) { 'ya existe (se actualiza)' } else { 'no existe (se crea)' })"

# El nombre de una Function es una dirección pública (<nombre>.azurewebsites.net): debe estar libre en todo Azure.
if (-not $existe -and $rgLocation) {
    $subId = az account show --query id -o tsv
    $check = az rest --method post --url "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Web/checknameavailability?api-version=2022-03-01" `
        --body "{\`"name\`":\`"$AppName\`",\`"type\`":\`"Microsoft.Web/sites\`"}" --query "{ok:nameAvailable, motivo:message}" -o json 2>$null | ConvertFrom-Json
    if ($check -and -not $check.ok) { $problemas.Add("El nombre '$AppName' no está disponible: $($check.motivo) Elija otro con -AppName.") }
    elseif (-not $check) { Write-Host "  (No se pudo comprobar si el nombre '$AppName' está libre; se sabrá al crear.)" -ForegroundColor Yellow }
}

# Permisos de quien corre el script sobre el grupo (incluye los heredados de la suscripción y los de sus grupos).
if ($rgLocation) {
    $userType = az account show --query user.type -o tsv
    if ($userType -eq 'user') {
        $me = az ad signed-in-user show --query id -o tsv 2>$null
        $scope = "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup"
        $roles = if ($me) { az role assignment list --assignee $me --scope $scope --include-inherited --include-groups --query "[].roleDefinitionName" -o tsv 2>$null } else { @() }
        $roles = @($roles | Where-Object { $_ })
        Write-Host "  Sus roles en el grupo: $(if ($roles.Count) { ($roles | Sort-Object -Unique) -join ', ' } else { '(no se pudieron leer)' })"
        if ($roles -contains 'Owner' -or $roles -contains 'Contributor') {
            # Suficiente para crear la Function, asignarle identidad y usar el almacenamiento.
        } elseif ($roles -contains 'Website Contributor') {
            Write-Host "  Aviso: con 'Website Contributor' puede crear la Function, pero también necesita leer las llaves del almacenamiento (por ejemplo 'Storage Account Contributor' sobre '$StorageName')." -ForegroundColor Yellow
        } elseif ($roles.Count -gt 0) {
            $problemas.Add("Sus roles en '$ResourceGroup' ($($roles -join ', ')) no alcanzan para crear la Function: pida 'Contributor' del grupo al administrador.")
        } else {
            Write-Host "  Aviso: no pude leer sus roles (puede faltar permiso para consultarlos). Confirme con el administrador que tiene 'Contributor' del grupo." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  (La sesión es de una identidad de servicio: confirme que tenga 'Contributor' del grupo.)" -ForegroundColor Yellow
    }
}

if ($problemas.Count -gt 0) {
    Write-Host ''
    Write-Host 'No se puede continuar:' -ForegroundColor Red
    $problemas | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host '  Todo en orden.' -ForegroundColor Green
if ($SoloVerificar) { Write-Host 'Solo verificación: no se creó ni cambió nada.'; exit 0 }

Write-Host '1/5 Function App (Flex Consumption, .NET 10)…'
if (-not $existe) {
    $extra = @()
    if ($SinAppInsights) { $extra += '--disable-app-insights' } elseif ($AppInsights) { $extra += @('--app-insights', $AppInsights) }
    Invoke-Az functionapp create --name $AppName --resource-group $ResourceGroup --storage-account $StorageName `
        --flexconsumption-location $Location --runtime dotnet-isolated --runtime-version 10.0 @extra -o none
}

Write-Host '2/5 Identidad administrada…'
$principalId = az functionapp identity assign --name $AppName --resource-group $ResourceGroup --query principalId -o tsv
if ($LASTEXITCODE -ne 0) { throw 'No se pudo asignar la identidad administrada.' }

Write-Host '3/5 Configuración…'
Invoke-Az functionapp config appsettings set --name $AppName --resource-group $ResourceGroup -o none --settings `
    "DevOps__Organization=$Organization" "DevOps__Project=$Project" "DevOps__Team=$Team" `
    "DevOps__WorkItemType=$WorkItemType" "DevOps__AreaPath=$AreaPath" "DevOps__Tags=$Tags"

Write-Host '4/5 Compilación y publicación…'
$publish = Join-Path $here 'publish'
$zip = Join-Path $here 'publish.zip'
Remove-Item $publish, $zip -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish (Join-Path $here 'ItopDevOpsBridge\ItopDevOpsBridge.csproj') -c Release -o $publish --nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación.' }
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip
Invoke-Az functionapp deployment source config-zip --name $AppName --resource-group $ResourceGroup --src $zip -o none

Write-Host '5/5 Llave de la Function…'
$key = az functionapp function keys list --name $AppName --resource-group $ResourceGroup --function-name CreatePbi --query default -o tsv 2>$null
if (-not $key) { $key = az functionapp keys list --name $AppName --resource-group $ResourceGroup --query functionKeys.default -o tsv }
$host_ = az functionapp show --name $AppName --resource-group $ResourceGroup --query "properties.defaultHostName || defaultHostName" -o tsv
$out = Join-Path $here "salida-$AppName.local.env"
@(
    '# Valores para config-itop.php (módulo itop-devops). Contiene la llave: guárdelo seguro y bórrelo después.'
    "function_url=https://$host_/api/itop/pbi"
    "function_key=$key"
) | Set-Content $out -Encoding utf8

Write-Host ''
Write-Host "Listo. Function: https://$host_/api/itop/pbi"
Write-Host "Llave guardada en: $out"
Write-Host "Identidad administrada (Object ID para agregar en Azure DevOps): $principalId"
