# Guía de pasos: iTop (mesa de servicio)

Esta guía cubre cuatro trabajos:

1. **Réplica local** de iTop con las mismas versiones de producción.
2. **Actualización** de iTop 3.0.2 a la versión más reciente, ensayada primero en la réplica.
3. **iTop → Azure DevOps**: un incidente con la etiqueta DEVOPS crea un PBI en el sprint actual.
4. **Recordatorio de cierre** de tickets solucionados (propuesta).

| Carpeta | Contenido |
|---|---|
| `extensiones/itop-devops/` | Extensión de iTop: campo Etiquetas, campos del PBI y envío asíncrono con reintentos |
| `devops-bridge/` | Azure Function .NET 10 (`ItopDevOpsBridge`), pruebas y script de despliegue `desplegar.ps1` |
| `entorno-plantillas/` | Configuración de MySQL, Apache y PHP de la réplica (`{RAIZ}` = carpeta del proyecto) |
| `docs/` | Plan de actualización, propuesta y detalle de la integración con Azure DevOps, capturas de la instalación |
| `iniciar.ps1`, `detener.ps1`, `cron.ps1` | Arrancar y detener la réplica y correr las tareas de fondo de iTop |

---

## 1. Réplica local (Windows)

Las versiones son las mismas de producción: **iTop 3.0.2-1-9957**, **PHP 8.2.26** y **MySQL 8.0.34**. Apache 2.4 se usa con una configuración propia.

1. **Descargar** a `descargas/`, solo de sitios oficiales:
   - PHP 8.2.26 *Thread Safe x64 (vs16)*: `https://windows.php.net/downloads/releases/archives/php-8.2.26-Win32-vs16-x64.zip`
   - MySQL 8.0.34 (zip sin instalador): `https://cdn.mysql.com/archives/mysql-8.0/mysql-8.0.34-winx64.zip`
   - iTop 3.0.2-1-9957: `https://sourceforge.net/projects/itop/files/itop/3.0.2-1/iTop-3.0.2-1-9957.zip`
   - Apache 2.4 (Apache Lounge, VS17). En la réplica se usaron los binarios de XAMPP en `C:\xampp\apache`.
2. **Extraer:**
   - PHP en `entorno/php`.
   - MySQL en `entorno/mysql`.
   - La carpeta `web` del zip de iTop en `itop/`.
3. **Configurar**, copiando las plantillas de `entorno-plantillas/` y cambiando `{RAIZ}` por la ruta de la carpeta:
   - `my.ini` → `entorno/my.ini`. MySQL queda en el puerto 3307, solo en 127.0.0.1, con utf8mb4.
   - `httpd.conf` → `entorno/apache/httpd.conf`. Apache queda en el puerto 8090 con `LoadFile php8ts.dll`.
   - `php.ini`: copiar `php.ini-production` y aplicar `php.ini.cambios`. Eso incluye:
     - las extensiones mysqli, gd, ldap, soap, zip, intl, curl, openssl, mbstring, fileinfo y sodium;
     - 512 MB de memoria, la zona horaria America/Costa_Rica y la carpeta de sesiones;
     - el paquete de certificados (CA) para HTTPS.
4. **Inicializar MySQL** y crear la base:
   ```powershell
   entorno\mysql\bin\mysqld.exe --defaults-file=entorno\my.ini --initialize-insecure
   ./iniciar.ps1
   entorno\mysql\bin\mysql.exe -u root -P 3307 -h 127.0.0.1
   ```
   ```sql
   ALTER USER 'root'@'localhost' IDENTIFIED BY '<contraseña root>';
   CREATE DATABASE itop CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER 'itop'@'localhost' IDENTIFIED BY '<contraseña itop>';
   GRANT ALL PRIVILEGES ON itop.* TO 'itop'@'localhost';
   ```
   Las contraseñas van en `entorno/credenciales.local.env`, que no se versiona. `cron.ps1` lee de ahí el usuario administrador.
5. **Instalar iTop** en `http://localhost:8090/setup/`, eligiendo:
   - Install new.
   - Aceptar las licencias.
   - Base `itop` en `127.0.0.1:3307` (base existente).
   - Administrador `admin`, idioma Español.
   - Sin datos de ejemplo.
   - Módulos: CMDB completa, servicios para empresas, **tickets ITIL** (requerimientos, incidentes y portal) y cambios simples.

   Las capturas de cada paso están en `docs/capturas-instalacion/`.
