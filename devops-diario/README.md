# devops-diario

Consola para el día a día en Azure DevOps. Entra con su cuenta de Microsoft Entra ID; no usa PAT.

## Variables (se definen una vez)

| Variable | Qué es |
|---|---|
| `DEVOPS_DIARIO_TENANT_ID` | Tenant de Microsoft Entra donde está su Azure DevOps (*Organization settings › Microsoft Entra*). Obligatoria. |
| `DEVOPS_DIARIO_PREFIJO_PBI` | Prefijo de los PBI que reciben tarea. Sin ella, `HU`. |
| `DEVOPS_DIARIO_ORGANIZACION`, `_PROYECTO`, `_EQUIPO` | Opcionales: si están, no se preguntan. |

Hay dos formas de definirlas; use una:
- **Globales de Windows**: con `setx`, y después abra otra consola.
  ```powershell
  setx DEVOPS_DIARIO_TENANT_ID "<tenant id>"
  setx DEVOPS_DIARIO_PREFIJO_PBI "<prefijo>"
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
- en el PBI **Daily** del sprint actual, su tarea `26/11/2026 Daily`;
- en cada PBI en **Committed** asignado a usted cuyo título empieza con el prefijo, la tarea `26/11/2026 Se trabaja en <título del PBI>`;
- nada en los PBI sin el prefijo: solo se listan.

No crea una tarea si el padre ya tiene una suya con esa fecha. "Ayer" es el día hábil anterior: un lunes, el viernes.

**Otros ajustes en `Reglas.cs`:** el título del PBI Daily, el estado de los PBI, el formato de los títulos y si solo toma los PBI asignados a usted.

Sin navegador: `dotnet run -- --codigo` (código de dispositivo). Con la sesión de Azure CLI: `dotnet run -- --cli`.
