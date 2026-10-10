# Diseño — Duración configurable, caducidad e historial de períodos académicos

> **Propuesta. No aplicada.** Ninguna migración de este documento se ha ejecutado en
> producción. Requiere autorización explícita (§10 del encargo). Fecha: 2026-10-10.

---

## 1. Estado actual (medido sobre el esquema real)

### `academic_periods` — `supabase/migrations/202609180001_mod3_cuadrante_aulas.sql:128`

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | fontanería |
| `code` | varchar(10) unique | **identidad visible** (`2026-1`, `SA26-2`); FK destino de `sections.period_code` |
| `name` | text | etiqueta humana |
| `start_date` | date **null** | anulable a propósito: el centro no ha cargado fechas reales |
| `end_date` | date **null** | idem |
| `is_active` | boolean not null default false | «operativo», **no** «vigente» |
| `created_at`, `updated_at` | timestamptz | |

`CHECK academic_periods_fechas_coherentes`: `end_date is null or start_date is null or end_date > start_date`.

### `programs` — `202609150001_mod2_curriculo.sql:97`

`id`, `code`, `name`, `type` (`CARRERA`/`CURSO_LIBRE`), `requires_internship`, `is_active`,
`created_at`, `updated_at`. **No hay ninguna columna de duración.**

### Otras piezas relevantes

- `subjects.academic_hours` — carga horaria **por materia**, no duración de programa.
- «Vigente» **no es una fecha**: es `system_settings.periodo_activo` (un `code`), declarado con
  `PUT /api/v1/admin/periodos/:id/vigente` (`backend/src/http/rutas/cuadrante.ts:194`).
- **Auditoría reutilizable:** `public.config_audit_log` (`202609120002_phase3_admin_core.sql:99`)
  es **append-only y genérica** — `tabla`, `clave`, `valor_anterior jsonb`, `valor_nuevo jsonb`,
  `actor_id`, `usuario_email`, `created_at` — con el trigger `public.audit_config_change()`
  (`security definer`). Es el patrón a seguir.
- Rutas actuales: `GET/POST /periodos`, `PATCH /periodos/:id`, `PUT /periodos/:id/vigente`.

---

## 2. Lo que falta (y lo que no)

| Necesidad del encargo | ¿Existe? |
|---|---|
| Duración **total del programa**, configurable | **No** |
| Duración / fechas propias del **período** | Parcial: hay `start_date`/`end_date`, sin duración ni cálculo |
| Caducidad / vencimiento | **No** |
| Extensión (prórroga) con fecha anterior y nueva | **No** |
| Historial de cambios de fechas | **No** (solo `updated_at`) |
| Estados del lapso | **No** (solo `is_active` + `periodo_activo`) |

---

## 3. Principios de diseño

1. **Nada se borra.** Un período no se elimina: se archiva (`is_active = false`) o se cierra
   (`closed_at`). Las matrículas, secciones, calificaciones y certificados siguen apuntando a él.
2. **El vencimiento se calcula, no se almacena.** No hay cron ni tarea programada: el estado sale
   de comparar `end_date` con `current_date`. Es el patrón que el proyecto ya usa para fechas.
3. **La duración del programa y la del período son cosas distintas.**
   - *Programa*: cuánto dura el trayecto completo (soldadura = 3 meses; una carrera = varios lapsos).
   - *Período*: cuánto dura **un** lapso. Tiene sus propias fechas efectivas.
4. **Reutilizar la auditoría existente**, no inventar una paralela.
5. **La reapertura es explícita y auditada**, nunca efecto colateral de editar una fecha.

---

## 4. Propuesta concreta

### 4.1 Duración del programa (total) — `programs`

```sql
alter table public.programs
  add column duration_value integer,
  add column duration_unit  text;

alter table public.programs
  add constraint programs_duracion_coherente check (
    (duration_value is null and duration_unit is null)          -- sin dato: válido
    or (duration_value > 0 and duration_unit in ('DIAS','SEMANAS','MESES'))
  );
```

