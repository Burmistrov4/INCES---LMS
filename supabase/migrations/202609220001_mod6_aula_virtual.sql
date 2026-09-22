-- ============================================================================
--  INCES LMS — Módulo 6: Aula Virtual (Tablón, Trabajo de clase, Calificaciones)
--  Archivo: 202609220001_mod6_aula_virtual.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  El «Google Classroom a la medida del INCES»: un docente publica anuncios en
--  el Tablón y trabajo en «Trabajo de clase»; los alumnos matriculados lo ven,
--  entregan y reciben nota. Es el módulo 6 del ROADMAP.
--
--  NADA SE DUPLICA DE LO QUE YA EXISTE
--  -----------------------------------
--  «Un curso» es una `sections` de M3: ya implica programa, materia y lapso,
--  y ya tiene roster (`enrollments`, M4) y docentes (`schedule_slots`, M3).
--  Crear una tabla de cursos habría creado una segunda fuente de verdad para
--  lo que la sección ya dice. Aquí sólo nacen las TRES piezas que no existían:
--  `m6_anuncios`, `m6_tareas` y `m6_entregas`.
--
--  Los ADJUNTOS no se remodelan: se reutiliza `files_metadata` de M5 tal cual.
--  El reparto que M5 ya tenía (`TEACHER_GUIDE` = material del docente,
--  `TASK_SUBMISSION` = entrega del alumno) es EXACTAMENTE el de Google
--  (`CourseWork.materials` vs `StudentSubmission.attachments`). Este archivo
--  **no toca** `202609210001_mod5_archivos.sql`: una migración ya aplicada no
--  se edita nunca, porque el libro mayor detecta la deriva. Lo que sí añade son
--  tres políticas de lectura nuevas sobre esa tabla (PARTE 7), que PostgreSQL
--  combina con OR con las de M5: son aditivas y no debilitan ninguna.
--
--  ESTE ARCHIVO CIERRA LA MITAD DE D17 QUE M5 NO PODÍA EXPRESAR
--  ------------------------------------------------------------
--  `files_metadata.entidad_id` es un UUID **sin tabla que lo respalde** hasta
--  hoy. Por eso un docente no veía las entregas de sus alumnos y un alumno no
--  veía las guías: no había nada que unir para saber a qué sección pertenece
--  una entrega, y por tanto qué docente la dicta. No era un descuido de M5:
--  era inexpresable. A partir de `m6_entregas` sí lo es, y por eso las
--  políticas van aquí y no allí.
--
--  LAS CUATRO DECISIONES QUE IMPONE EL ENTORNO INCES
--  -------------------------------------------------
--  1. NADA DEPENDE DE UN PLANIFICADOR (cortes eléctricos + arquitectura dual).
--     · La publicación programada se resuelve EN LA LECTURA, dentro de la
--       política RLS: `PUBLICADO or (BORRADOR and programado_para <= now())`.
--       El resultado para el alumno es el mismo que con un job, y no hay job.
--     · «Tardía» se ESCRIBE al entregar (`now() > fecha_limite`), dentro de la
--       misma transacción. No queda nada que calcular después.
--     · «Faltante» se DERIVA al leer (`estado='ASIGNADA' and fecha_limite <
--       now()`) y **nunca se auto-escribe un 0**. Google sí lo escribe, y aquí
--       se descarta a propósito: sería una escritura implícita en nombre de un
--       docente que no la pidió, y quedaría congelada —un alumno que entrega
--       tarde seguiría con el 0 puesto—. Lo pone el docente si corresponde.
--  2. ESCALA 0–20, no 0–100: es la escala venezolana y la que el centro usa en
--     actas. Va en un CHECK, no en un comentario.
--  3. NOTA BORRADOR ≠ NOTA ASIGNADA. Dos columnas. El alumno no ve nada hasta
--     que el docente DEVUELVE; y como `nota_asignada` es NULL hasta entonces,
--     no hay nada que ocultar en la lectura: el valor simplemente no existe.
--  4. LOS PLACEHOLDERS DE ENTREGA SE CREAN AL PUBLICAR (uno por matrícula
--     ENROLLED), no con un LEFT JOIN contra el roster al leer. Así «quién no ha
--     entregado» es una lectura directa y no un join contra una tabla que
--     cambia sola cuando alguien se matricula o se retira.
--
--  DOS CONTRADICCIONES DEL DISEÑO, RESUELTAS AQUÍ Y NO EN SILENCIO
--  ---------------------------------------------------------------
--  (a) `docs/ARQUITECTURA_AULA_VIRTUAL.md` §2.2 pedía a la vez
--      `CHECK (puntos_maximos > 0 AND puntos_maximos <= 20)` y «una tarea de
--      tipo MATERIAL no puede tener puntos_maximos distintos de 0». Las dos
--      juntas son insatisfacibles: un MATERIAL no podría existir. Se resuelve
--      con un rango que admite el 0 y dos CHECK de coherencia por tipo.
--  (b) El diseño listaba seis RPC y ninguna de LECTURA, pero la ruta del libro
--      del docente necesita `nota_borrador`, que el GRANT por columna le
--      esconde a `authenticated`. Sin una función `security definer` que la
--      lea, esa ruta habría nacido con la columna en blanco. Se añaden dos RPC
--      (`m6_crear_anuncio` y `m6_entregas_de_tarea`) y las funciones devuelven
--      **columnas explícitas, nunca la fila entera**: devolver `setof
--      m6_entregas` le entregaría `nota_borrador` al alumno dentro del
--      resultado, y el GRANT por columna habría sido decorativo.
--
--  `security definer` OBLIGA A AUTORIZAR A MANO (lección R-20)
--  -----------------------------------------------------------
--  Una función `definer` corre con los privilegios de su dueño y SE SALTA la
--  RLS. Por eso cada RPC hace su propia autorización con `auth.uid()` (y
--  `is_admin()` donde toca) y fija `search_path = public, pg_temp`. Conceder
--  EXECUTE de más aquí abriría justo la puerta que este archivo cierra.
--
--  EL MÓDULO SE DEJA APAGADO A PROPÓSITO (igual que hizo M5)
--  ---------------------------------------------------------
--  `m6_aula_virtual` se siembra con `habilitado = false`. La bandera debe ser
--  la última pieza que encaja: se enciende cuando ya existen las rutas Y la UI
--  que las sostiene. Encenderla antes dejaría un ítem de menú sin circuito
--  detrás (el patrón de R-22). El encendido irá en su propia migración
--  `202609220002_mod6_habilitar_modulo.sql`, siguiendo el reparto que ya usaron
--  M4 (`202609200001` construye / `202609200002` enciende) y M5.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — `m6_anuncios`: el Tablón
-- ---------------------------------------------------------------------------
--  Un anuncio pertenece a UNA sección. No hay anuncios «globales»: el INCES
--  trabaja por sección, y un anuncio suelto no tendría a quién dirigirse.
create table if not exists public.m6_anuncios (
  id               uuid        primary key default gen_random_uuid(),

  seccion_id       uuid        not null
                     references public.sections(id) on delete cascade,

  autor_id         uuid        not null
                     references public.profiles(id) on delete cascade,

  titulo           text        not null check (btrim(titulo) <> ''),
  cuerpo           text        not null default '',

  estado           text        not null default 'BORRADOR'
                     check (estado in ('BORRADOR', 'PUBLICADO', 'ELIMINADO')),

  -- Publicación diferida sin planificador (decisión 1). Se resuelve en la
  -- política de lectura, no con un job.
  programado_para  timestamptz,

  -- Orden del feed. Se fija al publicar, no al crear: un borrador no tiene
  -- fecha de publicación, y `created_at` no sirve como sustituto porque un
  -- borrador de hace un mes publicado hoy debe encabezar el tablón.
  publicado_en     timestamptz,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  -- Un anuncio «programado» sin fecha no significa nada: la política de
  -- lectura pregunta por `programado_para <= now()` y con NULL eso es NULL,
  -- así que la fila quedaría invisible para todos — incluido su autor— sin que
  -- nadie supiera por qué. Fallar al guardar es mejor que un silencio.
  constraint m6_anuncios_programado_coherente
    check (estado <> 'BORRADOR' or programado_para is not null or publicado_en is null)
);

