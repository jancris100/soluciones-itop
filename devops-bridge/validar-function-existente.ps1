<#
.SYNOPSIS
  Paso 1 de 2, cuando la empresa YA creó la Azure Function: revisa que esté todo lo necesario para ItopDevOpsBridge.
  NO crea ni cambia nada (ni en Azure ni en Azure DevOps).

.DESCRIPTION
  Revisa, y al final da un resumen con [OK], [AVISO] y [FALTA]:
    Esta máquina   Azure CLI con sesión iniciada, SDK de .NET 10 y curl.
    Function App   que exista y usted la vea; encendida; .NET 10 aislado; solo HTTPS y TLS 1.2; acceso público y
                   restricciones de IP (iTop debe poder entrar); almacenamiento; cómo se publica el código; identidad
                   administrada; sus roles; configuración DevOps__* que ya tenga; si ItopDevOpsBridge ya está publicada.
    Azure DevOps   que la organización esté conectada al MISMO tenant de Entra ID que la Function; proyecto, equipo,
                   tipo de elemento, área y sprint actual (con su propia sesión); si la identidad de la Function ya
                   está agregada en la organización.

  [FALTA] impide seguir: arréglelo (o pídalo al administrador) y vuelva a correrlo.
  [AVISO] no impide seguir, pero conviene revisarlo.
  Si termina en "Todo en orden", corra configurar-function-existente.ps1 con exactamente los mismos parámetros.

