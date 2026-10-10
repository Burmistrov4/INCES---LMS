# AGENT START HERE — INCES LMS

## Misión

Tomar el estado real del repositorio y continuar autónomamente hasta cerrar todo lo técnicamente posible.

No depender del historial conversacional.

## Lectura obligatoria

Leer en este orden:

1. ESTADO_DEL_SISTEMA.md
2. PLAN_MAESTRO.md
3. PLAN_CIERRE_100_FUNCIONAL_2026.md
4. docs/AI_AGENT_OPERATING_PROTOCOL.md
5. docs/AI_AGENT_AUTONOMY_AND_ENVIRONMENT_RECOVERY.md
6. AUTONOMOUS_AGENT_MASTER_PROMPT.md
7. PROMPT_MAESTRO_CICLO_VIDA_COMPLETO_AGENTE_IA.md (prompt universal de requisitos de ciclo de vida)
8. PROMPT_MAESTRO_CONTINUACION_CIERRE_INTEGRAL_2026-10-09.md (megaprompt operativo de continuación inmediata; leer y ejecutar)
9. PROMPT_ANTIGRAVITY_AUTONOMOUS_CLOSURE.md (complemento operativo específico de Antigravity)
10. MEMORY.md, si existe
11. auditorías/documentos de la fase activa

## Verificación inicial

Ejecutar y medir:

- git status --short
- rama actual
- últimos commits
- procesos y puertos relevantes
- estado del backend
- estado del frontend/build
- migraciones aplicadas vs escritas
- pruebas de la fase activa

No confiar en números históricos sin volver a medirlos.

## Regla de autonomía

No preguntar qué hacer cuando el siguiente paso sea deducible.

Cerrar un hito no termina la sesión.

Después de cada cierre:

ESTADO → SIGUIENTE DISCRIMINADOR → IMPLEMENTAR → PROBAR → REGRESAR → DOCUMENTAR → REPETIR.

## Si una herramienta falla

No declarar imposibilidad.

Usar esta escalera:

1. cambiar herramienta;
2. reducir el caso;
3. bajar de capa;
4. inspeccionar artefactos propios;
5. utilizar ingeniería inversa del sistema propio;
6. crear un adaptador reversible;
7. probar equivalencia;
8. documentar.

## Ingeniería inversa

Permitida para código, artefactos, bundles propios, sourcemaps, OpenAPI, migraciones, contratos, trazas, APIs legítimamente accesibles y artefactos CI.

No utilizarla para evadir autenticación, MFA, CAPTCHA, RLS, autorización, secretos o controles de terceros.

## Únicos bloqueadores humanos

H1 — credencial externa que sólo el propietario puede proporcionar.

H2 — autorización para una acción irreversible.

H3 — decisión de producto genuinamente ambigua y no deducible.

H4 — infraestructura externa que exige login interactivo, MFA, CAPTCHA o aprobación física.

Un H1–H4 no detiene el resto del proyecto.

## Evidencia

Nunca declarar PASS por:
- pantalla abierta;
- HTTP 200 aislado;
- mock;
- retry;
- prueba sin precondición;
- no-op.

La prueba debe demostrar la operación real que afirma medir.

## Estado conocido al 2026-10-09 (sesión 2)

- **El `231` NO se reproduce en esta sesión — el toolchain de Flutter funciona.** `flutter test --no-pub` → **974 pruebas, `All tests passed!`, exit 0**; `flutter build web --release --dart-define-from-file=.env.json` → **`√ Built build\web`**; `flutter.bat --version` OK. El bloqueo histórico era **del sandbox de la sesión anterior**, no del proyecto. **No volver a citarlo sin medirlo otra vez.** → `docs/AI_AGENT_BLOCKERS.md`.
- **Autenticación SIN Resend: CERRADA y VERIFICADA contra el motor real.** Recuperación interna (código temporal de un solo uso emitido por un administrador, canjeado por el titular que fija su propia contraseña, con **cierre de las sesiones previas**) y ciclo de vida completo de la invitación docente (consumo atómico, revocar, renovar, listado con estado real y sin exponer el hash). Evidencia: `supabase/humo-invitaciones.mjs` → **34 OK / 0 fallos**; `supabase/humo-recuperacion.mjs` → **27 OK / 0 fallos**; residuo `0/0/0` en ambos. Migraciones `202610090001`/`202610090002` aplicadas a la nube. → `docs/AI_AGENT_BLOCKERS.md`.
- **Defecto real corregido en esta sesión:** la emisión de códigos escribía `password_resets` con el cliente del llamante (sólo tiene `SELECT`) → 403 en la nube. Ahora va por `reposAdmin`, y el arnés de pruebas **bloquea** esa vía para que el defecto no vuelva a pasar inadvertido.
- **P0 / E2E: CERRADO por medición.** El bundle local estaba compilado con `dart-define.example.json` (la plantilla) → la app apuntaba a `https://<project-ref>.supabase.co` y el login fallaba **antes de emitir ninguna petición**. Guardia añadida en `e2e/playwright.config.ts`.
- **E2E completo contra bundle FRESCO: 24/24 passed (2,2 min), exit 0** — con `flutter build web` local, no con un artefacto de CI ni una copia parcheada.
- Migraciones Supabase: **46 registradas, 0 pendientes, 0 con deriva** (medido 2026-10-09 con `apply-migrations.mjs --check`).
- Backend `npm run verify`: **675/675 PASS** (32 archivos) · PGlite `validate.mjs`: **546/546** · Dart `analizar-dart.mjs`: **219 archivos, sin errores/avisos/infos**.
- P-02: CERRADO. · P-01: ABIERTO hasta despliegue real + HEAD. · Performance: EN CURSO. · Responsive: no iniciar hasta cumplir el gate de Performance.
- F1: Resend HTTP 401 sigue bloqueando **únicamente** notificaciones externas opcionales. · F2 planilla oficial: CERRADA. · F4 R2: 52/52 PASS en humo real. · Aula Virtual E2E específico: 7/7 PASS. · Producción Pages: HTTP 200. · API Render: HTTP 200 tras cold start. · CORS Pages → API: verificado.

