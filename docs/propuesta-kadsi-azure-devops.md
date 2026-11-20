# Recomendación: incidente de iTop marcado KADSI → PBI en el sprint actual de Azure DevOps

**Objetivo:** al crear (o marcar después) un incidente con **KADSI**, se crea un *Product Backlog Item* en Azure DevOps:
- con el título y la descripción del incidente;
- en el **sprint actual** del equipo;
- sin duplicados;
- y el incidente queda con el número y el enlace del PBI.

## Resumen de la recomendación

```
iTop — Crear incidente (selector "Etiquetas" = KADSI)
   └─ disparador "al crear" / "al actualizar" (filtro OQL: KADSI y sin PBI)
        └─ acción Webhook (asíncrona, por la cola del cron de iTop)
             └─ HTTPS ─▶ Azure Function (.NET) con identidad administrada del tenant
                           1. busca si ya existe un PBI para ese incidente (sin duplicados)
                           2. consulta el sprint actual del equipo
                           3. crea el PBI en ese sprint
                           4. escribe de vuelta en iTop: número, enlace y nota en el registro
```

## 1. Dónde se marca KADSI en el formulario

En iTop 3.0 estándar, el incidente **no** tiene un campo de etiquetas; solo las FAQ lo usan. Lo comprobé en el modelo de datos de la réplica. Los selectores que trae el formulario son:
- Origen: correo, teléfono, portal, monitoreo;
- Servicio;
- Subcategoría de servicio.

Si en producción ya existe un selector o campo para KADSI, se usa ese. Basta con saber su nombre interno, que aparece en *Herramientas Administrativas › Modelo de Datos › Incidente*. Si no existe:

| Opción | Cómo se ve al crear el incidente | Recomendación |
|---|---|---|
| **Campo "Etiquetas" (TagSet) en los tickets** | Un selector de etiquetas con chips; KADSI se elige de la lista y se administra en *Administración de Datos › Configuración de Etiquetas*. | **Recomendada.** Es lo que se describe como "un tag", sirve para futuras etiquetas, y se filtra con `etiquetas MATCHES 'KADSI'`. Requiere una extensión pequeña. |
| Subcategoría de servicio "KADSI" | Se elige en el selector de subcategoría que ya existe. | Sin código, pero mezcla "a quién se escala" con "qué servicio es". Sirve como solución temporal. |

La misma extensión agrega dos campos de solo lectura en el incidente: **PBI de Azure DevOps** (número) y su **enlace**, más la nota en el registro público.

## 2. Cómo sale de iTop

- **Disparadores nativos de iTop:** "al crear objeto" y "al actualizar objeto", con el filtro OQL `SELECT Incident WHERE etiquetas MATCHES 'KADSI' AND devops_id = ''`. Así funciona también si alguien agrega KADSI después de crear el incidente.
- **Acción Webhook:**
  - Primera opción: la extensión oficial de Combodo *Webhook integration*. Envía las llamadas por la cola asíncrona del cron, así que guardar el incidente no se vuelve lento ni falla si Azure no responde. **Hay que confirmar en la réplica que es compatible con 3.0.2**; si no, la misma extensión de etiquetas incluye un envío propio por la cola asíncrona de iTop.
- **Requisito:** el servidor de iTop debe poder salir por HTTPS a Azure.
  - Si no puede, el plan B es que la Azure Function **consulte** la API REST de iTop cada 5 minutos.
  - En ese caso Azure necesita llegar a iTop, y el aviso tarda un poco más.

## 3. La Azure Function (el puente)

**Autenticación por el tenant, sin PAT:** la Function tiene una **identidad administrada** de Entra ID. Una persona con rol *Project Collection Administrator* la agrega a la organización de Azure DevOps con licencia **Basic** y solo con permiso de crear y editar elementos de trabajo en el proyecto. La Function pide su token a Entra ID y llama la API REST de Azure DevOps.

