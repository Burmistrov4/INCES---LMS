# PLAN MAESTRO — Stack Definitivo e Inamovible

> **Proyecto:** LMS INCES — CFS Nacional de Soldadura "Rafael Urdaneta" (La Isabelica)
> **TEG:** IUTEPI — Análisis de Sistemas — 4º Semestre — Periodo SA26-2
> **Equipo:** José Tarazón, Lorenzo Roca, Sleither Vásquez, Adrián Cedeño
> **Tutor:** Prof. Maglis Camacho
> **Vigente desde:** 2026-09-12

---

## 1. STACK DEFINITIVO

| Capa | Tecnología | Notas |
|---|---|---|
| **Frontend** | Flutter + Dart | 100% responsive, build Web para dominio propio |
| **Base de datos** | **Supabase (PostgreSQL)** | Free tier 500 MB |
| **Autenticación** | Supabase Auth | Email/contraseña + confirmación por correo |
| **Backend** | Node.js / TypeScript | Stateless; delega la persistencia a Supabase |
| **Storage** | **Cloudflare R2** | 10 GB gratis. Presigned URLs; Supabase guarda sólo el `r2_key` |
| **Despliegue** | Serverless **y** contenedores | Render/Vercel **+** Docker/docker-compose en Ubuntu local |
| **cPanel** | Administrador Maestro | Control modular total y dinámico |
| **M9 (Certificados/QR)** | ❌ **Descartado** | Fuera de alcance |

### Reglas de Oro

1. **Poder absoluto del Administrador Maestro.** Todo módulo y función debe poder
   habilitarse, deshabilitarse y personalizarse dinámicamente desde el cPanel.
2. **Frontend responsive** desde el inicio (mobile / tablet / desktop).
3. **Supabase (PostgreSQL)** como única base de datos. Sin MongoDB.
4. **Backend stateless.** Sin estado en memoria; escalable horizontalmente.
5. **Storage pesado en R2.** MongoDB/Supabase nunca almacenan el archivo físico:
   sólo la metadata (`r2_key`).
6. **Arquitectura dual Cloud/Local** vía variables de entorno.
7. **M9 descartado.**

---

## 2. ADR — DECISIONES REGISTRADAS

| ADR | Decisión | Fecha | Estado |
|---|---|---|---|
| ADR-001 | Flutter + Node/TS + Supabase + R2 (no FastAPI/Next.js) | 2026-09-10 | Vigente |
| ADR-002 | Auth en Supabase; lógica de negocio en la API Node | 2026-09-10 | Vigente |
| ADR-003 | RLS como control de autorización en la base de datos | 2026-09-10 | Vigente |
| ADR-004 | Archivos sólo en R2; Presigned URLs TTL 15 min | 2026-09-10 | Vigente |
| ADR-005 | Inmutabilidad por triggers SQL | 2026-09-10 | N/A (era para M9) |
| **ADR-006** | **MongoDB descartado.** Se mantiene PostgreSQL/Supabase | 2026-09-12 | **Vigente** |
| **ADR-007** | **Alta de aspirante vía trigger atómico**, no por inserts del cliente | 2026-09-12 | **Vigente** |
| **ADR-008** | **El auto-registro nunca otorga rol.** Rol fijo `estudiante`; la promoción es manual/administrativa | 2026-09-12 | **Vigente** |
| **ADR-009** | **Arquitectura dual**: mismo artefacto, configuración por entorno | 2026-09-12 | **Vigente** |
| **ADR-010** | **Capas de datos devuelven `Result<T>`**, nunca `null` como señal de error | 2026-09-12 | **Vigente** |

**Motivo de ADR-006:** los problemas de suministro eléctrico en Venezuela exigen
maximizar free tiers robustos y 24/7, pero conservando la capacidad de correr en
un servidor local. PostgreSQL/Supabase ya está montado, tiene RLS probado y su
free tier es suficiente para el volumen del CFS. Migrar a MongoDB habría costado
las fases 2, 4, 5, 6 y 7 sin beneficio claro.

---

## 3. FASES (start to finish)

### FASE 0 — Cimientos y seguridad
| Tarea | Estado |
|---|---|
| Credenciales fuera de `main.dart` (`--dart-define`) | ✅ Hecho |
| Esquema SQL versionado en `supabase/migrations/` | ✅ Hecho |
| RLS en todas las tablas | ✅ Hecho |
| CI/CD: GitHub Actions → build Web → Cloudflare Pages | ⏳ Pendiente |
| Bucket R2 + CORS para Flutter Web | ⏳ Pendiente (Fase 6) |

---

### FASE 1 — Auth y Onboarding ✅ **COMPLETADA (2026-09-12)**