comment on table public.m6_anuncios is
  'Tablón de anuncios del aula virtual: un anuncio pertenece a una sección. La publicación programada se resuelve en la política RLS de lectura (no hay planificador: cortes eléctricos y arquitectura dual).';
comment on column public.m6_anuncios.estado is
  'Ciclo de vida: BORRADOR (sólo lo ve el docente) → PUBLICADO → ELIMINADO. El borrado es lógico: el anuncio se conserva como historial.';
comment on column public.m6_anuncios.programado_para is
  'Publicación diferida. Un BORRADOR con esta fecha en el pasado es visible para el alumno SIN que ningún proceso lo haya tocado: la política de lectura lo evalúa con now().';
comment on column public.m6_anuncios.publicado_en is
  'Cuándo se publicó de verdad. Ordena el feed. Distinto de created_at, que es cuándo se escribió el borrador.';


-- ---------------------------------------------------------------------------
--  PARTE 2 — `m6_tareas`: Trabajo de clase
-- ---------------------------------------------------------------------------
create table if not exists public.m6_tareas (
  id                        uuid        primary key default gen_random_uuid(),

  seccion_id                uuid        not null
                              references public.sections(id) on delete cascade,

  creado_por                uuid        not null
                              references public.profiles(id) on delete cascade,

  titulo                    text        not null check (btrim(titulo) <> ''),
  descripcion               text        not null default '',

  -- Reproduce `workType` de Google y su separación entre `CourseWork` y
  -- `CourseWorkMaterial`. `PREGUNTA` queda como marcador: el motor de
  -- preguntas de opción múltiple es un ciclo propio, no éste.
  tipo                      text        not null default 'TAREA'
                              check (tipo in ('TAREA', 'MATERIAL', 'PREGUNTA')),

  -- (a) El rango admite el 0 porque un MATERIAL no se califica. La coherencia
  -- por tipo la imponen los dos CHECK de abajo, que es donde corresponde: un
  -- único CHECK no puede decir «>0 salvo para MATERIAL» sin repetir el tipo.
  puntos_maximos            numeric(4,2) not null default 20
                              check (puntos_maximos >= 0 and puntos_maximos <= 20),

  fecha_limite              timestamptz,

  permitir_entrega_tardia   boolean     not null default true,

  -- `MODIFIABLE_UNTIL_TURNED_IN` es el defecto de Google: el alumno no puede
  -- cambiar los adjuntos una vez entregado, salvo que el docente le devuelva
  -- la entrega (`RECLAMADA`), que es la válvula de escape del ciclo.
  permite_edicion           text        not null default 'MODIFIABLE_UNTIL_TURNED_IN'
                              check (permite_edicion in ('MODIFIABLE_UNTIL_TURNED_IN', 'MODIFIABLE')),

  estado                    text        not null default 'BORRADOR'
                              check (estado in ('BORRADOR', 'PUBLICADO', 'ELIMINADO')),

  programado_para           timestamptz,

  -- Agrupación por texto y orden manual dentro del tema. Una tabla de temas
  -- añadiría una entidad y una ruta para ganar sólo el arrastre, que aquí no
  -- es crítico.
  tema                      text,
  orden                     integer     not null default 0,

  publicado_en              timestamptz,

  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  -- Un MATERIAL es el `CourseWorkMaterial` de Google: material de lectura, sin
  -- nota ni fecha límite. No genera entregas, y por eso no puede tener ni
  -- puntos ni fecha: si los tuviera, el libro de calificaciones mostraría una
  -- columna sin nada dentro y «quién no entregó» incluiría a todo el curso.
  constraint m6_tareas_material_sin_nota
    check (tipo <> 'MATERIAL' or puntos_maximos = 0),
  constraint m6_tareas_material_sin_plazo
    check (tipo <> 'MATERIAL' or fecha_limite is null),

  -- El complemento del rango abierto: lo que se califica vale más que cero.
  constraint m6_tareas_calificable_con_puntos
    check (tipo = 'MATERIAL' or puntos_maximos > 0),

  -- Mismo motivo que en los anuncios: un borrador con `programado_para` nula
  -- que ya tiene `publicado_en` es un estado que la política de lectura no
  -- puede interpretar.
  constraint m6_tareas_programado_coherente
    check (estado <> 'BORRADOR' or programado_para is not null or publicado_en is null)
);

comment on table public.m6_tareas is
  'Trabajo de clase: tareas, materiales y (a futuro) preguntas de una sección. Reutiliza files_metadata de M5 para los adjuntos: TEACHER_GUIDE apunta a esta tabla, TASK_SUBMISSION apunta a m6_entregas.';
comment on column public.m6_tareas.puntos_maximos is
  'Puntos sobre 20 (escala venezolana). Vale 0 sólo para tipo=MATERIAL; los CHECK de coherencia por tipo lo garantizan.';
comment on column public.m6_tareas.fecha_limite is
  'Fecha límite de entrega. NULL = sin plazo. Es la referencia de «tardía» (se escribe al entregar) y de «faltante» (se deriva al leer).';
comment on column public.m6_tareas.estado is
  'BORRADOR → PUBLICADO → ELIMINADO. Publicar crea los placeholders de entrega de cada matrícula ENROLLED.';


