# ROADMAP — INCES LMS PROJECT

> **Proyecto:** Plataforma Web para la Gestión de Procesos Académicos y Administrativos  
> **Institución:** CFS Nacional de Soldadura "Rafael Urdaneta" — INCES La Isabelica  
> **TEG IUTEPI:** Análisis de Sistemas — 4º Semestre — Periodo SA26-2  
> **Stack Definitivo:** Flutter (Web/Mobile) + Node.js/TypeScript API + PostgreSQL (Supabase) + Cloudflare R2

> ⚠️ **Este documento es la línea base del 2026-09-10 y está parcialmente
> desactualizado.** El plan vigente es
> [`docs/PLAN_MAESTRO_STACK_DEFINITIVO.md`](docs/PLAN_MAESTRO_STACK_DEFINITIVO.md).
> Cambios posteriores: **M9 (Certificados/QR) descartado**, se añade la
> **arquitectura dual Cloud/Local** y el **núcleo del Administrador Maestro**
> como fase propia. La migración a MongoDB se evaluó y se **descartó**
> (ADR-006). La Fase 1 (Auth y Onboarding) está **completada**.

---

## 1. MAPEO TEG ↔ ARQUITECTURA ↔ MÓDULOS

| Objetivo TEG (Cap. I) | Módulo Lógico | Entregable Técnico | Estado |
|---|---|---|---|
| Diagnosticar procesos manuales | **M0 — Levantamiento & Esquema BD** | Esquema SQL versionado, RLS, migraciones | ✅ Diseñado (`aspirantes`), pendiente versionar |
| Integrar inscripción de aspirantes | **M1 — Autenticación & Onboarding** | Auth Supabase, roles, registro aspirante, flag menor de edad | 🟡 **EN PROGRESO** (UI existe, sin backend) |
| Planificación curricular / pensum | **M2 — Currículo & Pensum** | CRUD Programs/Subjects, Setup-Wizard, periods | ⏳ Pendiente |
| Horarios, aulas, docentes | **M3 — Cuadrante (Horarios)** | Sections, Classrooms, Schedule_Slots, anti-colisión | ⏳ Pendiente |
| Inscripción, cupos, lista de espera | **M4 — Tráfico & Motor de Bids** | Enrollments FIFO, PENDING_BID 24h, Edge Functions | ⏳ Pendiente |
| Archivos, tareas, guías | **M5 — Almacenamiento (R2)** | Files_Metadata, Presigned URLs, purga automática | ⏳ Pendiente |
| Control asistencia, expulsión auto | **M6 — Asistencia** | Attendance_Records, motor 3 faltas → DROPPED → Bid | ⏳ Pendiente |
| Evaluaciones, notas, auditoría | **M7 — Calificaciones** | Evaluation_Plans (suma 100%), Grades, Audit Logs | ⏳ Pendiente |
| Pasantías, tutor industrial externo | **M8 — Pasantías** | Internships, Tokens externos, evaluación sin auth | ⏳ Pendiente |
| Certificación, QR, inmutabilidad | **M9 — Egreso & QR** | Graduates_Registry, Certificates, SHA-256, Trigger SQL | ⏳ Pendiente |

---

## 2. FASES DE IMPLEMENTACIÓN

### FASE 0 — CIMIENTOS Y SEGURIDAD (Semana 1) — **CRÍTICO**
| Tarea | Responsable | Verificación |
|---|---|---|
| Mover credenciales Supabase a `--dart-define` / `.env` (no commitear) | Dev | `main.dart` sin secrets; build web funciona |
| Versionar esquema SQL en `supabase/migrations/` (incl. `aspirantes`, `profiles`, `enrollments`...) | Dev | `supabase db push` aplica limpio |
| Activar RLS en todas las tablas; políticas por rol (admin, docente, estudiante) | Dev | `SELECT`/`INSERT`/`UPDATE` respetan rol |
| Configurar Cloudflare R2 + bucket `inces-lms-files`; CORS para Flutter web | Dev | Subida/descarga Presigned URL funciona |
| Crear `lib/services/supabase_service.dart` singleton + `lib/services/r2_service.dart` | Dev | Inyección de dependencias lista |
| Configurar CI/CD: GitHub Actions → Flutter build web → Cloudflare Pages | Dev | Push a `main` despliega automáticamente |

> **Nota:** Fase 0 desbloquea todo lo posterior. No avanzar a M1 sin RLS y migraciones versionadas.

---