Estos datos son una fotografía, no una fuente superior al código o a una medición nueva.

## Siguiente trabajo esperado

Cerrado en esta sesión: build web local, `flutter test` completo, los dos flujos de identidad (invitación y recuperación) con evidencia contra el motor real, y **el ciclo E2E docente→aprendiz→entrega→calificación→devolución**, que ya se ejecutó con limpieza verificada (`supabase/limpiar-ciclo-aula.mjs`; conteos devueltos a la línea base exacta).

Lo que queda, por orden de dependencia:

1. **C7 estabilizado:** se cambió la aserción obsoleta por el título real `Calificaciones`. La corrida mutante terminó **7/7 PASS, 0 flaky** y la limpieza devolvió la base a 76 tareas / 225 entregas, 0 huérfanas. Evidencia en `TODO_CIERRE_INTEGRAL_INCES_LMS.md` y `docs/AI_AGENT_BLOCKERS.md`.
2. Continuar con regresión de operaciones principales por rol (Mis Aulas, Aula Virtual, Inscripciones, cPanel) más allá de la carga de pantallas.
3. **G3 performance — causa raíz medida y cuatro cambios mínimos aplicados (2026-10-09, sesión 2).** El hook de autenticación hacía **dos viajes de red en serie en cada petición** (verificar token en GoTrue 239 ms + leer perfil en PostgREST 216 ms = **421 ms fijos**; `/yo` y `/modulos` no consultan nada propio y tardaban eso), y cada consulta adicional sumaba ~190 ms. Paralelizados esos dos viajes (`Promise.allSettled` en `plugins/autenticacion.ts`) y tres pares de lecturas independientes (`PerfilesSupabase.listar`, `InscripcionesSupabase.detallar`, `listarOcupacionCon`): `admin/usuarios` **−64 %** (1.462 → 521 ms), `aula/trabajo` −47 %, `aula/mis-entregas` −43 %, `mi-horario` −32 %, `admin/secciones/:id/inscripciones` −33 %. Verificado sin regresión: backend **675/675**, smokes de identidad **34 y 27 OK**, E2E completo verde, casos límite del contrato (incluido desplazamiento más allá del final → 200 con página vacía). Detalle y tablas en `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md`.
   - **Siguiente discriminador:** `admin/cuadrante` (899 ms), `admin/aulas` (820 ms), `admin/programas` (718 ms), `admin/acceso` (718 ms) siguen >700 ms — medir sus viajes antes de tocar código.
   - **Bloqueo acotado:** falta `SUPABASE_JWT_SECRET` en `backend/.env` para verificar el JWT en local y eliminar el viaje a GoTrue. Es una credencial del propietario.
4. Cerrar P-01 con despliegue real y verificación de HEAD, sin hacer commit/push/despliegue sin autorización.
5. Después: responsive, UI/UX, accesibilidad, Android si sigue en alcance, regresión integral y documentación final.

No se considera cerrada la aplicación completa por aprobar la matriz P0.

## Handoff

Al detenerse por límite real del entorno, escribir:

- fecha;
- fase;
- hito;
- estado;
- evidencia;
- archivos;
- comandos;
- resultados;
- regresiones;
- H1/H2/H3/H4;
- deudas;
- siguiente discriminador;
- comando exacto;
- criterio de cierre.

Nunca dejar únicamente "continuar".

## Continuidad de agentes — actualizado el 2026-10-09

Documentos operativos:
- docs/AI_AGENT_TOKEN_EFFICIENT_AUTONOMY.md — continuidad económica de contexto.
- docs/PROJECT_PHASE_GATES.md — puertas de aceptación.
- PROMPT_MAESTRO_CICLO_VIDA_COMPLETO_AGENTE_IA.md — especificación transversal para Antigravity/Gemini y otros agentes.
- PROMPT_ANTIGRAVITY_AUTONOMOUS_CLOSURE.md — instrucciones operativas específicas para Antigravity.

Uso recomendado: abre el repositorio correcto en Antigravity y pega/carga PROMPT_MAESTRO_CICLO_VIDA_COMPLETO_AGENTE_IA.md como misión principal. Indica que debe leer AGENT_START_HERE.md y todos los documentos canónicos, y ejecutar el prompt operativo específico de Antigravity como complemento. No copies únicamente el prompt si el agente no tiene acceso al repositorio: los documentos y el código son la memoria persistente necesaria.

El agente debe continuar por ciclos verificables, guardar checkpoints y cambiar de método ante bloqueos; no debe intentar evadir cuotas, controles de seguridad ni límites legítimos del proveedor.