-- ---------------------------------------------------------------------------
--  PARTE 3 — `m6_entregas`: StudentSubmission
-- ---------------------------------------------------------------------------
--  El `id` de esta tabla es el `entidad_id` de los archivos `TASK_SUBMISSION`.
--  Esa es la unión que M5 no podía hacer y que cierra la mitad de D17.
create table if not exists public.m6_entregas (
  id              uuid        primary key default gen_random_uuid(),

  tarea_id        uuid        not null
                    references public.m6_tareas(id) on delete cascade,

  -- Contra `profiles`, no contra `auth.users`: la entrega es de una PERSONA
  -- del sistema, y así se puede unir con el nombre sin pasar por auth.
  estudiante_id   uuid        not null
                    references public.profiles(id) on delete cascade,

  estado          text        not null default 'ASIGNADA'
                    check (estado in ('ASIGNADA', 'ENTREGADA', 'DEVUELTA', 'RECLAMADA')),

  -- Se escribe AL ENTREGAR (decisión 1), no lo calcula un job.
  es_tardia       boolean     not null default false,

  -- Sólo lo ve el docente. Se protege con GRANT POR COLUMNA (PARTE 6), no con
  -- RLS: una política es por fila y no puede esconder una columna.
  nota_borrador   numeric(4,2) check (nota_borrador between 0 and 20),

  -- Visible al alumno sólo cuando el docente devuelve. Y como es NULL hasta
  -- entonces, no hace falta ocultarlo: el valor no existe todavía.
  nota_asignada   numeric(4,2) check (nota_asignada between 0 and 20),

  entregada_en    timestamptz,
  devuelta_en     timestamptz,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- Un placeholder por alumno y tarea. Es lo que hace IDEMPOTENTE a
  -- `m6_publicar_tarea`: el `on conflict do nothing` de allá se apoya en esto.
  constraint m6_entregas_una_por_alumno unique (tarea_id, estudiante_id),

  -- No hay nota final sin borrador, igual que en Google: `assignedGrade` no
  -- puede existir sin `draftGrade`. Sin este CHECK, una devolución apresurada
  -- asignaría NULL y el alumno vería «—» sin que nada fallara.
  constraint m6_entregas_nota_asignada_exige_borrador
    check (nota_asignada is null or nota_borrador is not null)
);

comment on table public.m6_entregas is
  'Entrega de un alumno en una tarea. Su id es el entidad_id de los archivos TASK_SUBMISSION: esa unión es la que permite al docente ver las entregas de sus alumnos (mitad de D17 que M5 no podía expresar).';
comment on column public.m6_entregas.estado is
  'ASIGNADA (placeholder recién creado) → ENTREGADA → DEVUELTA. RECLAMADA es el «des-entregar» de Google y vuelve a habilitar la entrega.';
comment on column public.m6_entregas.es_tardia is
  'Se fija al entregar comparando con la fecha límite. Es un hecho histórico, no un estado derivado: la fecha límite puede cambiar después y la entrega ya ocurrió.';
comment on column public.m6_entregas.nota_borrador is
  'Nota del docente antes de devolver. PROTEGIDA POR GRANT POR COLUMNA: authenticated no tiene privilegio de SELECT sobre ella; sólo la leen las RPC security definer.';
comment on column public.m6_entregas.nota_asignada is
  'Nota que el alumno ya puede ver. NULL hasta que el docente devuelve: no se oculta, no existe.';


-- ---------------------------------------------------------------------------
--  PARTE 4 — Índices
-- ---------------------------------------------------------------------------
-- El feed del tablón: «los anuncios de esta sección, del más nuevo al más
-- viejo». Sin él, cada apertura del aula recorrería la tabla.
create index if not exists m6_anuncios_seccion_idx
  on public.m6_anuncios (seccion_id, publicado_en desc nulls last);

-- «El trabajo de clase de esta sección, en el orden en que el docente lo puso».
create index if not exists m6_tareas_seccion_orden_idx
  on public.m6_tareas (seccion_id, tema, orden);

-- «Las entregas de esta tarea»: es la consulta del libro de calificaciones del
-- docente. La `unique (tarea_id, estudiante_id)` ya cubre el prefijo
-- `tarea_id`, así que no se duplica el índice.
create index if not exists m6_entregas_estudiante_idx
  on public.m6_entregas (estudiante_id);

-- «Mis entregas»: la pantalla del alumno. El estado entra en el índice porque
-- la consulta del alumno casi siempre filtra por él (pendientes de entregar).
create index if not exists m6_entregas_estudiante_estado_idx
  on public.m6_entregas (estudiante_id, estado);


-- ---------------------------------------------------------------------------
--  PARTE 5 — Auxiliares de visibilidad
-- ---------------------------------------------------------------------------
--  Cinco preguntas que las políticas RLS y las RPC necesitan responder muchas
--  veces. Van en funciones `security definer` por dos motivos concretos, no por
--  comodidad:
--
--   1. **Evitan la RLS anidada.** Una política sobre `m6_entregas` que hiciera
--      `exists (select 1 from public.m6_tareas ...)` estaría consultando otra
--      tabla sujeta a RLS, y el resultado dependería de la política de esa
--      tabla. Eso no es defensa en profundidad: es una regla escrita en dos
--      sitios que pueden desviarse.
--   2. **Se pueden probar una a una** desde la suite de PGlite.
--
--  `stable` porque no escriben; `search_path` fijo por la misma razón que en
--  M5 (una función definer con search_path heredado es un secuestro esperando).

