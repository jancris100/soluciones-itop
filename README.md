# solucionesITOP

Trabajo sobre la mesa de servicio **iTop**:

- réplica local con las mismas versiones de producción (iTop 3.0.2-1-9957, PHP 8.2.26, MySQL 8.0.34);
- plan para actualizar a la versión más reciente;
- integración **iTop → PBI en Azure DevOps**, por tenant de Entra ID;
- propuesta de recordatorio de cierre de tickets solucionados.

**Todos los pasos están en [GUIA-PASOS.md](GUIA-PASOS.md).**

| Carpeta | Contenido |
|---|---|
| `extensiones/itop-devops/` | Extensión de iTop (etiquetas + envío a Azure DevOps) |
| `devops-bridge/` | Azure Function .NET 10 con sus pruebas. Scripts: `validar-function-existente.ps1` y `configurar-function-existente.ps1` (el administrador ya creó la Function), `verificar-function.ps1` y `desplegar-function.ps1` (recursos existentes) y `desplegar.ps1` (todo desde cero) |
| `entorno-plantillas/` | Configuración de MySQL, Apache y PHP de la réplica |
| `docs/` | Plan de actualización, diseño de la integración con Azure DevOps y capturas de la instalación |

Los binarios (PHP, MySQL, iTop), las bases de datos y las credenciales **no** están en el repositorio. Se recrean con la guía.
