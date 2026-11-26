# devops-diario

Consola para el día a día en Azure DevOps. Entra con su cuenta de Microsoft Entra ID; no usa PAT.

```powershell
cd devops-diario
dotnet run
```

La primera vez:
1. Pide el **tenant ID** (en Azure DevOps: *Organization settings › Microsoft Entra*).
2. Abre el navegador para iniciar sesión.
3. Le deja escoger organización, proyecto y equipo.

Lo guarda en `%LOCALAPPDATA%\devops-diario\` (fuera del repositorio). La opción 3 del menú lo cambia.

| Opción | Qué hace |
|---|---|
| 1. Mis IDs de hoy | Work items asignados a usted con la fecha en el título (`26/11/2026`). Termina con la lista de IDs para copiar. |
| 2. Crear IDs del día | Escoge ayer, hoy o ambos. Muestra lo que va a crear, lo que ya existe y los PBI omitidos, y pide confirmación. |

La opción 2 crea, para cada fecha:
- en el PBI **Daily** del sprint actual, su tarea `26/11/2026 Daily`;
- en cada PBI en **Committed** asignado a usted cuyo título empieza con el prefijo, la tarea `26/11/2026 Se trabaja en <título del PBI>`;
- nada en los PBI sin el prefijo: solo se listan.

No crea una tarea si el padre ya tiene una suya con esa fecha. "Ayer" es el día hábil anterior: un lunes, el viernes.

**Ajustes en `Reglas.cs`:**
- el **prefijo** de los PBI (marcado con `AQUÍ VA SU PREFIJO`);
- el título del PBI Daily y el estado de los PBI;
- el formato de los títulos y si solo toma los PBI asignados a usted.

Sin navegador: `dotnet run -- --codigo` (código de dispositivo). Con la sesión de Azure CLI: `dotnet run -- --cli`.
