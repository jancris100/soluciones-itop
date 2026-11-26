<#
.SYNOPSIS
  Prueba la Function ItopDevOpsBridge ya publicada, solo con permiso de lectura. No crea nada en Azure DevOps.

.DESCRIPTION
  - Sin llave debe responder 401 (está protegida).
  - Con la llave y un ticket vacío debe responder 400 (ItopDevOpsBridge está publicada, la llave sirve y valida los datos).
  La llave se pide en pantalla (no se muestra). Si no la pasa, solo se prueba sin llave.
  Al final imprime la URL para config-itop.php.

.EXAMPLE
  ./probar-function.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function>
#>
param(
    [Parameter(Mandatory)] [string] $Subscription,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AppName,
    # La llave de la Function; si no se pasa, se pide en pantalla.
    [securestring] $Llave
)

az account set --subscription $Subscription 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "No tengo sesión en la suscripción '$Subscription'. Corra az login." -ForegroundColor Red; exit 1 }
$hostName = az functionapp show --name $AppName --resource-group $ResourceGroup --query "properties.defaultHostName || defaultHostName" -o tsv 2>$null
if (-not $hostName) { Write-Host "No encuentro la Function '$AppName' en '$ResourceGroup'." -ForegroundColor Red; exit 1 }
$url = "https://$hostName/api/itop/pbi"

function Get-Codigo([hashtable] $headers) {
    try {
        return [int](Invoke-WebRequest -Uri $url -Method Post -Body '{}' -ContentType 'application/json' -Headers $headers -UseBasicParsing -TimeoutSec 90).StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

$ok = $true
$sinLlave = Get-Codigo @{}
if ($sinLlave -eq 401) { Write-Host '  [OK]    Sin llave responde 401 (protegida).' -ForegroundColor Green }
elseif ($sinLlave -eq 404) { Write-Host '  [FALLA] Responde 404: ItopDevOpsBridge todavía no está publicada.' -ForegroundColor Red; $ok = $false }
else { Write-Host "  [FALLA] Sin llave respondió $sinLlave (se esperaba 401). Si es la primera llamada, espere un minuto y repita." -ForegroundColor Red; $ok = $false }

if (-not $Llave) { try { $Llave = Read-Host 'Pegue la llave de la Function (Enter para omitir)' -AsSecureString } catch { } }
$llaveTexto = if ($Llave) { [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Llave)) } else { '' }
if ($llaveTexto) {
    $conLlave = Get-Codigo @{ 'x-functions-key' = $llaveTexto }
    if ($conLlave -eq 400) { Write-Host '  [OK]    Con llave y un ticket vacío responde 400: publicada y la llave sirve.' -ForegroundColor Green }
    elseif ($conLlave -eq 401) { Write-Host '  [FALLA] Con llave respondió 401: la llave no es la de la función CreatePbi (o la de la app).' -ForegroundColor Red; $ok = $false }
    else { Write-Host "  [FALLA] Con llave respondió $conLlave (se esperaba 400). Revise los registros de la Function (Log stream)." -ForegroundColor Red; $ok = $false }
}

Write-Host ''
Write-Host "URL para config-itop.php (function_url): $url"
if (-not $ok) { exit 1 }