6. **Tareas de fondo:** `./cron.ps1` corre `webservices/cron.php`, que maneja notificaciones, SLA y la cola asíncrona. En producción se programa cada 5 minutos.

**Problemas encontrados en Windows (documentar):**

| Síntoma | Causa | Solución |
|---|---|---|
| El asistente dice PHP 8.2.12 | Apache cargaba `php8ts.dll` de XAMPP desde el PATH | `LoadFile` de `php8ts.dll` en `httpd.conf` y el PHP propio primero en el PATH (`iniciar.ps1`) |
| La pantalla se ve sin estilos | Los `.htaccess` de iTop usan `IndexIgnore` | Cargar `mod_autoindex` en Apache |
| "SSL certificate problem" al llamar a Azure | El PHP portable no trae certificados raíz | `curl.cainfo` y `openssl.cafile` apuntan a un paquete CA. En Linux no hace falta. |
| Advertencia "PHP 8.2.26 not yet validated" | Combodo no validó PHP 8.2 para iTop 3.0.2 | Es la misma combinación de producción; solo se informa |

---

## 2. Actualizar iTop 3.0.2 a la versión más reciente

Todo se ensaya primero en la réplica con una copia de producción. El detalle está en `docs/plan-actualizacion-itop.md`.

1. **Definir la versión destino.** Revisar en `https://github.com/Combodo/iTop/releases` la última estable y sus requisitos. La 3.3.0 pide PHP 8.2 como mínimo, así que PHP 8.2.26 alcanza; MySQL 8.0 también.
2. **Inventario de producción:**
   - versión ("Acerca de iTop");
   - extensiones instaladas;
   - personalizaciones;
   - tareas programadas;
   - correo entrante.
3. **Respaldo completo:**
   - la base de datos (`mysqldump`);
   - la carpeta de iTop completa, con `conf/`, `data/` y `extensions/`.
4. **Ensayo en la réplica:**
   1. Restaurar el respaldo.
   2. Copiar la versión nueva sobre la carpeta, sin borrar `conf/`, `data/` ni `extensions/`.
   3. Quitar el atributo de solo lectura de `conf/production/config-itop.php`.
   4. Correr `/setup/` en modo **Upgrade an existing iTop instance**.

   La otra vía es *Sistema › Actualización de aplicación*: se sube el `.zip`, se verifica y se respaldan los archivos. Esa pantalla **no** descarga la versión ni respalda la base.
5. **Pruebas:**
   - entrar con un usuario;
   - crear, solucionar y cerrar un ticket;
   - notificaciones y correo entrante;
   - `cron.php`;
   - reportes;
   - las extensiones `itop-devops` y la del recordatorio de cierre.
6. **Producción:**
   - ventana de mantenimiento;
   - los mismos pasos ensayados;
   - verificación en "Acerca de iTop";
   - plan de reversa: restaurar el respaldo del paso 3.
7. **Evidencia:** captura de antes y después de "Acerca de iTop", comandos de respaldo, capturas del asistente, problemas encontrados y tiempos.

---

## 3. iTop → PBI en Azure DevOps

El agente marca **DEVOPS** en el selector **Etiquetas** del incidente. iTop envía el ticket por su cola, con reintentos, a la Azure Function **ItopDevOpsBridge**. La Function entra a Azure DevOps **por el tenant**, con la identidad administrada y sin PAT. Ahí busca si ya hay un PBI para ese ticket, consulta el **sprint actual** del equipo y crea el PBI. Después le devuelve a iTop el número y el enlace.

Detalle de parámetros, API y diseño: `docs/devops-implementacion.md` y `docs/propuesta-itop-azure-devops.md`.

### Requisitos
- La organización de Azure DevOps conectada al tenant de Entra ID de la empresa.
- Un proyecto con el tipo de elemento deseado: *Product Backlog Item* en Scrum, *User Story* en Agile o *Issue* en Basic.
- Un equipo con sprints que tengan fechas.
- Una suscripción de Azure en ese tenant, con permiso para crear recursos.
- Una persona con rol **Project Collection Administrator** en Azure DevOps.
- Que el servidor de iTop pueda salir por HTTPS a `*.azurewebsites.net`.
- El cron de iTop funcionando.

### Paso 1: Function en Azure

