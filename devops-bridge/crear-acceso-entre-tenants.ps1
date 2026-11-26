<#
.SYNOPSIS
  Solo cuando Azure DevOps está en OTRO tenant que la Function: crea el registro de aplicación con el que la Function
  entra a ese tenant, sin contraseñas ni secretos.

.DESCRIPTION
  La identidad administrada de la Function solo vale en su propio tenant. Para llegar a Azure DevOps en otro tenant:
    1. (este script, en el tenant de la Function) Crea un registro de aplicación multitenant y le agrega una credencial
       federada que confía en la identidad administrada de la Function. No crea secretos: la Function demuestra quién
       es con su identidad y entra como esa aplicación.
    2. (un administrador del tenant de Azure DevOps) Da de alta la aplicación en su tenant, una sola vez:
         az login --tenant <tenant de Azure DevOps> --allow-no-subscriptions
         az ad sp create --id <Application ID>
    3. (un Project Collection Administrator) La agrega en Azure DevOps por su nombre: acceso Basic y Contributor del
       proyecto.
    4. Valide y configure con -DevOpsTenantId <tenant de Azure DevOps> -DevOpsClientId <Application ID>.

  Quién lo corre: alguien con sesión en el tenant de la Function que pueda crear registros de aplicación (por defecto
  cualquier usuario puede; si la empresa lo restringió, el rol Application Developer o Application Administrator) y leer
  la Function. La identidad administrada debe estar activa (Identidad › Asignada por el sistema › Activado).

  Se puede volver a correr: si el registro ya existe, lo reutiliza.

.EXAMPLE
  ./crear-acceso-entre-tenants.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> -DevOpsTenantId "<tenant>"
#>
param(
    [Parameter(Mandatory)] [string] $Subscription,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AppName,
    # Tenant de Entra ID al que está conectada la organización de Azure DevOps.
    [Parameter(Mandatory)] [string] $DevOpsTenantId,
    # Nombre del registro de aplicación: es el que se busca después en Azure DevOps.
    [string] $RegistrationName = ''
)

$ErrorActionPreference = 'Stop'
function Invoke-Az { az @args; if ($LASTEXITCODE -ne 0) { throw "Falló: az $($args -join ' ')" } }
if (-not $RegistrationName) { $RegistrationName = "devops-bridge-$AppName" }

Write-Host '1/4 Function e identidad administrada…'
Invoke-Az account set --subscription $Subscription | Out-Null
$tenant = az account show --query tenantId -o tsv
$principalId = az functionapp identity show --name $AppName --resource-group $ResourceGroup --query principalId -o tsv 2>$null
if (-not $principalId) {
    throw "La Function '$AppName' no tiene identidad administrada activa (o no la veo). Pídale al administrador: Identidad › Asignada por el sistema › Activado, y vuelva a correr."
}
Write-Host "  Function en el tenant $tenant | identidad $principalId"
if ($DevOpsTenantId -eq $tenant) { Write-Host '  Azure DevOps está en el mismo tenant: este paso no hace falta; la identidad de la Function alcanza.' -ForegroundColor Yellow; exit 0 }

Write-Host "2/4 Registro de aplicación '$RegistrationName'…"
$appId = az ad app list --display-name $RegistrationName --query "[0].appId" -o tsv 2>$null
if ($appId) {
    Write-Host "  Ya existía: $appId"
    Invoke-Az ad app update --id $appId --sign-in-audience AzureADMultipleOrgs
} else {
    $appId = az ad app create --display-name $RegistrationName --sign-in-audience AzureADMultipleOrgs --query appId -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $appId) { throw 'No se pudo crear el registro de aplicación: su usuario no tiene permiso. Pídale al administrador el rol Application Developer, o que corra este script.' }
    Write-Host "  Creado: $appId"
}

Write-Host '3/4 Credencial federada (la aplicación confía en la identidad de la Function)…'
$existe = az ad app federated-credential list --id $appId --query "[?subject=='$principalId'] | [0].name" -o tsv 2>$null
if ($existe) {
    Write-Host '  Ya estaba.'
} else {
    $archivo = Join-Path ([IO.Path]::GetTempPath()) "devops-fic-$([guid]::NewGuid().ToString('N')).json"
    @{
        name        = "function-$AppName"
        issuer      = "https://login.microsoftonline.com/$tenant/v2.0"
        subject     = $principalId
        audiences   = @('api://AzureADTokenExchange')
        description = "Identidad administrada de la Function $AppName"
    } | ConvertTo-Json | Set-Content $archivo -Encoding ascii
    try { Invoke-Az ad app federated-credential create --id $appId --parameters "@$archivo" -o none } finally { Remove-Item $archivo -ErrorAction SilentlyContinue }
    Write-Host '  Creada.'
}

Write-Host '4/4 ¿Ya está dada de alta en el tenant de Azure DevOps?'
$enDestino = $null
$token = az account get-access-token --tenant $DevOpsTenantId --resource-type ms-graph --query accessToken -o tsv 2>$null
if ($token) {
    try {
        $r = Invoke-RestMethod -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 60 `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$appId'&`$select=id"
        $enDestino = @($r.value).Count -gt 0
    } catch { }
}

Write-Host ''
Write-Host "Listo en el tenant de la Function. Application (client) ID: $appId" -ForegroundColor Green
Write-Host "Nombre (el que se busca en Azure DevOps): $RegistrationName"
Write-Host ''
if ($enDestino -eq $true) {
    Write-Host 'Ya está dada de alta en el tenant de Azure DevOps.' -ForegroundColor Green
} else {
    Write-Host "Falta: un administrador del tenant de Azure DevOps ($DevOpsTenantId) la da de alta, una sola vez:" -ForegroundColor Yellow
    Write-Host "  az login --tenant $DevOpsTenantId --allow-no-subscriptions"
    Write-Host "  az ad sp create --id $appId"
    Write-Host '  (Necesita el rol Application Administrator o Cloud Application Administrator en ese tenant.)'
}
Write-Host ''
Write-Host 'Después:'
Write-Host "  1. Un Project Collection Administrator la agrega en Azure DevOps: Organization settings › Users › Add users: '$RegistrationName', acceso Basic, y Contributor del proyecto."
Write-Host "  2. Valide y configure agregando: -DevOpsTenantId $DevOpsTenantId -DevOpsClientId $appId"