**Problema que resolvió:** el registro creaba el usuario en `auth.users` pero
**nunca guardaba la ficha del aspirante**. Además el formulario no pedía
contraseña, así que el aspirante quedaba sin forma de entrar. Los datos se
perdían en silencio porque el repositorio se tragaba todas las excepciones.

**Solución adoptada (ADR-007):** el alta ocurre en **una sola transacción** de
PostgreSQL mediante el trigger `handle_new_user()` sobre `auth.users`. Si algo
falla (cédula duplicada, constraint de edad), Postgres revierte todo: no queda
usuario huérfano ni ficha a medias.

**Entregables:**

| Archivo | Cambio |
|---|---|
| `supabase/migrations/202609120001_phase1_onboarding.sql` | **Nuevo.** Trigger atómico + `precheck_aspirante()` + `link_pending_aspirante()`. Elimina la política `aspirantes_insert_public` (agujero de seguridad) |
| `lib/core/errors/app_exception.dart` | **Nuevo.** Errores tipados con mensajes en español |
| `lib/core/result.dart` | **Nuevo.** `Result<T>` sellado (`Success`/`Failure`) |
| `lib/models/registro_resultado.dart` | **Nuevo.** Distingue registro con/sin confirmación de correo |
| `lib/models/aspirante_model.dart` | `userId`, `toMetadata()`, fecha como `YYYY-MM-DD` |
| `lib/services/auth_service.dart` | `registrarAspirante()` devuelve `Result`; validación local + precheck |
| `lib/services/supabase_service.dart` | `signUp` con metadata, RPCs, `getMiAspirante()` |
| `lib/repositories/aspirante_repository.dart` | **Sin `catch` silencioso.** Todo devuelve `Result` |
| `lib/screens/aspirante_form_screen.dart` | Campos de contraseña, errores visibles, no se pierde lo escrito al fallar |
| `lib/screens/registro_exitoso_screen.dart` | Dos desenlaces reales (con/sin sesión) |
| `lib/screens/login_screen.dart` | Enlace a inscripción; consume `Result` |
| `lib/main.dart` | **Corregido bug crítico**: `home` + ruta `'/'` simultáneos (la app no arrancaba en debug). Ruta rota `/aspirante-registro` eliminada |
| `test/phase1_onboarding_test.dart` | **Nuevo.** 25 pruebas |

**Verificación:** `flutter analyze` = 0 issues · `flutter test` = **30/30 pasan**

**Paso manual pendiente:** aplicar la migración (ver §4).

---

### FASE 2 — API Node/TypeScript stateless
- Fastify + TypeScript + Zod; contrato **OpenAPI 3.1** antes de codificar M2+.
- Endpoints base: `POST /auth/login`, `GET /me`, `POST /aspirantes`, `GET /aspirantes/:id`.
- **Presigned URLs** R2: `POST /storage/presign-upload`, `POST /storage/presign-download`.
- Healthcheck `/health` + `UptimeRobot` cada 14 min (evita cold start de Render).
- **Arquitectura dual (ADR-009):** `Dockerfile` + `docker-compose.yml` para el
  servidor local; mismas variables de entorno que en serverless.

### FASE 3 — Núcleo del Administrador Maestro
> Base técnica de la Regla de Oro nº 1. Sin esto, el control modular queda a medias.

- Tabla `system_modules` (clave, nombre, habilitado, orden, icono, roles permitidos).
- Tabla `system_settings` (clave-valor tipada: `periodo_activo`, `max_faltas`,
  `enrollment_lock_days`, `r2_ttl_minutos`…).
- Middleware de la API que **rechaza** llamadas a módulos deshabilitados.
- UI del cPanel: interruptores por módulo y editor de parámetros.
- Auditoría: quién cambió qué flag y cuándo (`config_audit_log`).

### FASE 4 — M2 Currículo & M3 Cuadrante
- CRUD de programas (CARRERA / CURSO_LIBRE, `requires_internship`), materias y aulas.
- Setup-Wizard de pensum (arrastrar materias → períodos).
- Secciones + `schedule_slots` con **anti-colisión** de aula y docente (HTTP 409).
- Impresión de cuadrante con membrete dinámico (PDF).

### FASE 5 — M4 Inscripción & Motor de Bids
- Estados: `ENROLLED` · `WAITLISTED` · `PENDING_BID` · `DROPPED`.
- Cupo = `sections.max_capacity`; reserva con `SELECT ... FOR UPDATE`.
- Al liberarse un cupo → primer `WAITLISTED` (FIFO) pasa a `PENDING_BID` con
  ventana de **24 h**; si expira, avanza al siguiente.
