<#
.SYNOPSIS
  Crea (o actualiza) la Azure Function KadsiBridge y publica su código. Lo mismo sirve para pruebas y para la empresa:
  solo cambian los parámetros.

.DESCRIPTION
  1. Grupo de recursos, cuenta de almacenamiento y Function App (plan Flex Consumption, .NET 10 aislado, Application Insights).
  2. Identidad administrada (asignada por el sistema) para entrar a Azure DevOps por el tenant, sin PAT.
  3. Configuración DevOps__* (organización, proyecto, equipo, tipo de elemento, etiquetas).
  4. Compila, publica y deja la llave de la Function en un archivo local (no se imprime) para config-itop.php.

  Después, una persona con rol Project Collection Administrator agrega la identidad (su "Object ID", que imprime el
  script) a la organización de Azure DevOps con acceso Basic y la suma al proyecto con permiso de crear elementos.

.EXAMPLE
  ./desplegar.ps1 -ResourceGroup rg-kadsi -Location centralus -AppName func-kadsi-empresa `
     -Organization MiEmpresa -Project Soporte -Team "Soporte Team"
#>
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $Location,
    [Parameter(Mandatory)] [string] $AppName,
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $Project,
    [Parameter(Mandatory)] [string] $Team,
    [string] $StorageName = ('st' + ($AppName -replace '[^a-z0-9]', '').ToLower()).Substring(0, [Math]::Min(24, ('st' + ($AppName -replace '[^a-z0-9]', '')).Length)),
    [string] $WorkItemType = 'Product Backlog Item',
    [string] $AreaPath = '',
    [string] $Tags = 'KADSI',
    [string] $Subscription = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
function Invoke-Az { az @args; if ($LASTEXITCODE -ne 0) { throw "Falló: az $($args -join ' ')" } }

if ($Subscription) { Invoke-Az account set --subscription $Subscription | Out-Null }
Write-Host "Suscripción: $(az account show --query name -o tsv) (tenant $(az account show --query tenantId -o tsv))"

Write-Host '0/5 Proveedores de recursos de la suscripción…'
foreach ($namespace in 'Microsoft.Web', 'Microsoft.Storage', 'Microsoft.Insights', 'Microsoft.OperationalInsights') {
    if ((az provider show --namespace $namespace --query registrationState -o tsv) -ne 'Registered') {
        Invoke-Az provider register --namespace $namespace --wait -o none
    }
}

Write-Host '1/5 Grupo de recursos y almacenamiento…'
Invoke-Az group create --name $ResourceGroup --location $Location --tags proyecto=kadsi -o none
if (-not (az storage account show --name $StorageName --resource-group $ResourceGroup --query name -o tsv 2>$null)) {
    Invoke-Az storage account create --name $StorageName --resource-group $ResourceGroup --location $Location --sku Standard_LRS `
        --min-tls-version TLS1_2 --allow-blob-public-access false -o none
}

Write-Host '2/5 Function App (Flex Consumption, .NET 10)…'
if (-not (az functionapp show --name $AppName --resource-group $ResourceGroup --query name -o tsv 2>$null)) {
    Invoke-Az functionapp create --name $AppName --resource-group $ResourceGroup --storage-account $StorageName `
        --flexconsumption-location $Location --runtime dotnet-isolated --runtime-version 10.0 -o none
}
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
dotnet publish (Join-Path $here 'KadsiBridge\KadsiBridge.csproj') -c Release -o $publish --nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación.' }
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip
Invoke-Az functionapp deployment source config-zip --name $AppName --resource-group $ResourceGroup --src $zip -o none

Write-Host '5/5 Llave de la Function…'
$key = az functionapp function keys list --name $AppName --resource-group $ResourceGroup --function-name CreatePbi --query default -o tsv 2>$null
if (-not $key) { $key = az functionapp keys list --name $AppName --resource-group $ResourceGroup --query functionKeys.default -o tsv }
$host_ = az functionapp show --name $AppName --resource-group $ResourceGroup --query "properties.defaultHostName || defaultHostName" -o tsv
$out = Join-Path $here "salida-$AppName.local.env"
@(
    '# Valores para config-itop.php (módulo kadsi-devops). Archivo local: no se versiona.'
    "function_url=https://$host_/api/kadsi/pbi"
    "function_key=$key"
) | Set-Content $out -Encoding utf8

Write-Host ''
Write-Host "Listo. Function: https://$host_/api/kadsi/pbi"
Write-Host "Llave guardada en: $out"
Write-Host "Identidad administrada (Object ID para agregar en Azure DevOps): $principalId"