**Opción 0, cuando el administrador ya creó la Function.** No se crea nada en Azure. Son dos scripts, con los mismos parámetros:

```powershell
cd devops-bridge
# 1. Validación: no cambia nada.
./validar-function-existente.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> `
   -Organization <organización> -Project <proyecto> -Team "<equipo>"
# 2. Si dice "Todo en orden": configura, publica y prueba.
./configurar-function-existente.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> `
   -Organization <organización> -Project <proyecto> -Team "<equipo>"
```

Opcionales en los dos: `-WorkItemType` (por defecto `Product Backlog Item`), `-AreaPath` y `-Tags` (por defecto `DEVOPS`).

**1. `validar-function-existente.ps1`** marca cada punto con `[OK]`, `[AVISO]` o `[FALTA]`. Lo que está en `[FALTA]` impide seguir. Revisa:
- **Esta máquina:** Azure CLI con sesión iniciada en la suscripción y el SDK de .NET 10.
- **La Function:**
  - que exista y esté encendida;
  - que use **.NET 10 aislado**;
  - que sea solo HTTPS con TLS 1.2;
  - el acceso público y las restricciones de IP (iTop debe poder entrar);
  - el almacenamiento y la forma de publicar;
  - la identidad administrada;
  - **sus roles** (Website Contributor, Contributor u Owner);
  - la configuración `DevOps__*` que ya tenga.
- **Azure DevOps:**
  - que la organización esté conectada al **mismo tenant** de Entra ID que la Function;
  - con la sesión de usted: el proyecto, el equipo, el tipo de elemento, el área y el **sprint actual**;
  - si la identidad de la Function ya está agregada.

**2. `configurar-function-existente.ps1`** corre primero la validación y se detiene si algo falta. Luego:
1. Activa la identidad administrada si hace falta.
2. Carga `DevOps__*` y quita un PAT de pruebas si quedó alguno.
3. Publica el código.
4. Prueba sin crear nada en Azure DevOps:
   - sin llave debe responder 401;
   - con llave y un ticket vacío, 400.
5. Deja en `salida-<app>.local.env` la URL, la llave y el bloque listo para `config-itop.php`.

Al final imprime el **Object ID** e indica si la identidad ya está en Azure DevOps (paso 2 de abajo).