- **Anulable a propósito.** El usuario solo ha confirmado *soldadura = 3 meses*. El resto de
  programas queda sin dato hasta que el centro lo cargue — **no se inventa**.
- Es **informativa/planificación**: no genera fechas por sí sola. Se usa para (a) mostrar la
  duración prevista y (b) **sugerir** la fecha de fin de un período nuevo.

### 4.2 Duración del período — `academic_periods`

**No se añade columna de duración.** El período conserva sus **fechas efectivas**
(`start_date`, `end_date`), que es lo que el encargo pide («cada período debe conservar sus
propias fechas efectivas»). La duración es derivada (`end_date - start_date`).

Se añade una **ayuda de cálculo**, no un dato:

- En el formulario, si el período se asocia a un programa con duración, el botón
  «Calcular fin desde la duración» propone `end_date = start_date + duración`.
- **Regla de aritmética de meses (documentada y probada):** sumar *N* meses a una fecha que no
  existe en el mes destino **se satura al último día del mes destino**. Ejemplo: 31-ene + 1 mes =
  28-feb (29 en bisiesto), **no** 3-mar. Sin esta regla, «tres meses» significaría dos cosas
  distintas según el día de inicio. Se implementa en una función pura del backend, con pruebas.

### 4.3 Estados — conjunto mínimo, derivado

**Sin columna de estado.** El estado se **deriva** de `is_active` + fechas + `closed_at`:

| Estado | Regla |
|---|---|
| **Borrador** | `is_active = false` y `closed_at is null` |
| **Programado** | `is_active = true` y `start_date > hoy` |
| **Activo** | `is_active = true` y (`start_date <= hoy` o nulo) y (`end_date >= hoy` o nulo) |
| **Vencido** | `is_active = true` y `end_date < hoy` y `closed_at is null` |
| **Cerrado** | `closed_at is not null` |

Se añade **una sola** columna para distinguir «cerrado» (acción explícita) de «borrador»:

```sql
alter table public.academic_periods
  add column closed_at timestamptz,
  add column closed_by uuid;
```

- **Vencido ≠ Cerrado.** Vencido es lo que dice el calendario; cerrado es una decisión. Un período
  vencido sigue mostrando sus datos y **no** cierra actividades por sí solo.
- **Reabrir** = `closed_at := null`, mediante una acción explícita y auditada. **Editar una fecha
  nunca reabre.**

### 4.4 Caducidad: qué hace y qué no

- **Hace:** mostrar el estado (chip «Vencido»), conservar todo, permitir consulta histórica.
- **No hace (por defecto):** no bloquea inscripciones nuevas, no bloquea editar calificaciones, no
  cierra nada. Cualquier bloqueo automático sería una política institucional no confirmada.

### 4.5 Historial de cambios y prórrogas

Se **reutiliza `config_audit_log`**, con una ampliación mínima para el **motivo**:

```sql
alter table public.config_audit_log add column motivo text;
```

- `academic_periods` no tiene columna `clave` (tiene `code`), así que se añade un trigger hermano
  del existente, con el mismo patrón `security definer`:

```sql
create or replace function public.audit_academic_period_change()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_email text;
begin
  if v_actor is not null then
    select u.email into v_email from auth.users u where u.id = v_actor;
  end if;

  insert into public.config_audit_log
    (tabla, clave, valor_anterior, valor_nuevo, actor_id, usuario_email, motivo)
  values (
    'academic_periods',
    coalesce(new.code, old.code),
    case when tg_op = 'UPDATE' then to_jsonb(old) else null end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    v_actor, v_email,
    nullif(current_setting('app.audit_motivo', true), '')
  );
  return null;
end; $$;

create trigger academic_periods_audit
after insert or update or delete on public.academic_periods
for each row execute function public.audit_academic_period_change();
```

- El **motivo** viaja desde el backend con `select set_config('app.audit_motivo', $1, true)`
  dentro de la misma transacción del `PATCH`. Es el patrón estándar para inyectar contexto en un
  trigger, y evita una tabla de historial paralela.