### FASE 1 — M1: AUTENTICACIÓN & ONBOARDING ASPIRANTES (Semanas 2–3)
**Objetivo TEG:** *OE1 — Diagnosticar / OE2 — Requerimientos / OE3 — Diseñar plataforma*

| Hito | Archivos Clave | Criterio de Aceptación |
|---|---|---|
| **1.1 Refactor `aspirante_form_screen.dart`** — Responsive (mobile ≤480px, tablet, desktop), Stepper con validación por paso, campos obligatorios según planilla INCES | `lib/screens/aspirante_form_screen.dart`, `lib/widgets/form_step_*.dart` | Formulario renderiza sin overflow en Chrome DevTools device toolbar; `Form.validate()` por step |
| **1.2 Modelo `AspiranteModel` + `AspiranteRepository`** — Mapeo 1:1 a tabla `aspirantes` (campos: cedula, nombres, apellidos, fecha_nac, sexo, telefono, email, direccion, nivel_educativo, mision_ribaras, discapacidad, representante_legal si menor) | `lib/models/aspirante_model.dart`, `lib/repositories/aspirante_repository.dart` | `toJson()`/`fromJson()` coincide con migración SQL; test unitario pasa |
| **1.3 Servicio Supabase `AuthService`** — `signUpAspirante(data)` crea usuario en Auth + inserta en `aspirantes` + setea `requires_legal_tutor` si edad < 18 | `lib/services/auth_service.dart` | Transacción atómica; rollback si falla insert; email de confirmación enviado |
| **1.4 Pantalla `RegistroExitosoScreen`** — Muestra estado de verificación de email, instrucciones para menor de edad | `lib/screens/registro_exitoso_screen.dart` | Navegación fluida desde formulario |
| **1.5 Login unificado** — `LoginScreen` usa email/cedula + password; redirige según rol (`user_metadata.rol`) a `AdminDashboard` / `DocenteDashboard` / `AspiranteDashboard` | `lib/screens/login_screen.dart`, `lib/providers/role_provider.dart` | 3 roles navegan a su dashboard correspondiente |

**Definición de Terminado Fase 1:** Un aspirante real puede registrarse desde móvil, recibe email, confirma, hace login y ve su ficha básica. Datos persisten en Supabase con RLS.

---

### FASE 2 — BACKEND NODE.JS/TYPESCRIPT (Semana 4) — **PARALELO O SECUENCIAL**
> El frontend Flutter **no** debe contener lógica de negocio compleja (Bids, auditoría, triggers). Esa lógica vive en la API.

| Componente | Tech | Endpoints Mínimos (OpenAPI) |
|---|---|---|
| **API Core** | Fastify + TypeScript + Zod | `POST /auth/login`, `GET /me`, `POST /aspirantes`, `GET /aspirantes/:id` |
| **Motor de Bids** | Edge Function / Worker | `POST /enrollments/bid/trigger` (invocado por M6) |
| **Archivos R2** | Presigned URLs | `POST /storage/presign-upload`, `POST /storage/presign-download` |
| **Certificación QR** | PDFKit + QRCode | `POST /certificates/generate`, `GET /verify/:uuid` |
| **Despliegue** | Render/Koyeb | `https://api.inces-lms.example.com` + healthcheck |

**Contrato:** Frontend Flutter consume **solo** esta API (no Supabase directo para escrituras críticas). Supabase se usa solo para Auth y Realtime.

---

### FASE 3 — M2 Y M3: CURRÍCULO & CUADRANTE (Semanas 5–6)
| Entregable | Detalle |
|---|---|
| CRUD `Programas` (CARRERA / CURSO_LIBRE, `requires_internship`) | AdminDashboard → Sección "Programas" |
| CRUD `Materias` (banco global, `academic_hours`) | AdminDashboard → "Materias" |
| Setup-Wizard Pensum (arrastrar materias → períodos) | UI tipo Kanban, validación `program_subjects` ≠ ∅ |
| CRUD `Aulas` (TEORICO/LABORATORIO, `custom_capacity`) | AdminDashboard → "Infraestructura" |
| CRUD `Secciones` + `Schedule_Slots` (anti-colisión aula/docente) | Matriz visual "Cuadrante"; validación 409 en API |
| Impresión Membrete Dinámico (PDF) | `PERIODO | ESPECIALIDAD | SECCION | AULA` |

---