**Si usted no tiene permiso de escritura sobre la Function** (la publica su administrador):
1. **`preparar-para-administrador.ps1`**, con los mismos parámetros (y `-UsarPat` si aplica). Valida y compila, sin cambiar nada en Azure, y deja la carpeta `para-administrador\` con:
   - `ItopDevOpsBridge.zip`;
   - `configuracion.json`;
   - `INSTRUCCIONES.txt`, con los comandos exactos.

   El PAT no va en la carpeta: se le entrega al administrador aparte.
2. El administrador sigue `INSTRUCCIONES.txt`: carga la configuración (y el PAT), publica el zip y entrega la llave.
3. **`probar-function.ps1 -Subscription … -ResourceGroup … -AppName …`** solo necesita lectura y pide la llave en pantalla. Sin llave debe responder 401 y con llave, 400.

**Si Azure DevOps está en otro tenant que la Function.** La identidad administrada solo vale en su propio tenant. Para llegar al otro tenant se usa un registro de aplicación que confía en esa identidad (credencial federada). No lleva contraseñas ni secretos y no vence.

1. **`crear-acceso-entre-tenants.ps1`**, en el tenant de la Function. Lo corre alguien que pueda crear registros de aplicación y que vea la Function:
   ```powershell
   ./crear-acceso-entre-tenants.ps1 -Subscription "<id>" -ResourceGroup <grupo> -AppName <function> -DevOpsTenantId "<tenant de Azure DevOps>"
   ```
   - Crea el registro multitenant `devops-bridge-<function>` con la credencial federada.
   - Imprime su **Application (client) ID**.
2. **Un administrador del tenant de Azure DevOps** la da de alta una sola vez (rol Application Administrator o Cloud Application Administrator):
   ```powershell
   az login --tenant <tenant de Azure DevOps> --allow-no-subscriptions
   az ad sp create --id <Application ID>
   ```
3. **Un Project Collection Administrator** agrega `devops-bridge-<function>` en Azure DevOps, con acceso Basic y como Contributor del proyecto.
4. **Validar y configurar**: a los dos scripts de arriba se les agrega `-DevOpsTenantId <tenant de Azure DevOps> -DevOpsClientId <Application ID>`.

El tenant de Azure DevOps aparece en *Organization settings › Microsoft Entra*. El validador también lo muestra cuando no coincide.

**Alternativa con PAT, sin registro de aplicación.** Se agrega `-UsarPat` a los dos scripts. El PAT se pide en pantalla (no se muestra ni queda en el historial). El validador lo prueba contra el proyecto y el paso 2 lo carga en `DevOps__PersonalAccessToken`.
- **Cómo crearlo:** en Azure DevOps, *User settings › Personal access tokens*:
  - organización: la del proyecto;
  - permiso: **Work Items (Read & write)**.
- **En contra:**
  - vence (máximo un año): al renovarlo, se vuelve a correr el paso 2 con `-UsarPat`;
  - los PBI quedan creados a nombre de la persona dueña del PAT.

**Qué pedirle al administrador al crear la Function:**
- Runtime **.NET 10 (aislado)**. Con otra versión ItopDevOpsBridge no corre: la verificación lo avisa.
- Plan: Flex Consumption (recomendado) u otro.
- Si puede, **Identidad › Asignada por el sistema: Activado**.
- Para usted, **Website Contributor** sobre la Function.
- Que el servidor de iTop pueda salir por HTTPS a `*.azurewebsites.net`.

**Opción A, recursos que ya existen pero la Function la crea usted.** El administrador indica la suscripción, el grupo de recursos, la cuenta de almacenamiento y, si quiere, el Application Insights. Son dos pasos, con los mismos parámetros.

1. **Verificar:** `verificar-function.ps1` **no crea ni cambia nada**. Revisa:
   - la sesión y la suscripción;
   - el grupo de recursos y el almacenamiento;
   - el proveedor `Microsoft.Web` y la región (Flex Consumption con .NET 10);
   - el Application Insights indicado;
   - que el **nombre de la Function esté libre**;
   - **sus roles en el grupo** (Contributor u Owner);
   - el SDK de .NET 10.

   Si algo falta, dice qué es y a quién pedirlo.
2. **Crear:** `desplegar-function.ps1` **solo crea la Function**. No crea grupos ni almacenamiento ni registra proveedores. Además repite las verificaciones antes de empezar.

```powershell
cd devops-bridge
./verificar-function.ps1 -Subscription "<id>" -ResourceGroup <grupo> -StorageName <almacenamiento> -AppName func-devops-<empresa> `
   -Organization <organización> -Project <proyecto> -Team "<equipo>" [-AppInsights <appi existente>]
# Si dice "Todo en orden", el mismo comando con desplegar-function.ps1 crea la Function y publica el código.
```

**Qué preguntarle al administrador:**
- La suscripción y el grupo de recursos donde va la Function.
- La cuenta de almacenamiento que puede usar. Toda Function necesita una para su paquete y su estado.
- La región: debe admitir Flex Consumption con .NET 10. La verificación lo revisa.
- Application Insights: uno existente, o que se cree uno nuevo con el nombre de la app.
- El nombre de la Function App, que debe ser único en Azure.
- Sus permisos sobre ese grupo: crear la Function App, asignarle identidad y leer el almacenamiento. Normalmente *Contributor* del grupo.
- Que el proveedor `Microsoft.Web` esté registrado en la suscripción.
- Que el servidor de iTop pueda salir por HTTPS a `*.azurewebsites.net`.

**Opción B: crear todo desde cero** (pruebas o una suscripción propia). `desplegar.ps1` crea también el grupo de recursos y el almacenamiento, y registra los proveedores.

Para cualquiera de las dos opciones se necesitan Azure CLI y .NET 10 SDK, con la sesión iniciada en el tenant de la empresa (`az login --tenant <id>`).
```powershell
cd devops-bridge
dotnet test ItopDevOpsBridge.slnx            # 8 pruebas
./desplegar.ps1 -ResourceGroup rg-devops -Location centralus -AppName func-devops-<empresa> `
   -Organization <organización> -Project <proyecto> -Team "<equipo>" [-WorkItemType "Product Backlog Item"] [-Subscription <id>]
