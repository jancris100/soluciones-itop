# Plan: actualizar iTop 3.0.2 a la versión más reciente

**Punto de partida (igual que producción):** iTop 3.0.2-1-9957 (compilada el 2022-09-12), MySQL 8.0.34, PHP 8.2.26.
Este entorno local es la copia de ensayo: cada paso se prueba aquí, se documenta con capturas y luego se repite en producción.

## Versión destino

La versión más reciente en GitHub de Combodo es la **3.3.0**, que **sube el mínimo de PHP a 8.2** ([notas](https://github.com/Combodo/iTop/releases/tag/3.3.0)). La rama estable anterior es **3.2.x** (3.2.3-x). Antes de empezar hay que confirmar en [las versiones de iTop](https://github.com/Combodo/iTop/releases) cuál es la última estable y sus requisitos exactos de PHP y MySQL.

Con PHP 8.2.26 y MySQL 8.0.34, **probablemente no haga falta cambiar PHP**: 8.2 cumple el mínimo de 3.3. Hay que verificar que la versión destino no exija una versión de PHP o de MySQL más nueva.

## Pasos

1. **Inventario de producción**
   - Versión exacta: Acerca de iTop.
   - Extensiones instaladas y personalizaciones: carpeta `extensions/` y `env-production`.
   - Tamaño de la base.
   - Tareas programadas: `cron.php`.
   - Integraciones: correo entrante y API REST.
2. **Respaldo completo**
   - Base de datos con `mysqldump` o el respaldo de iTop.
   - Carpeta completa de iTop, incluidos `conf/production/config-itop.php`, `extensions/` y `data/`.
3. **Ensayo en este entorno**
   - Restaurar aquí el respaldo de producción, o una copia anonimizada.
   - Descargar la versión destino, reemplazar los archivos (sin borrar `conf/` ni `data/`) y ejecutar el asistente `/setup` en modo **Actualizar**.
   - Revisar que cada extensión tenga versión compatible con el destino.
   - Pruebas: entrar, crear y cerrar un ticket, notificaciones, correo entrante, `cron.php` y reportes.
4. **Producción**
   - Ventana de mantenimiento.
   - Repetir exactamente los pasos ensayados.
   - Verificación y plan de reversa: restaurar el respaldo del paso 2.
5. **Documentación**
   - Cada paso con capturas y comandos.
   - Problemas encontrados y cómo se resolvieron.
   - Tiempos reales.

## Qué documentar en cada etapa

| Etapa | Evidencia |
|---|---|
| Antes | Captura de "Acerca de iTop", lista de extensiones, versión de PHP (`php -v`) y MySQL |
| Respaldo | Nombre y tamaño de los archivos, comando usado |
| Actualización | Capturas del asistente, mensajes y advertencias |
| Después | Nueva captura de "Acerca de iTop", pruebas realizadas y resultado |
