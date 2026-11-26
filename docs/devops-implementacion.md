# iTop → Azure DevOps: implementación

Incidente de iTop con la etiqueta **DEVOPS** → PBI en el sprint actual del equipo en Azure DevOps. El número y el enlace del PBI vuelven al incidente. Para la empresa **solo cambian parámetros**: el código es el mismo.

```
iTop: incidente con Etiquetas = DEVOPS
  └─ extensión itop-devops: encola el envío (no frena al agente)
       └─ cron de iTop: POST a la Function (x-functions-key), con reintentos
            └─ Azure Function ItopDevOpsBridge (.NET 10, identidad administrada del tenant)
                 ├─ ¿ya hay PBI con la etiqueta iTop-I-000123? → lo devuelve (sin duplicados)
                 ├─ sprint actual del equipo → crea el PBI ahí
                 └─ responde número, enlace y sprint → iTop los guarda en el incidente
```

## Piezas

| Carpeta | Qué es |
|---|---|
| `extensiones/itop-devops/` | Extensión de iTop. Agrega el campo **Etiquetas** a los tickets con la etiqueta DEVOPS, más **PBI de Azure DevOps** y **Enlace al PBI**, y hace el envío asíncrono con reintentos. |
| `devops-bridge/ItopDevOpsBridge/` | Azure Function (`POST /api/itop/pbi`). |
| `devops-bridge/ItopDevOpsBridge.Tests/` | Pruebas: título, prioridad, etiquetas, descripción y validación. Se corren con `dotnet test devops-bridge/ItopDevOpsBridge.slnx`. |
| `devops-bridge/validar-function-existente.ps1` | Cuando el administrador ya creó la Function: revisa sin cambiar nada la Function (.NET 10 aislado, HTTPS, red, almacenamiento, identidad, roles) y Azure DevOps (mismo tenant, proyecto, equipo, tipo, sprint actual, identidad agregada). |
| `devops-bridge/configurar-function-existente.ps1` | Después de la validación: activa la identidad, carga `DevOps__*`, publica, prueba (401 sin llave, 400 con llave) y deja la URL, la llave y el bloque de `config-itop.php` en `salida-<app>.local.env`. |
| `devops-bridge/verificar-function.ps1` | Revisa sin cambiar nada que todo esté listo: grupo, almacenamiento, región, nombre libre y roles. |
| `devops-bridge/desplegar-function.ps1` | Crea solo la Function en recursos que ya existen y publica el código. Es la opción para la empresa. |
| `devops-bridge/desplegar.ps1` | Crea todo desde cero (grupo, almacenamiento y Function). Para pruebas o una suscripción propia. |

## Parámetros

**Function** (configuración de la Function App, `DevOps__*`):

| Parámetro | Ejemplo | Nota |
|---|---|---|
| `DevOps__Organization` | `MiEmpresa` | La parte de `dev.azure.com/<organización>` |
| `DevOps__Project` | `Soporte` | El proceso debe tener el tipo de elemento indicado |
| `DevOps__Team` | `Soporte Team` | El sprint actual es el de este equipo |
| `DevOps__WorkItemType` | `Product Backlog Item` | `User Story` en Agile, `Issue` en Basic |
| `DevOps__AreaPath` | *(vacío)* | Vacío = el área por defecto del equipo |
| `DevOps__Tags` | `DEVOPS` | Separadas por `;`. Siempre se agrega `iTop-<ref>` |
| `DevOps__ManagedIdentityClientId` | *(vacío)* | Solo si se usa una identidad asignada por el usuario |
| `DevOps__PersonalAccessToken` | *(vacío)* | **Solo pruebas** en organizaciones sin Entra ID. En la empresa, vacío |

**iTop** (`conf/production/config-itop.php`):

```php
$MySettings = array(
    'async_task_retries' => array(
        'AsyncItopDevOps' => array('max_retries' => 6, 'retry_delay' => 300, 'exponential_delay' => true),
    ),
    // …
);
$MyModuleSettings = array(
    'itop-devops' => array(
        'function_url' => 'https://<app>.azurewebsites.net/api/itop/pbi',
        'function_key' => '<llave de la Function>',
        'tag_code' => 'DEVOPS',
        'tag_attcode' => 'tags',
        'classes' => array('Incident'),   // agregar 'UserRequest' si también aplica a requerimientos
        'timeout' => 30,
    ),
    // …
);
```