Pasos por cada incidente:

1. **Sin duplicados:** busca con WIQL si ya existe un PBI con la etiqueta `iTop-I-000123`. Si existe, solo reescribe el enlace en iTop.
2. **Sprint actual:** `GET https://dev.azure.com/{org}/{proyecto}/{equipo}/_apis/work/teamsettings/iterations?$timeframe=current&api-version=7.1` → `System.IterationPath`.
   - El sprint es **por equipo**, así que se configura qué equipo recibe los PBI de KADSI.
   - Si no hay sprint activo (entre sprints), el PBI queda en el backlog del equipo y se avisa en el registro del incidente.
3. **Crear el PBI:** `POST .../_apis/wit/workitems/$Product%20Backlog%20Item?api-version=7.1`, con los campos:
   - `System.Title`: `[I-000123] <título del incidente>`
   - `System.Description`: la descripción del incidente más el enlace al incidente en iTop.
   - `System.IterationPath`: el sprint actual. `System.AreaPath`: el área del equipo.
   - `System.Tags`: `KADSI; iTop-I-000123`.
   - `Microsoft.VSTS.Common.Priority`: la prioridad de iTop. Crítica → 1, Alta → 2, Media → 3, Baja → 4.
4. **De vuelta en iTop:** con la API REST de iTop (`core/update`) guarda el número y el enlace del PBI y deja una nota en el registro público: *"PBI 4567 creado en Sprint 23"*.
   - Lo hace con un usuario técnico de iTop con perfil *REST Services User*, cuya contraseña va en Key Vault.

**Costo:** el plan de consumo de Azure Functions cobra por ejecución; para algunos tickets al día es prácticamente cero. La licencia Basic de la identidad cuenta como un usuario de Azure DevOps.

## 4. Por qué esta opción y no otras

| Alternativa | Por qué no como primera opción |
|---|---|
| Logic App / Power Automate | El conector de Azure DevOps suele quedar con la cuenta de una persona, y si esa persona sale el flujo se cae. La lógica del sprint actual y la de no duplicar es más incómoda. |
| PAT (token personal) en iTop | El token queda en el servidor de iTop, vence y está ligado a una persona. Usted pidió conectar por el tenant. |
| Que iTop llame directo a Azure DevOps | iTop no maneja tokens de Entra ID y habría que guardar secretos en iTop. Además, el sprint actual y la escritura de vuelta quedarían mezclados en el modelo de iTop. |
| Consultar iTop cada 5 minutos (plan B) | Válido si iTop no puede salir a internet, pero requiere que Azure llegue a iTop y no es inmediato. |

## 5. Lo que necesito saber

1. **En producción:** ¿el selector que vio en "Crear incidente" es un campo propio? ¿Cómo se llama? Una captura del formulario basta.
2. **Azure DevOps:** organización, proyecto, **equipo** cuyo sprint recibe los PBI, y área.
3. **Red:** ¿el servidor de iTop de producción puede salir por HTTPS a internet?
4. **Permisos:** quién tiene el rol *Project Collection Administrator* para agregar la identidad de la Function.
5. **Suscripción de Azure** del mismo tenant donde crear la Function y el Key Vault.

## 6. Plan de trabajo (en la réplica primero)

1. Extensión: campo Etiquetas + campos del PBI, probada en la réplica 3.0.2. También hay que probarla en la versión destino de la actualización.
2. Azure Function con identidad administrada: sprint actual, creación del PBI sin duplicados y escritura de vuelta.
3. Disparador y webhook en iTop, y prueba de punta a punta con un proyecto de prueba en Azure DevOps.
4. Paso a producción y documentación con capturas.

Referencias: [Webhook integration (Combodo)](https://store.itophub.io/en_US/products/combodo-webhook-integration) · [Service principals y managed identities en Azure DevOps](https://learn.microsoft.com/azure/devops/integrate/get-started/authentication/service-principal-managed-identity)