### FASE 4 — M4: INSCRIPCIÓN & MOTOR DE BIDS (Semana 7)
| Regla | Implementación |
|---|---|
| Cupo = `sections.max_capacity` (hereda de aula, editable) | API `POST /enrollments` con `SELECT ... FOR UPDATE` |
| Estados: `ENROLLED` | `WAITLISTED` | `PENDING_BID` | `DROPPED` | Enum + índice único `(section_id, student_id, date)` |
| Bid: DROPPED → primer WAITLISTED (ORDER BY created_at) → PENDING_BID 24h | Edge Function + Supabase Realtime notifica al aprendiz |
| Timeout 24h → DROPPED + siguiente en cola | Cron job diario (pg_cron o worker) |
| Lockout: si `now() > section.start_date + enrollment_lock_days` → Bid desactivado | Variable global en `configuracion_sistema` |

---

### FASE 5 — M5 Y M6: ARCHIVOS & ASISTENCIA (Semanas 8–9)
| M5 — Almacenamiento | M6 — Asistencia |
|---|---|
| `files_metadata` (entity_type: `TASK_SUBMISSION` \| `TEACHER_GUIDE`) | `attendance_records` (PRESENT/ABSENT/EXCUSED, unique idx) |
| Presigned PUT/GET (R2), max 10MB, solo PDF/DOCX/XLSX/JPG | Docente: botón "Pasar Asistencia" solo en días/horarios de su `schedule_slot` |
| Explorador Admin (filtro por entidad, alumno, fecha) | Motor 3 ABSENT consecutivos → `enrollments` = DROPPED → dispara Bid |
| Botón Nuclear: purga masiva por `period_code` (grace_days) | Alumno DROPPED desaparece de planilla notas (M7) |

---

### FASE 6 — M7: CALIFICACIONES (Semana 10)
- `evaluation_plans` por **sección** (no por materia) → múltiples docentes mismo materia
- Items con `weight` (NUMERIC 5,2); validación Σ ≤ 100% en API
- `grades` + `grade_audit_logs` (trigger: old_score, new_score, reason, user_id)
- Consolidación ponderada al cierre → `section.status = COMPLETED` → bloqueo grades
- Dashboard alerta: acumulado < 50% → bandera naranja "Riesgo reprobación"

---

### FASE 7 — M8: PASANTÍAS (Semana 11)
- `internships` (1:1 student, company_Rif, tutor_email, status ENUM)
- `industrial_tutor_tokens` (secure_token, expires_at, is_consumed)
- Flujo externo: `PATCH /api/internships/external-grade?token=` → valida token → guarda → `EVALUATED`
- `FAILED` → alumno vuelve a `PENDING_PLACEMENT` (repite horas)

---

### FASE 8 — M9: EGRESO & QR (Semana 12)
| Componente | Tech |
|---|---|
| `graduates_registry` (folio_number UNIQUE, final_gpa) | Trigger: al insertar → bloquea UPDATE/DELETE en `grades` + `attendance_records` donde student_id existe |
| `certificates` (document_type: TRANSCRIPT/DIPLOMA, hash_signature SHA-256) | PDF generado en API (PDFKit), subido a R2 (bucket `certificados`, policy READ ONLY) |
| QR en PDF → `https://api.inces-lms.example.com/verify/:certificate_uuid` | Endpoint público GET (sin auth) devuelve JSON con datos crudos |
| `is_revoked` para anular títulos | Admin puede revocar; QR muestra "ADULTERADO" |

---

## 3. CRITERIOS DE CALIDAD Y DEFINICIÓN DE "HECHO"

| Capa | Estándar |
|---|---|
| **Frontend (Flutter)** | `flutter analyze` = 0 issues; `flutter test` = 100% pass; responsive 320px–1920px; Material 3 + Inter font |
| **Backend (Node/TS)** | `npm run lint` + `npm run typecheck` = 0; tests unitarios ≥80% cobertura (Vitest); OpenAPI 3.1 generado |
| **Base de Datos** | Migraciones reversibles; RLS en 100% tablas; índices en FK y columnas de filtro frecuente |
| **Seguridad** | Secrets solo en vars de entorno; CORS restringido; Rate limit en auth; CSP headers |
| **Observabilidad** | Logs estructurados (pino); Sentry/Logtail en API; Supabase logs + Realtime monitor |
| **Documentación** | Cada módulo tiene `README.md` en `/docs/modules/M<N>/` con diagrama Mermaid y casos de uso |

---

## 4. HITOS DE ENTREGA ACADÉMICA (TEG)