```
El script hace lo siguiente:
- registra los proveedores de recursos;
- crea el almacenamiento y la Function (Flex Consumption, .NET 10, Application Insights) con su **identidad administrada**;
- carga los parámetros `DevOps__*` y publica el código;
- deja la URL y la llave en `salida-<app>.local.env`. Ese archivo no se versiona: guárdelo en un lugar seguro;
- imprime el **Object ID** de la identidad.

### Paso 2: Permisos en Azure DevOps
El Project Collection Administrator agrega la identidad de la Function. Se busca por el nombre de la app.
- *Organization settings › Users › Add users*: acceso **Basic**.
- Agregarla al proyecto como **Contributor**.

Alternativa por API: está en `docs/devops-implementacion.md` (`serviceprincipalentitlements`).

### Paso 3: iTop
1. Copiar `extensiones/itop-devops` a `<itop>/extensions/`.
2. Quitar el atributo de solo lectura de `conf/production/config-itop.php` y agregar esta configuración:
   ```php
   // dentro de $MySettings
   'async_task_retries' => array(
       'AsyncItopDevOps' => array('max_retries' => 6, 'retry_delay' => 300, 'exponential_delay' => true),
   ),
   // dentro de $MyModuleSettings
   'itop-devops' => array(
       'function_url' => 'https://<app>.azurewebsites.net/api/itop/pbi',
       'function_key' => '<llave de salida-<app>.local.env>',
       'tag_code' => 'DEVOPS',
       'tag_attcode' => 'tags',
       'classes' => array('Incident'),   // agregar 'UserRequest' si también aplica a requerimientos
       'timeout' => 30,
   ),
   ```
3. Correr `/setup/` en modo **Upgrade** y marcar **iTop → Azure DevOps** en la página de extensiones.
   - La etiqueta DEVOPS se crea sola.
   - Si en producción ya existe un campo `tags` en los tickets, cambiar `tag_attcode` y revisar el XML de la extensión antes de instalar.

### Paso 4: Prueba
1. Crear un incidente y marcar **DEVOPS** en **Etiquetas**.
2. Esperar al cron, o correrlo.
3. El incidente debe quedar con **PBI de Azure DevOps**, **Enlace al PBI** y una nota en la bitácora privada.
4. El PBI debe aparecer en el sprint actual con las etiquetas `DEVOPS; iTop-<ref>`.

**Si algo falla:**
- Revisar *Administración de Datos* o la tabla `priv_async_task`; el campo `last_error` dice el motivo.
- Revisar los logs de la Function en Application Insights.
- Errores comunes:
  - 401: la llave de la Function está mal.
  - 422 "rechazó la identidad": falta el paso 2.
  - 422 con un tipo de elemento: el proceso del proyecto no tiene ese tipo.

**Verificado en pruebas:** el incidente I-000001 creó el PBI 1 en el sprint actual, autenticado por la identidad administrada. Al reenviarlo devolvió el mismo PBI, sin duplicar.

---

## 4. Recordatorio de cierre de tickets solucionados (propuesta, pendiente)

**Flujo actual:** el agente pasa el ticket a **Solucionado** y el **solicitante** lo cierra desde el portal (o lo reabre). Si el solicitante no lo cierra, queda abierto indefinidamente. iTop 3.0.2 trae el estímulo "Cierre Automático" (`ev_autoclose`), pero no está conectado a ningún paso desde Solucionado.

**Propuesta, con las piezas nativas de iTop (las mismas de los SLA):**
1. Una extensión pequeña agrega un cronómetro **"Tiempo en Solucionado"** a incidentes y requerimientos. Corre solo en el estado *Solucionado* y lo revisa el cron.
2. Tiene estos umbrales:
   - **24 h:** recordatorio al solicitante.
   - **72 h (opcional):** segundo recordatorio.
   - **N días (opcional):** cierre automático con `ev_autoclose`, que se conecta a una transición Solucionado → Cerrado, y una nota en la bitácora.
3. El correo es una notificación de iTop (*Configuración › Notificaciones*): disparador "al alcanzar umbral" y acción de correo al solicitante, con enlace al ticket en el portal para cerrarlo o reabrirlo. El texto se edita sin programar.

**Decisiones pendientes antes de construirlo:**
- ¿Horas corridas u horas hábiles? Si son hábiles, ¿qué horario?
- ¿Solo recordatorio, o también cierre automático? ¿A los cuántos días?
- ¿Con copia al agente?
- ¿Aplica a incidentes, requerimientos o ambos?