## Pasos para la empresa

1. **Azure:**
   - Con los recursos que indique el administrador (suscripción, grupo y almacenamiento), correr primero `./verificar-function.ps1` y, si dice "Todo en orden", `./desplegar-function.ps1` con los mismos parámetros. El detalle y la lista de qué preguntarle al administrador están en `GUIA-PASOS.md`.
   - Imprime el **Object ID** de la identidad y deja la URL y la llave en `salida-<app>.local.env`. Ese archivo no se versiona.
2. **Azure DevOps** (la organización debe estar conectada al tenant de Entra ID). Un *Project Collection Administrator*:
   - En *Organization settings › Users*, agrega la identidad de la Function (se busca por el nombre de la app) con acceso **Basic**.
   - La agrega al proyecto como **Contributor**, o con permiso de crear y editar elementos en el área del equipo.
3. **iTop:**
   - Copiar `extensiones/itop-devops` a `extensions/` de iTop.
   - Quitar la marca de solo lectura de `conf/production/config-itop.php` y agregar la configuración de arriba.
   - Correr `/setup/` en modo **Upgrade** y marcar la extensión **iTop → Azure DevOps** en la página de extensiones.
   - La etiqueta DEVOPS se crea sola.
4. **Cron:** `webservices/cron.php` debe estar programado (cada 5 minutos); es el que hace los envíos.
5. **Prueba:**
   - Crear un incidente con la etiqueta DEVOPS y esperar al cron.
   - El incidente debe quedar con **PBI de Azure DevOps** y una nota en la bitácora privada.

## Prueba de punta a punta: aprobada

**Ambiente de prueba**

| Pieza | Valor |
|---|---|
| Tenant | Directorio predeterminado (`6b33b7a9-b32c-43f1-a8e3-53501894a934`) |
| Organización de Azure DevOps | `devops-pruebas`, creada dentro del tenant |
| Proyecto | `DevOps-Pruebas` (Scrum), equipo `DevOps-Pruebas Team`, Sprint 1 vigente |
| Function | `func-devops-pruebas` en `rg-devops-pruebas`, Central US, Flex Consumption |
| Identidad de la Function | Object ID `af44910c-8eb5-4b63-a47f-3e49b28f7e37`, acceso Basic y Contributor del proyecto |

**Resultado**

1. Se creó el incidente I-000001 en la réplica y se marcó DEVOPS en el selector Etiquetas.
2. El cron lo envió a la Function.
3. Se creó el **PBI 1** en `DevOps-Pruebas\Sprint 1`:
   - etiquetas `DEVOPS; iTop-I-000001`;
   - enlace de vuelta al incidente;
   - creado por `func-devops-pruebas`, con la identidad administrada y sin PAT.
4. El incidente quedó con el número y el enlace del PBI.
5. Al reenviar el mismo ticket, la Function devuelve el PBI existente (`created: false`). No duplica.
6. Sin llave, la Function responde 401.

**Por qué no se usó `SolucionesCoreForge`:** esa organización pertenece a una cuenta personal de Microsoft. Al conectarla al tenant, sus 2 miembros perdían el acceso, y ahí viven el código y el pipeline de producción de INTENEXO. Se creó otra organización dentro del tenant, que es el mismo escenario que en la empresa.

**Agregar la identidad por API**, como alternativa al portal (lo hace un Project Collection Administrator con su token de Entra ID):

```
POST https://vsaex.dev.azure.com/{org}/_apis/serviceprincipalentitlements?api-version=7.1-preview.1
{ "accessLevel": { "accountLicenseType": "express" },
  "servicePrincipal": { "origin": "aad", "originId": "<Object ID de la identidad>", "subjectKind": "servicePrincipal" },
  "projectEntitlements": [ { "group": { "groupType": "projectContributor" }, "projectRef": { "id": "<id del proyecto>" } } ] }
```

## Notas de la réplica (Windows)

El PHP portable de Windows no trae certificados raíz. En la réplica, `curl.cainfo` y `openssl.cafile` de `php.ini` apuntan al paquete de certificados de XAMPP. En un servidor Linux no hace falta.
