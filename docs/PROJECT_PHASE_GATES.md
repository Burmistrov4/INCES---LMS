# GATES DE FASE — INCES LMS

## Regla
Ninguna fase se declara cerrada por sensación. Cada gate exige evidencia.

## G0 — Baseline
Estado del repo, rama, procesos, artefactos y tests disponibles. Salida: baseline reproducible y bloqueadores clasificados.

## G1 — Funcionalidad
Flujo completo, persistencia, autorización, estados de UI, errores, pruebas y E2E donde aplique.

## G2 — Seguridad
Auth, RLS, permisos, secretos, endpoints, storage y separación de datos reales/seed. No desactivar seguridad como workaround.

## G3 — Performance
Medir antes/después: peso, requests, payload, tiempos, cold start, consultas, renders y memoria cuando sea posible. Optimizar primero el mayor coste medido.

## G4 — Responsive
Viewports mínimos: 375, 768, 1024, 1280 y 1440. Probar navegación, tablas, formularios, modales, overflow, touch y teclado.

## G5 — UX/A11y
Foco, labels, contraste, teclado, mensajes, loading/empty/error, semántica y consistencia.

## G6 — Motion/3D
Sólo después de G3/G4. Cada efecto debe tener presupuesto y fallback.

## G7 — Android
Build, navegación, autenticación, APIs, almacenamiento, cámara/QR si aplica y rendimiento básico.

## G8 — Regresión
Suite crítica, seguridad, E2E, smoke, tests de fase y análisis estático disponible.

## G9 — Producción
Deploy, HEAD real, assets, API, CORS, Auth, smoke de usuario real y errores.

## G10 — Auditoría final
Buscar TODO/FIXME, stubs, dead code, rutas/endpoints huérfanos, localhost, secretos, seeds visibles, flags temporales, documentación contradictoria, migraciones pendientes y regresiones.

## Cierre
CERRADO sólo si no quedan defectos técnicos conocidos sin clasificación.

## Continuidad
Si falla un gate: AISLAR → CORREGIR → PROBAR → REGRESAR.
Si existe H1–H4: PREPARAR → DOCUMENTAR → CONTINUAR OTRAS FASES → REVISITAR.
Nunca convertir un gate fallido en final de sesión.