| Capítulo TEG | Entregable Código | Fecha Límite Estimada |
|---|---|---|
| **Cap. III — Metodología** | Repo con `ROADMAP.md`, `ARCHITECTURE.md`, `DATABASE.md`, `API_SPEC.yaml` | Semana 2 |
| **Cap. IV — Desarrollo** | Fases 1–4 funcionales (Auth, Aspirantes, Currículo, Cuadrante, Inscripción+Bids) | Semana 8 |
| **Cap. V — Pruebas** | Fases 5–8 + Suite de pruebas automatizadas + Evidencias de estrés (k6) | Semana 12 |
| **Cap. VI — Conclusiones** | Demo end-to-end: Aspirante → Egresado → QR verificado por tercero | Semana 13 |

---

## 5. RIESGOS Y MITIGACIONES

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Supabase Free Tier límites (500MB DB, 1GB storage, 2M row reads) | Alta | Medio | M5 usa R2; archivar períodos antiguos; monitoreo diario |
| Render Free Tier cold start (15 min) | Alta | Bajo | UptimeRobot ping cada 14 min a `/health` |
| Complejidad Motor Bids + Asistencia concurrente | Media | Alto | Edge Functions atómicas; tests de caos (k6) antes de integrar |
| Migración Flutter → API Node (cambio de paradigma) | Media | Medio | Definir contrato OpenAPI **antes** de codificar M2+ |
| Falta de tiempo académico (entrega TEG) | Alta | Crítico | Priorizar M1, M4, M6, M9 (núcleo demostrable); M2, M3, M5, M7, M8 como "funcionalidad extendida" |

---

## 6. PRÓXIMOS PASOS INMEDIATOS (Esta semana)

1. ✅ **Crear `ROADMAP.md`** — *Hecho*
2. 🔄 **Refactor `aspirante_form_screen.dart`** — Responsive, validación por step, widgets separados
3. 🔄 **Crear `lib/services/supabase_service.dart`** — Singleton, tipado, manejo de errores
4. 🔄 **Implementar `AspiranteRepository.insert()`** — Conecta formulario → Supabase
5. 🔄 **Actualizar `ROADMAP.md`** — Marcar M1 como "En Progreso → Completado" al cerrar PR

---

## 7. DECISIONES ARQUITECTÓNICAS REGISTRADAS (ADR)

| ADR | Decisión | Fecha |
|---|---|---|
| ADR-001 | Stack: Flutter + Node/TS + Supabase + R2 (no FastAPI/Next.js) | 2026-09-10 |
| ADR-002 | Auth en Supabase; lógica de negocio en API Node (no Edge Functions salvo Bids/QR) | 2026-09-10 |
| ADR-003 | RLS como único control de autorización (no middleware custom en Flutter) | 2026-09-10 |
| ADR-004 | Archivos solo en R2; metadatos en PG; Presigned URLs TTL 15 min | 2026-09-10 |
| ADR-005 | Inmutabilidad por Triggers SQL (no solo app-level) para M9 | 2026-09-10 |

---

## 8. ESTRUCTURA DE CARPETAS OBJETIVO (Flutter)

```
lib/
├── main.dart
├── core/
│   ├── config/          # Env, themes, constants
│   ├── di/              # Dependency injection (get_it)
│   ├── errors/          # Failures, exceptions
│   └── utils/           # Helpers, extensions
├── models/              # Entidades puras (toJson/fromJson)
├── repositories/        # Contratos + impl Supabase
├── services/            # SupabaseService, R2Service, AuthService, NotificationService
├── providers/           # Riverpod/Provider state (AuthProvider, RoleProvider, ...)
├── screens/
│   ├── auth/            # Login, Registro, OlvidoPwd
│   ├── aspirante/       # Formulario, DashboardAspirante
│   ├── admin/           # DashboardAdmin, CRUDs M2-M9
│   ├── docente/         # DashboardDocente, Asistencia, Notas
│   └── public/          # VerifyCertificate (QR landing)
├── widgets/             # Componentes reutilizables (FormSteps, DataTables, QRView)
└── routes/              # GoRouter config
```

---

## 9. COMANDOS ÚTILES

```bash
# Flutter
flutter analyze
flutter test --coverage
flutter build web --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

# Supabase (local)
supabase start
supabase db push
supabase migration new nombre_migracion
supabase db reset

# Node API
npm run dev
npm run typecheck
npm run lint
npm test

# Despliegue
wrangler pages deploy build/web --project-name=inces-lms  # Cloudflare Pages
```

---

**Última actualización:** 2026-09-10  
**Versión:** 1.0 — Baseline post-auditoría completa  
**Responsable:** Equipo TEG INCES (José Tarazón, Lorenzo Roca, Sleither Vásquez, Adrián Cedeño)  
**Tutor:** Prof. Maglis Camacho