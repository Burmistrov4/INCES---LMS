# MEMORY.md — INCES LMS

> Memoria operativa para que un agente AI pueda retomar el proyecto sin reconstruir todo el historial.

## 0. Lectura obligatoria

1. MEMORY.md
2. docs/AUDITORIA_RENDIMIENTO_2026-10-08.md
3. PLAN_MAESTRO.md
4. PLAN_CIERRE_100_FUNCIONAL_2026.md
5. git status --short

## 1. Identidad

- Proyecto: INCES-LMS-PROJECT, LMS para INCES La Isabelica.
- Stack: Flutter Web + Fastify 5/TypeScript/Zod + Supabase PostgreSQL/RLS + Cloudflare R2 + Playwright.
- Producción: https://inces-lms.pages.dev/
- API: https://inces-lms-api.onrender.com
- Cloud/Local/offline: FUERA DE ALCANCE; pertenecía a otro proyecto.

## 2. Secuencia vigente

F1 correo/recovery: DEFERIDA.
1. Performance.
2. Responsive 375 / 768 / 1024 / 1280 / 1440.
3. UI/UX global.
4. 3D/animaciones sólo si no degradan rendimiento.
5. Android.
6. Regresión y auditoría final.

## 3. Estado funcional

- Aula Virtual real: 7/7 PASS.
- Flutter focalizado: 84/84 PASS.
- Backend verify: 658/658 PASS.
- Invitaciones docentes: 19/19 PASS.
- R2/archivos: 52/52 PASS.
- Planilla F2: VERDE/CERRADA.
- Pages: HTTP 200.
- API Render: HTTP 200 después de cold start; CORS correcto.
- SEM-SOL-CL: Soldadura Básica, sin [SEMILLA].
- F1: NO CERRADA; requiere proveedor válido y recepción real.

## 4. Corrección crítica reciente

LibroEntrega conserva m6_entregas.id como entregaId. calificar/devolver deben recibir entregaId real, no estudianteId.

Build E2E correcto usa:
flutter build web --release --dart-define-from-file=.env.json --output build/e2e-web-fixed

Un build sin dart-define-from-file puede fallar porque String.fromEnvironment queda vacío.

## 5. Performance actual

- build/web-final: ~41.43 MiB, 39 archivos.
- WASM: 27.50 MiB.
- symbols: 8.18 MiB.
- JS: 4.01 MiB.
- main.dart.js: 3.57 MiB sin compresión.
- Producción sirve Brotli.
- Producción estaba en max-age=0, must-revalidate.
- Se añadió web/_headers para mejorar caché; falta reconstruir/desplegar/verificar.
- Renderer no cambiado.
- Siguiente candidato: medir obtenerTodos()/SupabaseService.todos() y su payload antes de paginar.

## 6. Restricciones

- Flutter analyze/test/build local ha sufrido ERROR_PIPE_BUSY 231; CI es referencia de build/test y node devops/analizar-dart.mjs es sustituto de análisis de tipos.
- E2E local es sensible a proxy, CORS, puertos y teardown.
- String.fromEnvironment se resuelve en build; .env.json no es runtime.
- RLS es frontera de autorización.
- Migraciones YYYYMMDDNNN_*.sql; no editar aplicadas.
- No borrar datos reales ni tareas E2E con SQL destructivo fuera de mecanismo documentado.

## 7. Git y artefactos

git status tiene cambios históricos y documentos/probes sin seguimiento. No limpiar a ciegas. Primero clasificar evidencia vs basura temporal.

## 8. Secretos

e2e/.env.e2e contiene credenciales E2E. Nunca copiar contraseñas, tokens, anon keys o service keys a documentación.

## 9. Deudas

- ~54 tareas E2E de prueba tipo Tarea E2E [ciclo] siguen en Supabase según último conteo; limpieza controlada pendiente.
- F1 diferida.
- Responsive/UI/UX/3D/Android pendientes.
- Validación física de cámara Android pendiente.
- F11 producción global todavía no cerrada.

## 10. Handover

Al terminar cada sesión actualizar MEMORY.md, docs/AUDITORIA_RENDIMIENTO_2026-10-08.md y PLAN_CIERRE_100_FUNCIONAL_2026.md. Cambiar PLAN_MAESTRO.md sólo si cambia arquitectura/alcance.

Registrar siempre: fecha/hora, comando, resultado, archivos modificados, pruebas posteriores y siguiente discriminador.

## 11. Último avance de Performance — 2026-10-08

