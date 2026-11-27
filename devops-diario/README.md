# devops-diario

Ventana (y consola) para el día a día en Azure DevOps. Entra con su cuenta de Microsoft Entra ID; no usa PAT.

## Ventana (recomendada)

```powershell
cd devops-diario
.\instalar-ventana.ps1
```

Crea `devops-diario.exe` en `%LOCALAPPDATA%\devops-diario\app` y el acceso directo **DevOps diario** en el escritorio.
Después de un `git pull`, córralo otra vez para actualizarla.

- **Crear tareas:** escoge la fecha (o Ayer / Hoy) y muestra el Daily y sus PBI en Committed.
  - Cada tarea es fecha + prefijo + título del PBI. El prefijo se edita en cada fila y la ventana recuerda el último por PBI.
  - Las horas se reparten solas (Daily 0,25 y el resto de 7,50) y se pueden cambiar; el total de 7,50 es una guía, no obligatorio.
  - Si falta un PBI, se crea ahí mismo (en Committed, en el sprint y asignado a usted) y queda en la lista.
  - Lo que ya existe para esa fecha aparece en gris y no se vuelve a crear.
- **Mis IDs:** los work items con la fecha en el título y un botón para copiar los IDs.

## Consola

## Variables (se definen una vez)

| Variable | Qué es |
|---|---|
| `DEVOPS_DIARIO_TENANT_ID` | Tenant de Microsoft Entra donde está su Azure DevOps (*Organization settings › Microsoft Entra*). Obligatoria. |
| `DEVOPS_DIARIO_PREFIJO` | Prefijo que llevan las tareas de los PBI (no filtra PBI). También sirve el nombre viejo `DEVOPS_DIARIO_PREFIJO_PBI`. |
| `DEVOPS_DIARIO_FORMATO_TAREA` | Opcional. Título de la tarea de un PBI con `{fecha}`, `{prefijo}` y `{pbi}`. Sin ella: `{fecha} {prefijo} Se trabaja en {pbi}`. |
| `DEVOPS_DIARIO_CAMPO_HORAS` | Opcional. Campo de las horas. Sin ella usa Completed Work, o Remaining Work si el proceso es Scrum. |
| `DEVOPS_DIARIO_ORGANIZACION`, `_PROYECTO`, `_EQUIPO` | Opcionales: si están, no se preguntan. |

Hay dos formas de definirlas; use una:
- **Globales de Windows**: con `setx`, y después abra otra consola.
  ```powershell
  setx DEVOPS_DIARIO_TENANT_ID "<tenant id>"
  setx DEVOPS_DIARIO_PREFIJO "<prefijo>"
  ```
- **`Properties\launchSettings.json`**: copie `Properties\launchSettings.example.json` con ese nombre y llene los valores.
  - Es el archivo que lee `dotnet run`.
  - No se sube a git, para que el tenant no quede en el repositorio.
  - Si lo usa, sus valores mandan sobre las variables globales.

## Uso

```powershell
cd devops-diario
dotnet run
```

La primera vez abre el navegador para iniciar sesión y le deja escoger organización, proyecto y equipo. Lo guarda en `%LOCALAPPDATA%\devops-diario\`; la opción 3 del menú lo cambia.

| Opción | Qué hace |
|---|---|
| 1. Mis IDs de hoy | Work items asignados a usted con la fecha en el título (`26/11/2026`). Termina con la lista de IDs para copiar. |
| 2. Crear IDs del día | Escoge ayer, hoy o ambos. Muestra lo que va a crear, lo que ya existe y los PBI omitidos, y pide confirmación. |

La opción 2 crea, para cada fecha:
- en el PBI **Daily** del sprint actual, su tarea `26/11/2026 Daily`, con 0,25 h;
- en cada PBI en **Committed** asignado a usted, la tarea `26/11/2026 <prefijo> Se trabaja en <título del PBI>`.

**Horas:** la jornada es de 7,50 h. El Daily lleva 0,25 h y las tareas de PBI se reparten las 7,25 h restantes:
- con una o dos tareas, se reparten solas en cuartos de hora (una: 7,25; dos: 3,75 y 3,50);
- con más de dos, o si ese día ya tenía tareas, pregunta las horas de cada una y va mostrando cuánto lleva de 7,50.
  Enter acepta la sugerida y la última propone lo que falta.

No crea una tarea si el padre ya tiene una suya con esa fecha. "Ayer" es el día hábil anterior: un lunes, el viernes.

**Otros ajustes en `Reglas.cs`:** la jornada (7,50), las horas del Daily (0,25), con cuántas tareas reparte solo (2), el título del PBI Daily, el estado de los PBI y si solo toma los PBI asignados a usted.

Sin navegador: `dotnet run -- --codigo` (código de dispositivo). Con la sesión de Azure CLI: `dotnet run -- --cli`.