-- ¿El usuario actual dicta esta sección? Incluye al administrador, que
-- supervisa todo. `is_active` se comprueba para que una clase retirada del
-- cuadrante no siga dando acceso.
create or replace function public.m6_dicta_seccion(p_seccion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_admin() or exists (
    select 1
    from public.schedule_slots ss
    where ss.section_id = p_seccion_id
      and ss.teacher_id = auth.uid()
      and ss.is_active
  );
$$;

comment on function public.m6_dicta_seccion(uuid) is
  '¿El usuario actual dicta esta sección? Cierto para el docente con un schedule_slot activo y para el administrador.';

-- ¿El usuario actual está matriculado en esta sección? Sólo ENROLLED: una
-- matrícula en lista de espera no da acceso al material de clase.
create or replace function public.m6_matriculado_en(p_seccion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.enrollments e
    where e.section_id = p_seccion_id
      and e.student_id = auth.uid()
      and e.status = 'ENROLLED'
  );
$$;

comment on function public.m6_matriculado_en(uuid) is
  '¿El usuario actual está matriculado (status=ENROLLED) en esta sección? Una matrícula en espera o retirada no da acceso al aula.';

-- ¿El usuario actual dicta la sección de esta tarea? Es la pregunta del
-- docente, y la que abre los borradores: él los ve antes de publicarlos.
create or replace function public.m6_dicta_tarea(p_tarea_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_admin() or exists (
    select 1
    from public.m6_tareas t
    where t.id = p_tarea_id
      and public.m6_dicta_seccion(t.seccion_id)
  );
$$;

comment on function public.m6_dicta_tarea(uuid) is
  '¿El usuario actual dicta la sección de esta tarea? Cierto también para el administrador.';

-- Lo mismo un escalón más abajo: la entrega no guarda la sección, la hereda
-- de su tarea. Se sube por la tarea en vez de duplicar `seccion_id` en la
-- entrega, que sería una tercera copia de la misma verdad.
create or replace function public.m6_dicta_entrega(p_entrega_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_admin() or exists (
    select 1
    from public.m6_entregas e
    join public.m6_tareas t on t.id = e.tarea_id
    where e.id = p_entrega_id
      and public.m6_dicta_seccion(t.seccion_id)
  );
$$;

comment on function public.m6_dicta_entrega(uuid) is
  '¿El usuario actual dicta la sección de la tarea de esta entrega? Es la puerta del libro de calificaciones del docente.';

-- ¿Esta tarea le toca al usuario actual como alumno? Es la política de lectura
-- del alumno, y aquí es donde vive la decisión 1: un BORRADOR con
-- `programado_para` ya vencida es visible **sin que ningún proceso lo publique**.
-- El docente no la necesita: para él está `m6_dicta_tarea`.
create or replace function public.m6_tarea_publicada_para_mi(p_tarea_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.m6_tareas t
    where t.id = p_tarea_id
      and t.estado <> 'ELIMINADO'
      and public.m6_matriculado_en(t.seccion_id)
      and (
        t.estado = 'PUBLICADO'
        or (t.estado = 'BORRADOR'
            and t.programado_para is not null
            and t.programado_para <= now())
      )
  );
$$;

comment on function public.m6_tarea_publicada_para_mi(uuid) is
  '¿Esta tarea es visible para el alumno actual? Cierto si está PUBLICADO, o si es BORRADOR con programado_para ya vencida. Es la publicación diferida sin planificador.';


-- ---------------------------------------------------------------------------
--  PARTE 6 — RLS y permisos
-- ---------------------------------------------------------------------------
--  La frontera de autorización es la RLS, no la API (ADR-003). Nada de esto se
--  comprueba en Node. Y la escritura directa está PROHIBIDA (patrón de M4/M5):
--  la clave publishable viaja al navegador, así que si se pudiera insertar a
--  mano, un alumno podría publicarse un anuncio, darse una tarea por entregada
--  o —peor— escribirse la nota. Toda escritura pasa por las RPC de la PARTE 8.

alter table public.m6_anuncios enable row level security;
alter table public.m6_tareas   enable row level security;
alter table public.m6_entregas enable row level security;

-- --- m6_anuncios -----------------------------------------------------------
drop policy if exists m6_anuncios_visible on public.m6_anuncios;
create policy m6_anuncios_visible
on public.m6_anuncios
for select
to authenticated
using (
  estado <> 'ELIMINADO'
  and (
    public.m6_dicta_seccion(seccion_id)
    or autor_id = auth.uid()
    or (
      public.m6_matriculado_en(seccion_id)
      and (
        estado = 'PUBLICADO'
        or (estado = 'BORRADOR'
            and programado_para is not null
            and programado_para <= now())
      )
    )
  )
);

-- --- m6_tareas -------------------------------------------------------------
drop policy if exists m6_tareas_visible on public.m6_tareas;
create policy m6_tareas_visible
on public.m6_tareas
for select
to authenticated
using (
  estado <> 'ELIMINADO'
  and (
    public.m6_dicta_seccion(seccion_id)
    or public.m6_tarea_publicada_para_mi(id)
  )
);

-- --- m6_entregas -----------------------------------------------------------
drop policy if exists m6_entregas_visible on public.m6_entregas;
create policy m6_entregas_visible
on public.m6_entregas
for select
to authenticated
using (
  public.is_admin()
  or estudiante_id = auth.uid()
  or public.m6_dicta_entrega(id)
);

-- --- Permisos de tabla -----------------------------------------------------
--  `nota_borrador` se protege con GRANT POR COLUMNA. No es una preferencia de
--  estilo: RLS es por FILA y no puede esconder una columna, así que sin esto un
--  alumno leería su nota antes de que el docente la devuelva —exactamente la
--  garantía que la decisión 3 quiere conservar—. La lista de columnas es
--  explícita y **no** incluye `nota_borrador`; las RPC `security definer` sí la
--  leen, porque dentro de ellas el privilegio es el del dueño.
--
--  Consecuencia para el backend: el repositorio NO puede hacer `select *` sobre
--  `m6_entregas`; PostgREST genera SQL como `authenticated` y recibiría
--  `42501`. Es la misma razón por la que las RPC devuelven columnas explícitas
--  en vez de `setof m6_entregas`.
revoke all on public.m6_anuncios from anon, authenticated;
revoke all on public.m6_tareas   from anon, authenticated;
revoke all on public.m6_entregas from anon, authenticated;

grant select on public.m6_anuncios to authenticated;
grant select on public.m6_tareas   to authenticated;
grant select (id, tarea_id, estudiante_id, estado, es_tardia,
              nota_asignada, entregada_en, devuelta_en, created_at, updated_at)
  on public.m6_entregas to authenticated;

-- --- `updated_at` ----------------------------------------------------------
drop trigger if exists m6_anuncios_set_updated_at on public.m6_anuncios;
create trigger m6_anuncios_set_updated_at
before update on public.m6_anuncios
for each row execute function public.set_updated_at();

drop trigger if exists m6_tareas_set_updated_at on public.m6_tareas;
create trigger m6_tareas_set_updated_at
before update on public.m6_tareas
for each row execute function public.set_updated_at();

drop trigger if exists m6_entregas_set_updated_at on public.m6_entregas;
create trigger m6_entregas_set_updated_at
before update on public.m6_entregas
for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------------
--  PARTE 7 — La mitad de D17 que M5 no podía expresar
-- ---------------------------------------------------------------------------
--  Tres políticas de LECTURA nuevas sobre `files_metadata`, y **en esta
--  migración, nunca editando la de M5**: una migración ya aplicada no se toca.
--  PostgreSQL combina las políticas SELECT con OR, así que las de M5 siguen
--  valiendo y ninguna se debilita: esto sólo AÑADE visibilidad donde antes no
--  había forma de concederla.
--
--  Son tres y no una porque cada una responde a una relación distinta, y
--  mezclarlas habría escondido cuál de ellas concede el acceso cuando algo
--  fallara:
--    · el docente ve las GUÍAS de las tareas que dicta (incluidos borradores);
--    · el docente ve las ENTREGAS de sus alumnos;
--    · el alumno ve las GUÍAS de las tareas que le tocan.
--  Las entregas del propio alumno ya las cubre `files_metadata_read_own` de M5.

drop policy if exists files_metadata_docente_guia on public.files_metadata;
create policy files_metadata_docente_guia
on public.files_metadata
for select
to authenticated
using (
  entity_type = 'TEACHER_GUIDE'
  and entidad_id is not null
  and public.m6_dicta_tarea(entidad_id)
);

drop policy if exists files_metadata_docente_entrega on public.files_metadata;
create policy files_metadata_docente_entrega
on public.files_metadata
for select
to authenticated
using (
  entity_type = 'TASK_SUBMISSION'
  and entidad_id is not null
  and public.m6_dicta_entrega(entidad_id)
);

drop policy if exists files_metadata_estudiante_guia on public.files_metadata;
create policy files_metadata_estudiante_guia
on public.files_metadata
for select
to authenticated
using (
  entity_type = 'TEACHER_GUIDE'
  and entidad_id is not null
  and public.m6_tarea_publicada_para_mi(entidad_id)
);

-- --- 7.1 Integridad de `entidad_id`: un agujero que abre M6, no M5 ---------
--  Hasta hoy `entidad_id` no significaba nada, porque no había tabla que lo
--  respaldara. M6 es quien le da sentido, así que M6 es quien debe impedir que
--  apunte a cualquier cosa. Sin esto, un alumno podría subir un archivo con el
--  `entidad_id` de la entrega de OTRO compañero —la RPC de M5 no lo mira, y no
--  se puede editar: ya está aplicada— y al docente le aparecería un archivo
--  ajeno colgado de una entrega que no lo subió. Y con una guía, un alumno
--  podría inyectar «material de apoyo» en la tarea de toda la sección.
--
--  Va en un trigger y no en la RPC de M5 por la regla de siempre: la migración
--  aplicada no se edita. Y va en la tabla, no en la ruta, porque la ruta no es
--  la frontera (ADR-003) y porque un `insert` desde el editor SQL tampoco pasa
--  por Node.
--
--  `entidad_id` NULL sigue permitido: M5 lo admite a propósito (la entidad
--  puede crearse después de subir el archivo) y la UI del estudiante sube
--  material de apoyo sin atarlo a nada todavía.
create or replace function public.m6_validar_entidad_de_archivo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.entidad_id is null then
    return new;
  end if;

  if new.entity_type = 'TASK_SUBMISSION' then
    -- La entrega tiene que existir Y ser de quien sube el archivo. Se compara
    -- contra `propietario_id` y no contra `auth.uid()` porque un administrador
    -- puede registrar en nombre de otro (M5 lo permite explícitamente).
    if not exists (
      select 1
      from public.m6_entregas e
      where e.id = new.entidad_id
        and e.estudiante_id = new.propietario_id
    ) then
      raise exception
        'La entrega % no existe o no pertenece al propietario del archivo.',
        new.entidad_id
        using errcode = '23503';
    end if;

  elsif new.entity_type = 'TEACHER_GUIDE' then
    -- La guía se cuelga de una tarea que el usuario dicta (o de cualquiera, si
    -- es administrador). Sin esto, un alumno publicaría material en la tarea
    -- de toda la sección.
    if not exists (
      select 1
      from public.m6_tareas t
      where t.id = new.entidad_id
        and public.m6_dicta_seccion(t.seccion_id)
    ) then
      raise exception
        'La tarea % no existe o no la dicta quien sube la guía.',
        new.entidad_id
        using errcode = '23503';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.m6_validar_entidad_de_archivo() is
  'Impide que un archivo se ate a una entidad ajena: una entrega de otro alumno o la tarea de una sección que no se dicta. M6 es quien da sentido a files_metadata.entidad_id, así que M6 es quien lo vigila.';

drop trigger if exists m6_validar_entidad_de_archivo on public.files_metadata;
create trigger m6_validar_entidad_de_archivo
before insert or update of entity_type, entidad_id on public.files_metadata
for each row execute function public.m6_validar_entidad_de_archivo();


-- ---------------------------------------------------------------------------
--  PARTE 8 — RPCs de escritura
-- ---------------------------------------------------------------------------
--  Autorización uniforme: la RLS no actúa dentro de una función `definer`, así
--  que cada una comprueba `auth.uid()` e `is_admin()` por su cuenta. Los fallos
--  de autorización usan 42501 (→ 403, el mismo código que produce la RLS); los
--  de estado o inexistencia, 23514 (→ 400 con el mensaje tal cual).

-- ---------------------------------------------------------------------------
--  8.1 Crear un anuncio
-- ---------------------------------------------------------------------------
--  Existe como RPC y no como `insert` directo por la razón de siempre: la clave
--  publishable viaja al navegador, así que una política de INSERT laxa dejaría
--  a cualquiera publicar en el tablón de una sección ajena —o marcarse el
--  anuncio como PUBLICADO de una vez, saltándose el borrador—.
create or replace function public.m6_crear_anuncio(
  p_seccion_id      uuid,
  p_titulo          text,
  p_cuerpo          text,
  p_programado_para timestamptz default null
)
returns table (
  id              uuid,
  seccion_id      uuid,
  autor_id        uuid,
  titulo          text,
  cuerpo          text,
  estado          text,
  programado_para timestamptz,
  publicado_en    timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para publicar un anuncio.'
      using errcode = '42501';
  end if;

  if not public.m6_dicta_seccion(p_seccion_id) then
    raise exception 'No dictas la sección %: no puedes publicar en su tablón.', p_seccion_id
      using errcode = '42501';
  end if;

  return query
  insert into public.m6_anuncios as a
    (seccion_id, autor_id, titulo, cuerpo, programado_para)
  values
    (p_seccion_id, v_actor, p_titulo, coalesce(p_cuerpo, ''), p_programado_para)
  returning a.id, a.seccion_id, a.autor_id, a.titulo, a.cuerpo,
            a.estado, a.programado_para, a.publicado_en;
end;
$$;

comment on function public.m6_crear_anuncio(uuid, text, text, timestamptz) is
  'Crea un anuncio en el tablón de una sección que el usuario dicta. Nace en BORRADOR; si se pasa programado_para, será visible para los alumnos cuando esa hora llegue, sin que ningún proceso lo publique.';


-- ---------------------------------------------------------------------------
--  8.2 Crear una tarea
-- ---------------------------------------------------------------------------
create or replace function public.m6_crear_tarea(
  p_seccion_id              uuid,
  p_titulo                  text,
  p_descripcion             text,
  p_tipo                    text        default 'TAREA',
  -- `null` y NO `20`, aunque 20 sea el valor de negocio. Con `default 20`, la
  -- llamada natural `m6_crear_tarea(sec, 'Lectura', '', 'MATERIAL')` —sin
  -- pasar puntos, porque un material no se califica— **fallaba con 23514**: el
  -- argumento llegaba valiendo 20, la comprobación de coherencia de MATERIAL lo
  -- veía como «un material con puntos» y rechazaba. Un valor por defecto que
  -- contradice al caso más común es peor que no tenerlo, porque el error
  -- aparece lejos de su causa. Con `null`, «no me lo dijeron» se distingue de
  -- «me dijeron 20», y el 20 se aplica abajo sólo a lo que sí se califica.
  p_puntos_maximos          numeric     default null,
  p_fecha_limite            timestamptz default null,
  p_permitir_entrega_tardia boolean     default true,
  p_tema                    text        default null,
  p_orden                   integer     default 0
)
returns table (
  id                      uuid,
  seccion_id              uuid,
  titulo                  text,
  descripcion             text,
  tipo                    text,
  puntos_maximos          numeric,
  fecha_limite            timestamptz,
  permitir_entrega_tardia boolean,
  tema                    text,
  orden                   integer,
  estado                  text,
  publicado_en            timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para crear una tarea.'
      using errcode = '42501';
  end if;

  if not public.m6_dicta_seccion(p_seccion_id) then
    raise exception 'No dictas la sección %: no puedes crear trabajo en ella.', p_seccion_id
      using errcode = '42501';
  end if;

  -- La coherencia MATERIAL/sin nota la imponen los CHECK de la tabla; se
  -- comprueba aquí también para dar un mensaje que se entienda, en vez de un
  -- `violates check constraint m6_tareas_material_sin_nota` a secas. Los tres
  -- casos que la tabla rechazaría se traducen aquí a errores de negocio: un
  -- mensaje que nombra la regla ahorra media hora, y uno que nombra la
  -- restricción, no.
  if p_tipo = 'MATERIAL' then
    -- Un MATERIAL es de lectura: ni puntos ni plazo. Se compara contra `null`
    -- («no me lo dijeron») además de contra 0, para que **omitir** el argumento
    -- —que es lo natural en un material— no cuente como «le puse puntos».
    if (p_puntos_maximos is not null and p_puntos_maximos <> 0)
       or p_fecha_limite is not null then
      raise exception 'Un MATERIAL es de lectura: no lleva puntos ni fecha límite.'
        using errcode = '23514';
    end if;
  else
    -- Lo calificable vale entre 0 exclusivo y 20. Se aplica aquí el mismo
    -- valor por defecto que la columna, para poder comprobarlo ANTES de
    -- insertar y dar el mensaje bueno en vez de una violación de CHECK.
    if coalesce(p_puntos_maximos, 20) <= 0 then
      raise exception 'Una tarea calificable debe valer más de 0 puntos.'
        using errcode = '23514';
    end if;

    if coalesce(p_puntos_maximos, 20) > 20 then
      raise exception 'La nota máxima no puede superar 20 (la escala del centro).'
        using errcode = '23514';
    end if;
  end if;

  return query
  insert into public.m6_tareas as t
    (seccion_id, creado_por, titulo, descripcion, tipo, puntos_maximos,
     fecha_limite, permitir_entrega_tardia, tema, orden)
  values
    (p_seccion_id, v_actor, p_titulo, coalesce(p_descripcion, ''), p_tipo,
     case when p_tipo = 'MATERIAL' then 0 else coalesce(p_puntos_maximos, 20) end,
     p_fecha_limite, p_permitir_entrega_tardia, p_tema, coalesce(p_orden, 0))
  returning t.id, t.seccion_id, t.titulo, t.descripcion, t.tipo,
            t.puntos_maximos, t.fecha_limite, t.permitir_entrega_tardia,
            t.tema, t.orden, t.estado, t.publicado_en;
end;
$$;

comment on function public.m6_crear_tarea(uuid, text, text, text, numeric, timestamptz, boolean, text, integer) is
  'Crea trabajo de clase en una sección que el usuario dicta. Nace en BORRADOR y sin entregas: publicar es lo que crea los placeholders.';


-- ---------------------------------------------------------------------------
--  8.3 Publicar una tarea (y crear los placeholders de entrega)
-- ---------------------------------------------------------------------------
create or replace function public.m6_publicar_tarea(p_tarea_id uuid)
returns table (
  id           uuid,
  seccion_id   uuid,
  titulo       text,
  estado       text,
  publicado_en timestamptz,
  entregas     integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor   uuid := auth.uid();
  v_tarea   public.m6_tareas;
  v_creadas integer;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para publicar una tarea.'
      using errcode = '42501';
  end if;

  select * into v_tarea from public.m6_tareas where m6_tareas.id = p_tarea_id;

  if not found then
    raise exception 'La tarea % no existe.', p_tarea_id
      using errcode = '23514';
  end if;

  if not public.m6_dicta_seccion(v_tarea.seccion_id) then
    raise exception 'No dictas la sección de la tarea %: no puedes publicarla.', p_tarea_id
      using errcode = '42501';
  end if;

  if v_tarea.estado = 'ELIMINADO' then
    raise exception 'La tarea % está eliminada.', p_tarea_id
      using errcode = '23514';
  end if;

  -- Recrear el placeholder de alguien que ya entregó lo borraría con él: las
  -- entregas cuelgan de esta fila en cascada. Por eso publicar sólo toca lo
  -- que falta, y por eso el UPDATE no se lleva por delante `estado`.
  --
  -- OJO CON EL `t.` DEL `coalesce`: `returns table (...)` convierte los nombres
  -- de las columnas de salida en variables de PL/pgSQL, y `publicado_en` es una
  -- de ellas. Sin calificar, el lado derecho del SET es ambiguo y la función
  -- **no llega a ejecutarse**: `42702 column reference "publicado_en" is
  -- ambiguous`. Los destinos del SET no colisionan; sólo el lado derecho. Se
  -- aliasa la tabla y se califica, en vez de renombrar la columna de salida
  -- (renombrarla rompería el contrato que lee el backend).
  update public.m6_tareas as t
     set estado          = 'PUBLICADO',
         publicado_en    = coalesce(t.publicado_en, now()),
         programado_para = null
   where t.id = p_tarea_id;

  -- IDEMPOTENTE: publicar dos veces no duplica placeholders. Un botón que se
  -- puede pulsar dos veces no puede crear dos entregas por alumno — y la
  -- `unique (tarea_id, estudiante_id)` con `on conflict do nothing` lo
  -- garantiza en la base, no en la ruta.
  insert into public.m6_entregas (tarea_id, estudiante_id)
  select p_tarea_id, e.student_id
    from public.enrollments e
   where e.section_id = v_tarea.seccion_id
     and e.status     = 'ENROLLED'
  on conflict (tarea_id, estudiante_id) do nothing;

  get diagnostics v_creadas = row_count;

  return query
  select t.id, t.seccion_id, t.titulo, t.estado, t.publicado_en,
         (select count(*)::int from public.m6_entregas e where e.tarea_id = t.id)
    from public.m6_tareas t
   where t.id = p_tarea_id;
end;
$$;

comment on function public.m6_publicar_tarea(uuid) is
  'Publica una tarea y crea un placeholder de entrega por cada matrícula ENROLLED. Idempotente: republicar no duplica entregas (unique + on conflict do nothing).';


-- ---------------------------------------------------------------------------
--  8.4 Entregar
-- ---------------------------------------------------------------------------
--  Devuelve COLUMNAS EXPLÍCITAS, nunca la fila entera: `setof m6_entregas`
--  entregaría `nota_borrador` dentro del resultado y el GRANT por columna
--  habría quedado decorativo.
create or replace function public.m6_entregar_tarea(p_entrega_id uuid)
returns table (
  id            uuid,
  tarea_id      uuid,
  estado        text,
  es_tardia     boolean,
  nota_asignada numeric,
  entregada_en  timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_e     public.m6_entregas;
  v_t     public.m6_tareas;
  v_tarde boolean;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para entregar una tarea.'
      using errcode = '42501';
  end if;

  select * into v_e from public.m6_entregas where m6_entregas.id = p_entrega_id;

  if not found then
    raise exception 'La entrega % no existe.', p_entrega_id
      using errcode = '23514';
  end if;

  -- El dueño, no el docente: entregar es del alumno. Ni siquiera el
  -- administrador entrega en nombre de otro —no hay caso de uso y sí un
  -- registro de honestidad que se rompería—.
  if v_e.estudiante_id <> v_actor then
    raise exception 'La entrega % no es tuya.', p_entrega_id
      using errcode = '42501';
  end if;

  select * into v_t from public.m6_tareas where m6_tareas.id = v_e.tarea_id;

  if v_t.estado <> 'PUBLICADO' then
    raise exception 'La tarea no está publicada: no se puede entregar.'
      using errcode = '23514';
  end if;

  if v_e.estado = 'DEVUELTA' then
    raise exception 'La entrega ya fue devuelta: no se puede volver a entregar.'
      using errcode = '23514';
  end if;

  -- Decisión 1: la fecha límite y la bandera se evalúan AQUÍ, en la misma
  -- transacción. No hay nada que calcular después, así que no hace falta nada
  -- que corra después.
  v_tarde := v_t.fecha_limite is not null and now() > v_t.fecha_limite;

  if v_tarde and not v_t.permitir_entrega_tardia then
    raise exception 'La tarea cerró el % y no admite entregas tardías.', v_t.fecha_limite
      using errcode = '23514';
  end if;

  -- `MODIFIABLE_UNTIL_TURNED_IN` significa exactamente eso: una vez entregada,
  -- el alumno no cambia los adjuntos. La válvula de escape es `reclamar`.
  if v_e.estado = 'ENTREGADA' and v_t.permite_edicion = 'MODIFIABLE_UNTIL_TURNED_IN' then
    raise exception 'La tarea ya está entregada. Reclámala antes de volver a entregarla.'
      using errcode = '23514';
  end if;

  return query
  update public.m6_entregas as e
     set estado       = 'ENTREGADA',
         es_tardia    = v_tarde,
         entregada_en = now()
   where e.id = p_entrega_id
  returning e.id, e.tarea_id, e.estado, e.es_tardia, e.nota_asignada, e.entregada_en;
end;
$$;

comment on function public.m6_entregar_tarea(uuid) is
  'Marca la entrega como ENTREGADA y fija es_tardia comparando con la fecha límite, todo en la misma transacción. Sólo el alumno dueño. No devuelve nota_borrador.';


-- ---------------------------------------------------------------------------
--  8.5 Reclamar (el «des-entregar» de Google)
-- ---------------------------------------------------------------------------
create or replace function public.m6_reclamar_entrega(p_entrega_id uuid)
returns table (
  id            uuid,
  tarea_id      uuid,
  estado        text,
  es_tardia     boolean,
  nota_asignada numeric,
  entregada_en  timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_e     public.m6_entregas;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para reclamar una entrega.'
      using errcode = '42501';
  end if;

  select * into v_e from public.m6_entregas where m6_entregas.id = p_entrega_id;

  if not found then
    raise exception 'La entrega % no existe.', p_entrega_id
      using errcode = '23514';
  end if;

  if v_e.estudiante_id <> v_actor then
    raise exception 'La entrega % no es tuya.', p_entrega_id
      using errcode = '42501';
  end if;

  -- Una vez devuelta, la nota ya es del alumno y el ciclo está cerrado.
  -- Reclamar entonces reabriría una entrega calificada, que es justo lo que
  -- la devolución viene a impedir.
  if v_e.estado <> 'ENTREGADA' then
    raise exception 'Sólo se puede reclamar una entrega ya entregada (estado actual: %).', v_e.estado
      using errcode = '23514';
  end if;

  return query
  update public.m6_entregas as e
     set estado = 'RECLAMADA'
   where e.id = p_entrega_id
  returning e.id, e.tarea_id, e.estado, e.es_tardia, e.nota_asignada, e.entregada_en;
end;
$$;

comment on function public.m6_reclamar_entrega(uuid) is
  'Devuelve la entrega a RECLAMADA para poder volver a entregarla. Sólo el alumno dueño y sólo desde ENTREGADA: una entrega ya devuelta no se reabre.';


-- ---------------------------------------------------------------------------
--  8.6 Calificar (nota BORRADOR)
-- ---------------------------------------------------------------------------
create or replace function public.m6_calificar_entrega(
  p_entrega_id uuid,
  p_nota       numeric
)
returns table (
  id            uuid,
  tarea_id      uuid,
  estudiante_id uuid,
  estado        text,
  es_tardia     boolean,
  nota_borrador numeric,
  nota_asignada numeric
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_e     public.m6_entregas;
  v_t     public.m6_tareas;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para calificar.'
      using errcode = '42501';
  end if;

  if p_nota is null or p_nota < 0 or p_nota > 20 then
    raise exception 'La nota debe estar entre 0 y 20.'
      using errcode = '23514';
  end if;

  select * into v_e from public.m6_entregas where m6_entregas.id = p_entrega_id;

  if not found then
    raise exception 'La entrega % no existe.', p_entrega_id
      using errcode = '23514';
  end if;

  if not public.m6_dicta_entrega(p_entrega_id) then
    raise exception 'No dictas la sección de esta entrega: no puedes calificarla.'
      using errcode = '42501';
  end if;

  select * into v_t from public.m6_tareas where m6_tareas.id = v_e.tarea_id;

  if p_nota > v_t.puntos_maximos then
    raise exception 'La nota % supera el máximo de la tarea (%).', p_nota, v_t.puntos_maximos
      using errcode = '23514';
  end if;

  -- Sólo se califica lo entregado. Poner nota a un placeholder vacío es
  -- escribir una nota sobre trabajo que no existe; «faltante» se DERIVA al
  -- leer, no se escribe (decisión 1).
  if v_e.estado not in ('ENTREGADA', 'RECLAMADA') then
    raise exception 'No hay nada que calificar todavía (estado actual: %).', v_e.estado
      using errcode = '23514';
  end if;

  return query
  update public.m6_entregas as e
     set nota_borrador = p_nota
   where e.id = p_entrega_id
  returning e.id, e.tarea_id, e.estudiante_id, e.estado, e.es_tardia,
            e.nota_borrador, e.nota_asignada;
end;
$$;

comment on function public.m6_calificar_entrega(uuid, numeric) is
  'Escribe la nota BORRADOR: el alumno todavía no la ve. Sólo el docente de la sección, sólo sobre una entrega entregada, y nunca por encima de los puntos de la tarea.';


-- ---------------------------------------------------------------------------
--  8.7 Devolver (borrador → asignada)
-- ---------------------------------------------------------------------------
create or replace function public.m6_devolver_entrega(p_entrega_id uuid)
returns table (
  id            uuid,
  tarea_id      uuid,
  estudiante_id uuid,
  estado        text,
  es_tardia     boolean,
  nota_borrador numeric,
  nota_asignada numeric,
  devuelta_en   timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_e     public.m6_entregas;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para devolver una entrega.'
      using errcode = '42501';
  end if;

  select * into v_e from public.m6_entregas where m6_entregas.id = p_entrega_id;

  if not found then
    raise exception 'La entrega % no existe.', p_entrega_id
      using errcode = '23514';
  end if;

  if not public.m6_dicta_entrega(p_entrega_id) then
    raise exception 'No dictas la sección de esta entrega: no puedes devolverla.'
      using errcode = '42501';
  end if;

  -- Devolver SIN nota es legítimo (es el «devuelta sin calificar» de Google):
  -- lo que no puede haber es una nota asignada sin borrador, y de eso ya se
  -- encarga el CHECK de la tabla. Aquí sólo se exige que haya algo que
  -- devolver.
  if v_e.estado not in ('ENTREGADA', 'RECLAMADA') then
    raise exception 'No hay una entrega que devolver (estado actual: %).', v_e.estado
      using errcode = '23514';
  end if;

  return query
  update public.m6_entregas as e
     set estado        = 'DEVUELTA',
         nota_asignada = e.nota_borrador,
         devuelta_en   = now()
   where e.id = p_entrega_id
  returning e.id, e.tarea_id, e.estudiante_id, e.estado, e.es_tardia,
            e.nota_borrador, e.nota_asignada, e.devuelta_en;
end;
$$;

comment on function public.m6_devolver_entrega(uuid) is
  'Copia la nota borrador a la asignada, marca DEVUELTA y sella la fecha. Es el único momento en que el alumno ve una nota. Sólo el docente de la sección.';


-- ---------------------------------------------------------------------------
--  8.8 El libro del docente: leer las entregas CON `nota_borrador`
-- ---------------------------------------------------------------------------
--  Esta RPC no la pedía el diseño y es imprescindible: el GRANT por columna le
--  esconde `nota_borrador` a `authenticated`, así que la ruta del libro no
--  puede leerla con un SELECT normal. Sin esta función, la ruta habría nacido
--  devolviendo la columna en blanco —un fallo que no da error— y el docente
--  habría calificado a ciegas.
--
--  Devuelve `table(...)` explícita y no `setof m6_entregas` por lo mismo que
--  las RPC del alumno: una fila entera arrastraría la columna protegida.
create or replace function public.m6_entregas_de_tarea(p_tarea_id uuid)
returns table (
  id            uuid,
  estudiante_id uuid,
  estado        text,
  es_tardia     boolean,
  nota_borrador numeric,
  nota_asignada numeric,
  entregada_en  timestamptz,
  devuelta_en   timestamptz,
  -- Derivada, no almacenada: «faltante» es un juicio que depende del reloj y
  -- que caduca solo. Escribirlo como 0 sería congelar una opinión (decisión 1).
  faltante      boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select e.id,
         e.estudiante_id,
         e.estado,
         e.es_tardia,
         e.nota_borrador,
         e.nota_asignada,
         e.entregada_en,
         e.devuelta_en,
         (e.estado = 'ASIGNADA'
          and t.fecha_limite is not null
          and t.fecha_limite < now()) as faltante
    from public.m6_entregas e
    join public.m6_tareas  t on t.id = e.tarea_id
   where e.tarea_id = p_tarea_id
     and public.m6_dicta_entrega(e.id)
   order by e.estudiante_id;
$$;

comment on function public.m6_entregas_de_tarea(uuid) is
  'El libro de calificaciones de una tarea, con la nota borrador incluida (que el GRANT por columna esconde a authenticated). Deriva «faltante» al leer en vez de escribir un 0 automático. Sólo el docente de la sección.';


-- ---------------------------------------------------------------------------
--  PARTE 9 — Permisos de las funciones
-- ---------------------------------------------------------------------------
--  PostgreSQL concede EXECUTE a PUBLIC por defecto en toda función nueva: sin
--  el `revoke` explícito, `anon` podría llamar a las RPC. Se revoca de `public`
--  y `anon`, y se concede sólo a `authenticated` (la autorización fina la hace
--  cada función con `auth.uid()` / `is_admin()`).
--
--  Los cinco auxiliares de la PARTE 5 también se conceden: las políticas RLS
--  los invocan, y una política que llama a una función sin EXECUTE no falla
--  con un mensaje claro — simplemente no encuentra filas.
revoke all on function public.m6_dicta_seccion(uuid)              from public, anon;
revoke all on function public.m6_matriculado_en(uuid)             from public, anon;
revoke all on function public.m6_dicta_tarea(uuid)                from public, anon;
revoke all on function public.m6_dicta_entrega(uuid)              from public, anon;
revoke all on function public.m6_tarea_publicada_para_mi(uuid)    from public, anon;
revoke all on function public.m6_validar_entidad_de_archivo()     from public, anon;
revoke all on function public.m6_crear_anuncio(uuid, text, text, timestamptz) from public, anon;
revoke all on function public.m6_crear_tarea(uuid, text, text, text, numeric, timestamptz, boolean, text, integer) from public, anon;
revoke all on function public.m6_publicar_tarea(uuid)             from public, anon;
revoke all on function public.m6_entregar_tarea(uuid)             from public, anon;
revoke all on function public.m6_reclamar_entrega(uuid)           from public, anon;
revoke all on function public.m6_calificar_entrega(uuid, numeric) from public, anon;
revoke all on function public.m6_devolver_entrega(uuid)           from public, anon;
revoke all on function public.m6_entregas_de_tarea(uuid)          from public, anon;

grant execute on function public.m6_dicta_seccion(uuid)              to authenticated;
grant execute on function public.m6_matriculado_en(uuid)             to authenticated;
grant execute on function public.m6_dicta_tarea(uuid)                to authenticated;
grant execute on function public.m6_dicta_entrega(uuid)              to authenticated;
grant execute on function public.m6_tarea_publicada_para_mi(uuid)    to authenticated;
grant execute on function public.m6_crear_anuncio(uuid, text, text, timestamptz) to authenticated;
grant execute on function public.m6_crear_tarea(uuid, text, text, text, numeric, timestamptz, boolean, text, integer) to authenticated;
grant execute on function public.m6_publicar_tarea(uuid)             to authenticated;
grant execute on function public.m6_entregar_tarea(uuid)             to authenticated;
grant execute on function public.m6_reclamar_entrega(uuid)           to authenticated;
grant execute on function public.m6_calificar_entrega(uuid, numeric) to authenticated;
grant execute on function public.m6_devolver_entrega(uuid)           to authenticated;
grant execute on function public.m6_entregas_de_tarea(uuid)          to authenticated;


-- ---------------------------------------------------------------------------
--  PARTE 10 — Semilla del módulo
-- ---------------------------------------------------------------------------
--  Orden 55: entre M5 (50) y `m6_asistencia` (60), para que el aula aparezca
--  junto a los archivos que usa.
--
--  UN CONFLICTO DE NOMENCLATURA, DICHO EN VOZ ALTA
--  ----------------------------------------------
--  El catálogo de `202609120002` ya tenía reservada la clave `m6_asistencia`, y
--  detrás `m7_calificaciones` y `m8_pasantias`. Es decir: **el número 6 estaba
--  tomado**. Por eso la clave del aula virtual es `m6_aula_virtual` y **no** se
--  renombra `m6_asistencia`: la semilla dice que las claves nunca se renombran,
--  y renombrarla rompería cualquier referencia guardada. El nombre del archivo
--  de la migración no crea la clave.
--
--  `habilitado = false` a propósito. Ver la nota del encabezado.
insert into public.system_modules
  (clave, nombre, descripcion, habilitado, orden, icono, roles_permitidos, categoria)
values
  ('m6_aula_virtual', 'Aula Virtual',
   'Tablón de anuncios, trabajo de clase, entregas y calificaciones por sección.',
   false, 55, 'school', '{}', 'academico')
on conflict (clave) do nothing;