- web/_headers preparado, pero Flutter build no lo copia al output por sí solo.
- Se creó devops/preparar-cloudflare-pages.mjs para copiarlo después del build.
- Prueba local sobre build/web-final-perf: copia correcta.
- Producción con Brotli: main.dart.js ~1.075 MB transferidos; CanvasKit WASM ~2.86 MB; HTML 728 B; bootstrap 5.2 KB.
- Baseline de tiempos desde la máquina de trabajo: HTML ~0.23–0.31 s; bootstrap ~0.26–0.35 s; main.dart.js ~0.69–1.07 s; CanvasKit WASM ~0.86–1.06 s.
- P-01 sigue abierto hasta que el build/deploy real de Pages incluya _headers y HEAD devuelva la política nueva.

### Verificación post-cambio

- Primer intento de flutter test falló antes de ejecutar pruebas por una variable de entorno ausente: PROGRAMFILES(X86). No fue fallo de código.
- Segundo intento, definiendo PROGRAMFILES(X86) sólo para el proceso, terminó **84/84 PASS**, exit 0, **27.75 s**.
- El build release con el cambio de headers terminó correctamente: flutter build web --release --dart-define-from-file=.env.json --output build/web-final-perf, **116.2 s**, exit 0.
- Wasm dry-run del build: PASS; sólo warning informativo que recomienda probar --wasm. No se cambia renderer en esta fase.
## 12. P-02 completado — 2026-10-08

- Se midieron consultas Supabase reales autenticadas.
- AspiranteGateway.todos() no tiene consumidores en lib/; no se refactorizó.
- aspirantes select=* admin: 27 filas / 26,859 B.
- Proyección mínima aspirantes: 27 / 5,529 B.
- miFicha(): 1 fila / 1,348 B con relación.
- miFicha() cambió de select(*, programs(name)) a proyección explícita de los campos que consume AspiranteModel; bytes actuales siguen en 1,348 B. No reclamar reducción de bytes; la mejora evita crecimiento silencioso futuro.
- Regresión focalizada: 85/85 PASS, 76.25 s.
- P-02: VERIFICADO LOCAL/CERRADO.
- P-01: sigue ABIERTO; web/_headers preparado y helper devops/preparar-cloudflare-pages.mjs creado. No hay token Cloudflare local ni workflow de Pages; no hacer push automático.
- Se crearon docs/AI_AGENT_OPERATING_PROTOCOL.md y AUTONOMOUS_AGENT_MASTER_PROMPT.md.
- Probes temporales usados para medición fueron eliminados; no quedan e2e/_probe*.mjs.
- Próximo discriminador: cargas reales por rol/Mis Aulas/Aula Virtual/Inscripciones/cPanel.


## 13. CONTRATO DE AUTONOMÍA AI v2 — 2026-10-08

Se reforzó el handover para agentes autónomos:

- `docs/AI_AGENT_OPERATING_PROTOCOL.md` ampliado con máquina de estados, continuidad entre hitos, política de credenciales E2E, anti-parálisis, límites de reintento, gates de fase, auditoría final y clasificación H1/H2/H3/H4.
- `AUTONOMOUS_AGENT_MASTER_PROMPT.md` reemplazado por **PROMPT MAESTRO v2**, orientado a ejecución autónoma de extremo a extremo.
- El agente debe continuar automáticamente después de cerrar cada hito y sólo puede solicitar intervención humana por:
  - H1 credencial externa que sólo el usuario puede proporcionar;
  - H2 autorización irreversible;
  - H3 decisión de producto genuinamente ambigua;
  - H4 infraestructura externa que exige login interactivo.
- Para E2E puede y debe generar credenciales temporales/datos sintéticos cuando exista un mecanismo legítimo.
- No puede saltarse MFA/CAPTCHA/RLS ni imprimir secretos.
- Un bloqueo humano no detiene el resto del proyecto: debe completar todo lo independiente y dejar preparado el desbloqueo.
- Si el proyecto no está terminado, no debe declararlo terminado.
- Si queda intervención humana, debe crear `docs/BLOQUEADORES_HUMANOS_<fecha>.md` con evidencia y acción exacta.
- Al cierre global debe generar `docs/CIERRE_FINAL_<fecha>.md`.

### Siguiente ejecución

La prioridad no cambió:
**Performance → P-01 Cloudflare real → Responsive → UI/UX → Animaciones/3D → Android → regresión total → producción → cierre documental.**

Próximo discriminador de Performance:
dashboard por rol + Mis Aulas + Aula Virtual + Inscripciones/catálogo + cPanel.
