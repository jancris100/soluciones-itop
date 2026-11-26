<#
.SYNOPSIS
  Paso 1 de 2: revisa que todo esté listo para crear la Azure Function ItopDevOpsBridge. NO crea ni cambia nada.

.DESCRIPTION
  Corre las verificaciones de desplegar-function.ps1 (que es el paso 2) con los mismos datos:
    - sesión de Azure CLI, suscripción y tenant;
    - que el grupo de recursos y la cuenta de almacenamiento existan y se tenga acceso;
    - que el proveedor Microsoft.Web esté registrado y la región admita Flex Consumption con .NET 10;
    - que el Application Insights indicado exista;
    - que el nombre de la Function esté libre en Azure (o que ya exista en ese grupo, para actualizarla);
    - sus roles en el grupo (Contributor u Owner alcanzan);
    - que esté el SDK de .NET 10 para compilar.
  Si dice "Todo en orden", corra desplegar-function.ps1 con exactamente los mismos parámetros.

.EXAMPLE
  ./verificar-function.ps1 -Subscription "<id>" -ResourceGroup <grupo> -StorageName <almacenamiento> `
     -AppName func-devops-empresa -Organization MiEmpresa -Project Soporte -Team "Soporte Team" [-AppInsights <appi>]
#>
param(
    [Parameter(Mandatory)] [string] $Subscription,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $StorageName,
    [Parameter(Mandatory)] [string] $AppName,
    [Parameter(Mandatory)] [string] $Organization,
    [Parameter(Mandatory)] [string] $Project,
    [Parameter(Mandatory)] [string] $Team,
    [string] $Location = '',
    [string] $AppInsights = ''
)

$parametros = @{
    Subscription = $Subscription; ResourceGroup = $ResourceGroup; StorageName = $StorageName; AppName = $AppName
    Organization = $Organization; Project = $Project; Team = $Team; Location = $Location; AppInsights = $AppInsights
}
& (Join-Path $PSScriptRoot 'desplegar-function.ps1') @parametros -SoloVerificar
exit $LASTEXITCODE