- Notificación por correo + Realtime.
- Lockout si `now() > section.start_date + enrollment_lock_days`.

### FASE 6 — M5 Archivos (R2) & M6 Asistencia
- `files_metadata` (`TASK_SUBMISSION` | `TEACHER_GUIDE`) con `r2_key`; máximo
  10 MB; sólo PDF/DOCX/XLSX/JPG.
- Botón "Pasar Asistencia" habilitado sólo dentro del `schedule_slot` del docente.
- **Motor de 3 faltas consecutivas → `DROPPED` → dispara el Bid** (M5).
- "Botón nuclear": purga masiva por `period_code` con `grace_days`.

### FASE 7 — M7 Calificaciones
- `evaluation_plans` **por sección** (permite varios docentes en la misma materia).
- Ítems con `weight`; validación Σ = 100 % en la API.
- `grade_audit_logs` (old_score, new_score, motivo, usuario).
- Consolidación al cierre → `section.status = COMPLETED` → bloqueo de notas.
- Alerta de riesgo: acumulado < 50 %.

### FASE 8 — M8 Pasantías
- `internships` + `industrial_tutor_tokens` (token seguro, expiración, un solo uso).
- Flujo externo sin cuenta: `PATCH /api/internships/external-grade?token=`.
- `FAILED` → vuelve a `PENDING_PLACEMENT` (repite horas).

### FASE 9 — Endurecimiento y despliegue dual
- Suite de pruebas automatizadas + estrés con k6.
- Documentación por módulo en `/docs/modules/M<N>/`.
- Guía de despliegue: Render/Vercel **y** docker-compose en Ubuntu local.
- Plan de contingencia eléctrica: procedimiento de arranque del servidor local.

---

## 4. APLICAR LA MIGRACIÓN DE LA FASE 1

**Opción A — Supabase CLI (recomendada):**
```bash
supabase link --project-ref <tu-project-ref>
supabase db push
```

**Opción B — SQL Editor:** pega el contenido completo de
`supabase/migrations/202609120001_phase1_onboarding.sql` y ejecútalo.

**Verificación posterior:**
```sql
-- Debe devolver el trigger sobre auth.users
select tgname from pg_trigger where tgname = 'on_auth_user_created';

-- Prueba de humo del prechequeo
select public.precheck_aspirante('00000000', 'nadie@example.com');  -- OK
```

**Configuración de correo:** si quieres que el aspirante entre directo tras
registrarse, desactiva la confirmación por correo en
*Supabase → Authentication → Providers → Email → Confirm email*. Con la
confirmación activa, el flujo muestra la pantalla de "revisa tu bandeja" y la
ficha igual queda creada (el trigger es atómico).

**Promover a docente o admin** (el auto-registro nunca lo hace):
```sql
update public.profiles set rol = 'docente' where lower(email) = 'persona@inces.edu.ve';
```

---

## 5. DEUDA TÉCNICA REGISTRADA

| # | Deuda | Impacto | Prioridad |
|---|---|---|---|
| D1 | `SupabaseService` tiene constructor privado → **no es inyectable ni simulable**. Los tests no pueden cubrir el camino feliz de red | Medio (limita cobertura) | Fase 2 |
| D2 | El frontend Flutter habla directo con Supabase; falta migrar escrituras críticas a la API | Medio (ADR-002) | Fase 2 |
| D3 | `precheck_aspirante` permite enumerar cédulas/correos | Bajo (formulario público) | Fase 3 |
| D4 | `docente_dashboard` es un cascarón de 73 líneas | Bajo | Fase 6 |
| D5 | Sin CI/CD: los tests no corren en cada push | Medio | Fase 0 (pendiente) |
| D6 | Filas huérfanas creadas por el bug anterior requieren revisión manual | Bajo | Fase 3 |

---

## 6. HITOS ACADÉMICOS (TEG)

| Capítulo | Entregable | Fase |
|---|---|---|
| Cap. III — Metodología | `PLAN_MAESTRO`, `ROADMAP`, `DATABASE.md`, `API_SPEC.yaml` | 0–2 |
| Cap. IV — Desarrollo | Auth, Aspirantes, Admin Maestro, Currículo, Cuadrante, Inscripción+Bids | 1–5 |
| Cap. V — Pruebas | Suite automatizada + evidencias de estrés (k6) | 6–9 |
| Cap. VI — Conclusiones | Demo end-to-end: Aspirante → Aula → Notas → Egresado | 9 |

---

**Última actualización:** 2026-09-12
**Versión:** 2.0 — Stack definitivo, MongoDB descartado, Fase 1 completada