.EXAMPLE
  ./validar-function-existente.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> `
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
    [securestring] $Pat
)

$ErrorActionPreference = 'Continue'
$faltas = New-Object System.Collections.Generic.List[string]
$avisos = New-Object System.Collections.Generic.List[string]
function Ok([string] $texto) { Write-Host "  [OK]    $texto" -ForegroundColor Green }
function Aviso([string] $texto) { $avisos.Add($texto); Write-Host "  [AVISO] $texto" -ForegroundColor Yellow }
function Falta([string] $texto) { $faltas.Add($texto); Write-Host "  [FALTA] $texto" -ForegroundColor Red }
function Info([string] $texto) { Write-Host "          $texto" }
$enc = { param($s) [uri]::EscapeDataString($s) }

# PAT: se pide una vez y se usa solo en memoria.
if ($UsarPat -and -not $Pat) { $Pat = Read-Host 'Pegue el PAT de Azure DevOps (no se muestra)' -AsSecureString }
$patTexto = if ($Pat) { [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Pat)) } else { '' }

# ---------------------------------------------------------------------------------------------------------------
Write-Host ''
Write-Host '1/3 Esta máquina'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Falta 'No está Azure CLI (az). Instálelo: https://aka.ms/installazurecliwindows'
    Write-Host ''; Write-Host 'Sin Azure CLI no se puede revisar lo demás.' -ForegroundColor Red; exit 1
}
Ok "Azure CLI $((az version -o json 2>$null | ConvertFrom-Json).'azure-cli')"
# ItopDevOpsBridge es .NET 10: lo compila el SDK 10 o uno más nuevo (el 11 compila proyectos net10.0 sin cambios).
$sdk = dotnet --list-sdks 2>$null | ForEach-Object { ($_ -split ' ')[0] } | Where-Object { [int]($_.Split('.')[0]) -ge 10 } | Select-Object -Last 1
if ($sdk) { Ok "SDK de .NET $sdk (compila ItopDevOpsBridge, que es .NET 10)" }
else { Falta 'Falta un SDK de .NET 10 o más nuevo en esta máquina: https://dotnet.microsoft.com/download/dotnet/10.0' }
$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curl) { Aviso 'No está curl.exe: no puedo revisar el tenant de Azure DevOps ni llegar a la Function.' }

az account set --subscription $Subscription 2>$null
if ($LASTEXITCODE -ne 0) {
    Falta "No tengo sesión en la suscripción '$Subscription'. Corra 'az login' con su cuenta de la empresa (y revise el id)."
    Write-Host ''; Write-Host 'Sin la suscripción no se puede revisar lo demás.' -ForegroundColor Red; exit 1
}
$cuenta = az account show -o json | ConvertFrom-Json
$tenant = $cuenta.tenantId
Ok "Sesión: $($cuenta.user.name) | suscripción $($cuenta.name) | tenant $tenant"

# ---------------------------------------------------------------------------------------------------------------
Write-Host ''
Write-Host "2/3 Function App '$AppName'"
$app = az functionapp show --name $AppName --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json
$principalId = $null
if (-not $app) {
    Falta "No encuentro la Function '$AppName' en el grupo '$ResourceGroup', o no tengo acceso. Confirme nombre y grupo con el administrador, y que le dio acceso."
} else {
    $props = $app.properties
    $estado = if ($app.state) { $app.state } else { $props.state }
    if ($estado -eq 'Running') { Ok "Encendida ($($app.location))" } else { Falta "La Function está '$estado'. Debe estar encendida (Running)." }

    # .NET 10 aislado: en Flex Consumption está en functionAppConfig.runtime; en los demás planes, en linuxFxVersion
    # (Linux) o en FUNCTIONS_WORKER_RUNTIME + netFrameworkVersion (Windows).
    $flex = $props.functionAppConfig.runtime
    $config = az functionapp config show --name $AppName --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json
    # Leer la configuración pide permiso de escritura (Website Contributor): con solo lectura, Azure no la entrega.
    $nombres = @(az functionapp config appsettings list --name $AppName --resource-group $ResourceGroup --query "[].name" -o tsv 2>$null)
    $leeConfig = $LASTEXITCODE -eq 0 -and $nombres.Count -gt 0
    if ($flex) {
        $plan = 'Flex Consumption'
        $runtime = "$($flex.name) $($flex.version)"
        $okRuntime = $flex.name -eq 'dotnet-isolated' -and "$($flex.version)" -like '10*'
    } else {
        $plan = if ($props.sku) { $props.sku } else { 'Consumo / App Service' }
        $worker = az functionapp config appsettings list --name $AppName --resource-group $ResourceGroup --query "[?name=='FUNCTIONS_WORKER_RUNTIME'].value | [0]" -o tsv 2>$null
        if ($config.linuxFxVersion) {
            $runtime = $config.linuxFxVersion
            $okRuntime = $config.linuxFxVersion -match '^DOTNET-ISOLATED\|10'
        } else {
            $runtime = "$worker $($config.netFrameworkVersion)"
            $okRuntime = $worker -eq 'dotnet-isolated' -and "$($config.netFrameworkVersion)" -like 'v10*'
        }
    }
    if ($okRuntime) { Ok "Runtime $runtime | plan $plan" }
    else { Falta "La Function usa '$runtime' (plan $plan) y ItopDevOpsBridge necesita .NET 10 aislado (dotnet-isolated 10.0). Pídale al administrador que la cree o la cambie a ese runtime." }

    $httpsOnly = if ($null -ne $props.httpsOnly) { $props.httpsOnly } else { $app.httpsOnly }
    if ($httpsOnly) { Ok 'Solo HTTPS' } else { Aviso "La Function acepta HTTP sin cifrar. Recomendado: 'Solo HTTPS' activado (Configuración › General), porque iTop manda la llave en cada llamada." }
    if ($config.minTlsVersion -and [version]$config.minTlsVersion -lt [version]'1.2') { Aviso "TLS mínimo $($config.minTlsVersion). Recomendado: 1.2." }
    elseif ($config.minTlsVersion) { Ok "TLS mínimo $($config.minTlsVersion)" }

    if ($props.publicNetworkAccess -eq 'Disabled') {
        Aviso 'El acceso público está deshabilitado: el servidor de iTop solo llegará por red privada (VNet / Private Endpoint), y la publicación del código desde esta máquina puede fallar.'
    }
    $restricciones = az functionapp config access-restriction show --name $AppName --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json
    $reglas = @($restricciones.ipSecurityRestrictions | Where-Object { $_.ipAddress -ne 'Any' -and $_.name -ne 'Allow all' })
    if ($reglas.Count -gt 0) {
        Aviso "La Function tiene restricciones de IP ($(($reglas | ForEach-Object { "$($_.action) $($_.ipAddress)" }) -join ', ')). La IP de salida del servidor de iTop debe estar permitida."
    } else { Ok 'Sin restricciones de IP de entrada (iTop puede llegar)' }
    $reglasScm = @($restricciones.scmIpSecurityRestrictions | Where-Object { $_.ipAddress -ne 'Any' -and $_.name -ne 'Allow all' })
    if ($reglasScm.Count -gt 0 -and -not $restricciones.scmIpSecurityRestrictionsUseMain) {
        Aviso 'El sitio de publicación (SCM) tiene restricciones de IP: la IP de esta máquina debe estar permitida para publicar el código.'
    }

    # Con cadena de conexión es AzureWebJobsStorage; con identidad, AzureWebJobsStorage__accountName (o __blobServiceUri…).
    if (-not $leeConfig) {
        Aviso "Su usuario no puede leer la configuración de la Function (hace falta Website Contributor), así que no veo el almacenamiento. Revíselo en el portal: Function › Configuración › Variables de entorno: debe estar AzureWebJobsStorage o AzureWebJobsStorage__accountName."
    } elseif ($nombres | Where-Object { $_ -like 'AzureWebJobsStorage*' }) {
        Ok "Almacenamiento de la Function configurado ($(($nombres | Where-Object { $_ -like 'AzureWebJobsStorage*' }) -join ', '))"
    } else { Falta 'La Function no tiene almacenamiento (ninguna configuración AzureWebJobsStorage). Sin él no arranca: pídale al administrador que lo configure.' }

    if ($flex) {
        if ($props.functionAppConfig.deployment.storage.value) { Ok 'Publicación: contenedor de despliegue de Flex Consumption' }
        else { Falta 'Flex Consumption sin contenedor de despliegue (functionAppConfig.deployment.storage).' }
    } else {
        $basic = az resource show --ids "$($app.id)/basicPublishingCredentialsPolicies/scm" --query properties.allow -o tsv 2>$null
        if ($basic -eq 'false') { Aviso 'Las credenciales básicas de publicación (SCM) están deshabilitadas. Si la publicación falla, pida habilitarlas o publique desde Visual Studio / un pipeline.' }
        else { Ok 'Publicación por zip (credenciales SCM habilitadas)' }
    }

    $principalId = $app.identity.principalId
    if ($principalId) { Ok "Identidad administrada activa (Object ID $principalId)" }
    elseif ($app.identity.userAssignedIdentities) { Aviso 'Solo tiene identidad asignada por el usuario. ItopDevOpsBridge usa la del sistema, salvo que configure DevOps__ManagedIdentityClientId.' }
    else { Aviso 'La identidad administrada no está activa: el paso 2 la activa (o pídale al administrador: Identidad › Asignada por el sistema › Activado).' }

    $userType = az account show --query user.type -o tsv
    if ($userType -eq 'user') {
        $me = az ad signed-in-user show --query id -o tsv 2>$null
        $roles = @()
        if ($me) { $roles = @(az role assignment list --assignee $me --scope $app.id --include-inherited --include-groups --query "[].roleDefinitionName" -o tsv 2>$null | Where-Object { $_ }) }
        if ($roles | Where-Object { $_ -in 'Owner', 'Contributor', 'Website Contributor' }) { Ok "Sus roles: $(($roles | Sort-Object -Unique) -join ', ')" }
        elseif ($roles.Count -gt 0) { Aviso "Sus roles ($(($roles | Sort-Object -Unique) -join ', ')) no alcanzan para configurar y publicar. Quien corra configurar-function-existente.ps1 (por ejemplo su administrador) necesita 'Website Contributor' o 'Contributor' sobre '$AppName'." }
        else { Aviso "No pude leer sus roles. Confirme con el administrador que tiene 'Website Contributor' (o Contributor) sobre '$AppName'." }
    } else { Aviso 'La sesión es de una identidad de servicio: confirme que tenga Website Contributor o Contributor sobre la Function.' }

    $actuales = az functionapp config appsettings list --name $AppName --resource-group $ResourceGroup --query "[?starts_with(name, 'DevOps__')].{n:name, v:value}" -o json 2>$null | ConvertFrom-Json
    if (@($actuales).Count -gt 0) {
        Info 'Configuración DevOps__ que ya tiene (el paso 2 la reemplaza con sus parámetros):'
        foreach ($s in $actuales) {
            $valor = if ($s.n -eq 'DevOps__PersonalAccessToken') { if ($s.v) { '(con valor)' } else { '(vacío)' } } else { $s.v }
            Info "  $($s.n) = $valor"
        }
        if (-not $patTexto -and ($actuales | Where-Object { $_.n -eq 'DevOps__PersonalAccessToken' -and $_.v })) { Aviso 'DevOps__PersonalAccessToken tiene valor: en la empresa debe quedar vacío para que use la identidad administrada.' }
    }

    $funciones = @(az functionapp function list --name $AppName --resource-group $ResourceGroup --query "[].name" -o tsv 2>$null)
    if ($funciones | Where-Object { $_ -like '*CreatePbi' }) { Info 'ItopDevOpsBridge ya está publicada (función CreatePbi). El paso 2 la actualiza.' }
    else { Info 'ItopDevOpsBridge todavía no está publicada: lo hace el paso 2.' }

    $hostName = if ($props.defaultHostName) { $props.defaultHostName } else { $app.defaultHostName }
    if ($curl -and $hostName) {
        $codigo = & curl.exe -s -o NUL -w '%{http_code}' --max-time 30 "https://$hostName/"
        if ($codigo -and $codigo -ne '000') { Ok "Esta máquina llega a https://$hostName (HTTP $codigo)" }
        else { Aviso "Esta máquina no llega a https://$hostName. Si iTop está en otra red, pruebe desde el servidor de iTop: curl -I https://$hostName/" }
    }
}

# ---------------------------------------------------------------------------------------------------------------
Write-Host ''
Write-Host "3/3 Azure DevOps '$Organization'"
$orgUrl = "https://dev.azure.com/$(& $enc $Organization)"
if ($curl) {
    $cabeceras = & curl.exe -s -o NUL -D - --max-time 30 "$orgUrl/_apis/connectionData"
    $tenantOrg = ($cabeceras | Select-String -Pattern '^X-VSS-ResourceTenant:\s*(\S+)' | Select-Object -First 1).Matches.Groups[1].Value
    if (-not $tenantOrg) { Falta "No encuentro la organización '$Organization' en Azure DevOps. Es la parte de dev.azure.com/<organización>." }
    elseif ($tenantOrg -eq '00000000-0000-0000-0000-000000000000') { Falta "La organización '$Organization' no está conectada a Entra ID (es de cuentas personales). La identidad de la Function solo funciona si está conectada al tenant $tenant." }
    elseif ($tenantOrg -eq $tenant -and -not $patTexto) { Ok "Conectada al mismo tenant que la Function ($tenant)" }
    elseif ($patTexto) { Ok "Tenant de la organización: $tenantOrg. La Function entrará con el PAT (no depende del tenant)." }
    elseif (-not $DevOpsClientId) {
        Falta "La organización está en el tenant $tenantOrg y la Function en $tenant. La identidad de la Function sola no entra a otro tenant: cree el acceso con crear-acceso-entre-tenants.ps1 y pase -DevOpsTenantId $tenantOrg -DevOpsClientId <Application ID>."
    } elseif ($DevOpsTenantId -ne $tenantOrg) {
        Falta "La organización está en el tenant $tenantOrg, pero -DevOpsTenantId dice '$DevOpsTenantId'. Use -DevOpsTenantId $tenantOrg."
    } else { Ok "Organización en otro tenant ($tenantOrg): la Function entra con el registro de aplicación $DevOpsClientId" }
}

# Organización en otro tenant: el registro de aplicación (en el tenant de la Function) debe ser multitenant y confiar en
# la identidad administrada de la Function.
$nombreEnDevOps = $AppName
if ($DevOpsClientId) {
    $registro = az ad app show --id $DevOpsClientId -o json 2>$null | ConvertFrom-Json
    if (-not $registro) {
        Aviso "No pude leer el registro de aplicación $DevOpsClientId en este tenant (no existe, o su usuario no puede verlo). Confírmelo con quien lo creó."
    } else {
        $nombreEnDevOps = $registro.displayName
        if ($registro.signInAudience -ne 'AzureADMultipleOrgs') { Falta "El registro '$($registro.displayName)' no es multitenant ($($registro.signInAudience)): en Autenticación, marque 'Cuentas de cualquier directorio organizativo'." }
        else { Ok "Registro de aplicación '$($registro.displayName)' (multitenant)" }
        $federadas = @(az ad app federated-credential list --id $DevOpsClientId -o json 2>$null | ConvertFrom-Json)
        if ($principalId -and ($federadas | Where-Object { $_.subject -eq $principalId -and $_.audiences -contains 'api://AzureADTokenExchange' })) {
            Ok 'El registro confía en la identidad administrada de la Function (credencial federada)'
        } elseif ($principalId) {
            Falta "El registro '$($registro.displayName)' no tiene la credencial federada de la identidad de la Function (Object ID $principalId). Vuelva a correr crear-acceso-entre-tenants.ps1."
        }
    }
}

# Con su sesión: en el tenant de la organización (si es otro, su cuenta debe estar también en ese tenant).
$tenantToken = if ($tenantOrg -and $tenantOrg -ne $tenant -and $tenantOrg -ne '00000000-0000-0000-0000-000000000000') { $tenantOrg } else { $tenant }
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --tenant $tenantToken --query accessToken -o tsv 2>$null
if (-not $token -and $tenantToken -ne $tenant) {
    Info "Para revisar la organización con su cuenta, inicie sesión también en su tenant: az login --tenant $tenantToken --allow-no-subscriptions"
}
function Get-DevOps([string] $url) {
    try {
        $r = Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $token" } -Method Get -UseBasicParsing -TimeoutSec 60
    } catch {
        $codigo = 0
        if ($_.Exception.Response) { $codigo = [int]$_.Exception.Response.StatusCode }
        return @{ Status = $codigo; Body = $null; Raw = '' }
    }
    # Sin acceso, Azure DevOps a veces responde 203 con la página de inicio de sesión (HTML) en vez de 401.
    if ("$($r.Headers['Content-Type'])" -notlike '*json*') { return @{ Status = 401; Body = $null; Raw = '' } }
    # Algunas respuestas (tipos de elemento) traen claves que solo difieren en mayúsculas y ConvertFrom-Json no las lee.
    $body = $null
    try { $body = $r.Content | ConvertFrom-Json } catch { }
    return @{ Status = [int]$r.StatusCode; Body = $body; Raw = $r.Content }
}

if (-not $token) {
    Aviso 'No pude obtener un token de Azure DevOps con su sesión: no reviso proyecto, equipo ni sprint. Revíselos a mano.'
} else {
    $proyecto = Get-DevOps "$orgUrl/_apis/projects/$(& $enc $Project)?includeCapabilities=true&api-version=7.1"
    if ($proyecto.Status -eq 200) {
        Ok "Proyecto '$Project' (proceso $($proyecto.Body.capabilities.processTemplate.templateName))"
        $projUrl = "$orgUrl/$(& $enc $Project)"

        $equipo = Get-DevOps "$orgUrl/_apis/projects/$(& $enc $Project)/teams/$(& $enc $Team)?api-version=7.1"
        if ($equipo.Status -eq 200) { Ok "Equipo '$Team'" }
        else { Falta "No encuentro el equipo '$Team' en el proyecto (HTTP $($equipo.Status)). Use el nombre exacto de Project settings › Teams." }

        $tipo = Get-DevOps "$projUrl/_apis/wit/workitemtypes/$(& $enc $WorkItemType)?api-version=7.1"
        if ($tipo.Status -eq 200) { Ok "Tipo de elemento '$WorkItemType'" }
        else {
            $tipos = Get-DevOps "$projUrl/_apis/wit/workitemtypes?api-version=7.1"
            $lista = ([regex]::Matches($tipos.Raw, '"name":"([^"]+)","referenceName"') | ForEach-Object { $_.Groups[1].Value } |
                Where-Object { $_ -in 'Product Backlog Item', 'User Story', 'Issue', 'Requirement' } | Sort-Object -Unique) -join ', '
            Falta "El proyecto no tiene el tipo '$WorkItemType'. Pase -WorkItemType con uno de estos: $lista"
        }

        if ($AreaPath) {
            $relativa = ($AreaPath -replace '^[^\\]+\\?', '') -split '\\' | ForEach-Object { & $enc $_ }
            $area = Get-DevOps "$projUrl/_apis/wit/classificationnodes/Areas/$($relativa -join '/')?api-version=7.1"
            if ($area.Status -eq 200) { Ok "Área '$AreaPath'" } else { Falta "No existe el área '$AreaPath' en el proyecto. Déjelo vacío para usar el área del equipo." }
        }

        if ($equipo.Status -eq 200) {
            $sprint = Get-DevOps "$projUrl/$(& $enc $Team)/_apis/work/teamsettings/iterations?`$timeframe=current&api-version=7.1"
            $actual = @($sprint.Body.value) | Select-Object -First 1
            # Las fechas vienen en UTC; PowerShell 7 las convierte a fecha y 5.1 las deja como texto.
            $fecha = { param($v) if ($v -is [datetime]) { $v.ToUniversalTime().ToString('yyyy-MM-dd') } else { "$v".Substring(0, 10) } }
            if ($actual) { Ok "Sprint actual del equipo: $($actual.path) ($(& $fecha $actual.attributes.startDate) a $(& $fecha $actual.attributes.finishDate))" }
            elseif ($sprint.Status -eq 200) { Aviso 'El equipo no tiene un sprint vigente hoy: los PBI quedarán en el backlog hasta que se creen sprints con fechas.' }
            else { Aviso "No pude leer los sprints del equipo (HTTP $($sprint.Status))." }
        }
    } elseif ($proyecto.Status -eq 404) {
        Falta "No existe el proyecto '$Project' en '$Organization' (o no lo ve). Use el nombre exacto."
    } else {
        Aviso "Su cuenta no tiene acceso a '$Organization' (HTTP $($proyecto.Status)): no reviso proyecto, equipo ni sprint. Revíselos a mano o pida acceso."
    }

    if (-not $patTexto -and ($principalId -or $DevOpsClientId)) {
        $ids = Get-DevOps "https://vssps.dev.azure.com/$(& $enc $Organization)/_apis/identities?searchFilter=General&filterValue=$(& $enc $nombreEnDevOps)&queryMembership=None&api-version=7.1"
        $encontrada = @($ids.Body.value) | Where-Object { $_.providerDisplayName -eq $nombreEnDevOps -or $_.customDisplayName -eq $nombreEnDevOps } | Select-Object -First 1
        if ($encontrada) { Ok "'$nombreEnDevOps' ya está en la organización" }
        elseif ($ids.Status -eq 200) {
            Aviso "'$nombreEnDevOps' todavía no está en Azure DevOps. Un Project Collection Administrator lo agrega (Organization settings › Users › Add users: '$nombreEnDevOps', acceso Basic, proyecto '$Project' como Contributor)."
        } else { Info "No pude buscar '$nombreEnDevOps' en la organización: confírmelo con el administrador de Azure DevOps." }
    }
}

