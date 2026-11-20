# Guía de pasos: iTop (mesa de servicio)

Esta guía cubre cuatro trabajos:

1. **Réplica local** de iTop con las mismas versiones de producción.
2. **Actualización** de iTop 3.0.2 a la versión más reciente, ensayada primero en la réplica.
3. **KADSI → Azure DevOps**: un incidente con la etiqueta KADSI crea un PBI en el sprint actual.
4. **Recordatorio de cierre** de tickets solucionados (propuesta).

| Carpeta | Contenido |
|---|---|
| `extensiones/kadsi-devops/` | Extensión de iTop: campo Etiquetas, campos del PBI y envío asíncrono con reintentos |
| `kadsi-bridge/` | Azure Function .NET 10 (`KadsiBridge`), pruebas y script de despliegue `desplegar.ps1` |
| `entorno-plantillas/` | Configuración de MySQL, Apache y PHP de la réplica (`{RAIZ}` = carpeta del proyecto) |
| `docs/` | Plan de actualización, propuesta y detalle de KADSI, capturas de la instalación |
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
   - las extensiones `kadsi-devops` y la del recordatorio de cierre.
6. **Producción:**
   - ventana de mantenimiento;
   - los mismos pasos ensayados;
   - verificación en "Acerca de iTop";
   - plan de reversa: restaurar el respaldo del paso 3.
7. **Evidencia:** captura de antes y después de "Acerca de iTop", comandos de respaldo, capturas del asistente, problemas encontrados y tiempos.

---

## 3. KADSI → PBI en Azure DevOps

El agente marca **KADSI** en el selector **Etiquetas** del incidente. iTop envía el ticket por su cola, con reintentos, a la Azure Function **KadsiBridge**. La Function entra a Azure DevOps **por el tenant**, con la identidad administrada y sin PAT. Ahí busca si ya hay un PBI para ese ticket, consulta el **sprint actual** del equipo y crea el PBI. Después le devuelve a iTop el número y el enlace.

Detalle de parámetros, API y diseño: `docs/kadsi-implementacion.md` y `docs/propuesta-kadsi-azure-devops.md`.

### Requisitos
- La organización de Azure DevOps conectada al tenant de Entra ID de la empresa.
- Un proyecto con el tipo de elemento deseado: *Product Backlog Item* en Scrum, *User Story* en Agile o *Issue* en Basic.
- Un equipo con sprints que tengan fechas.
- Una suscripción de Azure en ese tenant, con permiso para crear recursos.
- Una persona con rol **Project Collection Administrator** en Azure DevOps.
- Que el servidor de iTop pueda salir por HTTPS a `*.azurewebsites.net`.
- El cron de iTop funcionando.

### Paso 1: Function en Azure
Se necesitan Azure CLI y .NET 10 SDK, con la sesión iniciada en el tenant de la empresa (`az login --tenant <id>`).
```powershell
cd kadsi-bridge
dotnet test KadsiBridge.slnx            # 8 pruebas
./desplegar.ps1 -ResourceGroup rg-kadsi -Location centralus -AppName func-kadsi-<empresa> `
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

Alternativa por API: está en `docs/kadsi-implementacion.md` (`serviceprincipalentitlements`).

### Paso 3: iTop
1. Copiar `extensiones/kadsi-devops` a `<itop>/extensions/`.
2. Quitar el atributo de solo lectura de `conf/production/config-itop.php` y agregar esta configuración:
   ```php
   // dentro de $MySettings
   'async_task_retries' => array(
       'AsyncKadsiDevOps' => array('max_retries' => 6, 'retry_delay' => 300, 'exponential_delay' => true),
   ),
   // dentro de $MyModuleSettings
   'kadsi-devops' => array(
       'function_url' => 'https://<app>.azurewebsites.net/api/kadsi/pbi',
       'function_key' => '<llave de salida-<app>.local.env>',
       'tag_code' => 'KADSI',
       'tag_attcode' => 'tags',
       'classes' => array('Incident'),   // agregar 'UserRequest' si también aplica a requerimientos
       'timeout' => 30,
   ),
   ```
3. Correr `/setup/` en modo **Upgrade** y marcar **KADSI → Azure DevOps** en la página de extensiones.
   - La etiqueta KADSI se crea sola.
   - Si en producción ya existe un campo `tags` en los tickets, cambiar `tag_attcode` y revisar el XML de la extensión antes de instalar.

### Paso 4: Prueba
1. Crear un incidente y marcar **KADSI** en **Etiquetas**.
2. Esperar al cron, o correrlo.
3. El incidente debe quedar con **PBI de Azure DevOps**, **Enlace al PBI** y una nota en la bitácora privada.
4. El PBI debe aparecer en el sprint actual con las etiquetas `KADSI; iTop-<ref>`.

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