- Con esto, la historia de un período se **reconstruye** desde el registro: creación, activación,
  fecha inicial, cada modificación (valor anterior y nuevo), actor, fecha/hora, motivo, cierre y
  reapertura. Nada depende de `updated_at`.

### 4.6 Seguridad (RLS y permisos)

- `config_audit_log` ya es **solo-escritura-por-trigger**; se mantiene. Lectura: admin.
- Escritura de `academic_periods`: **admin** (`public.is_admin()`), igual que hoy.
- El backend comprueba rol (`exigirAdmin`) **y** la base lo vuelve a comprobar por RLS (ADR-003).
- La extensión de fecha **no** se apoya en el frontend: la regla vive en el backend y el trigger
  registra el actor real (`auth.uid()`), no lo que diga el cliente.

---

## 5. Migración (preparada, **NO aplicada**)

Un solo archivo, `YYYYMMDDNNN_periodos_duracion_y_caducidad.sql`, con:

1. `programs.duration_value`, `programs.duration_unit` + `CHECK`.
2. `academic_periods.closed_at`, `academic_periods.closed_by`.
3. `config_audit_log.motivo`.
4. `audit_academic_period_change()` + trigger.
5. Permisos (`grant update` de las columnas nuevas a `authenticated` bajo RLS).
6. **Al aplicar:** añadir lo nuevo al arreglo `esperadas` de `supabase/verificar-esquema.mjs`
   (si no, el verificador lo reporta como «tabla heredada» y falla — lección de M2).

**Reversibilidad:** todo son columnas anulables y un trigger; el rollback es
`drop trigger`, `drop function`, `drop column`. No hay `UPDATE`/`DELETE` de datos existentes, así
que revertir no pierde información. Límite de reversión: los cambios ya auditados se quedan en
`config_audit_log` (append-only) aunque se revierta el esquema.

**Orden de despliegue:** migración **antes** del frontend (regla del proyecto). El frontend debe
tolerar que las columnas no existan todavía (`duration_value` ausente = «sin duración cargada»).

---

## 6. Plan de pruebas

- **PGlite (SQL):** el `CHECK` rechaza duración inválida; el trigger escribe `valor_anterior`/
  `valor_nuevo` y `motivo`; reabrir deja rastro; no se puede borrar un período con secciones.
- **Backend (unit, vitest):** función pura de aritmética de meses (31-ene + 1 mes = 28/29-feb);
  `estadoDePeriodo(periodo, hoy)` para los 5 estados, con fechas controladas (sin tocar el reloj
  de producción); validación `start < end`.
- **Backend (integración):** `PATCH /periodos/:id` con fechas inválidas (400), extensión por
  admin (200 + auditoría), por docente (403), período vencido, reapertura explícita.
- **Flutter (widget):** el panel muestra el chip de estado correcto y el diálogo de extensión
  pide motivo; los estados no borran filas.
- **E2E (Playwright):** crear período → fijar fechas → extender → recargar → el historial conserva
  la fecha anterior y el actor. Con fechas **controladas**, nunca esperando a que venza de verdad.

---

## 7. Decisiones institucionales pendientes (NO inventadas)

1. **¿El vencimiento bloquea inscripciones nuevas?** Propuesta por defecto: **no**, solo avisa.
2. **¿El cierre bloquea editar calificaciones?** Propuesta por defecto: **no**; el cierre es
   informativo y auditable.
3. **¿`motivo` es obligatorio siempre o solo al extender?** Propuesta: obligatorio **solo al
   extender** un período que ya tiene secciones o matrículas.
4. **¿La duración del programa determina cuántos lapsos abarca?** Propuesta: **no** por ahora; es
   informativa y sirve para sugerir la fecha de fin.
5. **¿Confirmas el conjunto de 5 estados?** ¿Alguno sobra o falta (p. ej. «Cancelado»)?

Hasta que 1–3 se decidan, el sistema **no** aplicará bloqueo alguno: mostrará el estado y dejará
la decisión al administrador. Así ninguna política irreversible entra sin confirmación.