# El PAT, con lo mismo que usará la Function: el tipo de elemento y el sprint del equipo (permiso Work Items).
if ($patTexto) {
    $basic = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$patTexto"))
    $proyUrl = "$orgUrl/$(& $enc $Project)"
    $pruebas = @(
        @{ Que = "tipo de elemento '$WorkItemType'"; Url = "$proyUrl/_apis/wit/workitemtypes/$(& $enc $WorkItemType)?api-version=7.1" },
        @{ Que = "sprints del equipo '$Team'"; Url = "$proyUrl/$(& $enc $Team)/_apis/work/teamsettings/iterations?`$timeframe=current&api-version=7.1" }
    )
    foreach ($prueba in $pruebas) {
        $codigo = 0; $json = $false
        try {
            $r = Invoke-WebRequest -Uri $prueba.Url -Headers @{ Authorization = $basic } -UseBasicParsing -TimeoutSec 60
            $codigo = [int]$r.StatusCode; $json = "$($r.Headers['Content-Type'])" -like '*json*'
        } catch { if ($_.Exception.Response) { $codigo = [int]$_.Exception.Response.StatusCode } }
        if ($codigo -eq 200 -and $json) { Ok "PAT: entra a Azure DevOps y lee el $($prueba.Que)" }
        elseif ($codigo -eq 404) { Falta "PAT: entra, pero no encuentra el $($prueba.Que). Revise el nombre exacto." }
        else { Falta "PAT: Azure DevOps lo rechazó (HTTP $codigo). Revise que no esté vencido, que sea de la organización '$Organization' (o de todas) y que tenga Work Items (Read & write)." }
    }
    Info 'El permiso de escritura no se puede probar sin crear un PBI: confírmelo al crear el PAT (Work Items: Read & write).'
}

# ---------------------------------------------------------------------------------------------------------------
Write-Host ''
if ($faltas.Count -gt 0) {
    Write-Host "Faltan $($faltas.Count) cosa(s) antes de configurar:" -ForegroundColor Red
    $faltas | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    if ($avisos.Count -gt 0) { Write-Host "Además hay $($avisos.Count) aviso(s) arriba." -ForegroundColor Yellow }
    exit 1
}
if ($avisos.Count -gt 0) { Write-Host "Todo en orden, con $($avisos.Count) aviso(s) para revisar (arriba)." -ForegroundColor Yellow }
else { Write-Host 'Todo en orden.' -ForegroundColor Green }
Write-Host 'Siguiente paso: configurar-function-existente.ps1 con exactamente los mismos parámetros.'
exit 0
