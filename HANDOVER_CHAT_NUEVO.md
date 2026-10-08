# HANDOVER — Contexto completo para un chat nuevo con acceso al filesystem

> **Fecha:** 2026-10-06 · **Commit:** `f53a3ac` · rama `main`
> **Para:** un agente con acceso a `C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT`
>
> **Cómo usar este documento:** léelo entero antes de tocar nada. La sección §7
> («Reglas que costaron caro») es la más importante — **cada una salió de un error
> real cometido en el proyecto**, y saltárselas reproduce el error.

---

## 1. Qué es el proyecto

**LMS/Classroom a la medida del CFS Nacional de Soldadura «Rafael Urdaneta», INCES La Isabelica.**

**Es el Trabajo Especial de Grado de Lorenzo Roca** (Análisis de Sistemas, IUTEPI, 4º semestre, periodo SA26-2). Tutor: Prof. Maglis Camacho. Equipo: José Tarazón, Sleither Vásquez, Adrián Cedeño. **Se defiende ante un jurado — el peso académico es real.**

**NO es** el portal nacional del INCES, ni el Campus Virtual nacional, ni un LMS genérico, ni un sistema de certificación.

**Dentro:** portal público del CFS · oferta formativa · inscripción digital · Planilla Oficial · workflow de envío/observación/reenvío/aprobación · dashboard administrativo · roles · Aula Virtual · tareas · entregas · calificaciones · materiales · anuncios · horarios · asistencia QR · responsive · accesibilidad · seguridad · testing.

**Fuera:** certificación · QR de certificado · clon del portal nacional · arquitectura Cloud/Local · offline-first.

---

## 2. Stack real — verificado

```
Frontend:  Flutter Web (CanvasKit) · Dart · Material 3
Backend:   Node 22 · TypeScript · Fastify 5 · Zod · ESM
Datos:     Supabase · PostgreSQL 17.6 · RLS · triggers · RPC
Auth:      Supabase Auth · JWT
Storage:   Cloudflare R2
E2E:       Playwright
```

**Arquitectura del backend — respetarla:** `HTTP → Dominio/Puertos → Infraestructura → Supabase`. **El dominio NO conoce Fastify ni Supabase.** Los repositorios implementan los puertos. Zod define la entrada.

**El cliente Supabase se construye POR PETICIÓN con el JWT del llamante** (`repos-supabase.ts:1113` — `constructor(private readonly cliente: SupabaseClient)`). **Eso es lo que hace efectiva la RLS.** **No usar service-role en rutas normales.**

---

## 3. Estado cuantitativo

| Capa | Medida |
|---|---|
| Dart (frontend) | **125 archivos** |
| TypeScript (`backend/src`) | **44 archivos** |
| Migraciones | **40 aplicadas · 0 pendientes · 0 con deriva** |
| E2E (specs) | **12** |
| Tests backend | **27 archivos** |
| Tests Flutter | **66 archivos** |
| Documentos raíz `.md` | **~20** |

**Verde, con evidencia:** esquema (530 aserciones CI) · backend (`npm run verify`) ·
tipos Dart (207 archivos) · E2E (14 casos) · Aula Virtual (4/4 ×2) · registro de
aspirantes · workflow de planilla (7/7 + 44/44 local).

---

## 4. Git — el punto de partida real

```
rama: main · HEAD: f53a3ac
~11 archivos modificados · ~38 no rastreados
```

**Hay trabajo local SIN COMMITEAR y es valioso.** **Nunca** ejecutar
`git reset --hard`, `git clean`, `git restore`, `git checkout --`, `git stash` **ni
equivalentes**. **Inspeccionar antes de tocar, y preservar lo que no es tuyo.**

**Entre los no rastreados hay instrumentos de diagnóstico** (`supabase/_*.mjs`,
`e2e/tests/_*.spec.ts`). **Son evidencia y algunos funcionan — no borrarlos.**

---

## 5. Lo que existe y funciona — no rehacer

| Pieza | Estado |
|---|---|
| Landing pública | ✅ `lib/screens/landing_page.dart` — carga oferta real por `AspiranteRepository.obtenerProgramasDisponibles()`. Tiene pruebas |
| Registro de aspirantes | ✅ `POST /auth/v1/signup` → 200, `aspirantes` crece |
| Catálogo de inscripción | ✅ `inscripcion_campos` — **44 campos** (38 física + 6 sistema) |
| Formulario de inscripción | ✅ `aspirante_form_screen.dart` + `PUT /yo/planilla` |
| Planilla PDF/XLSX **genérica** | ✅ en uso — `planilla-pdf.ts` / `planilla-xlsx.ts` |
| Aula Virtual | ✅ 4/4 E2E |
| Asistencia QR (M7) | 🟡 nube ✓, sin validar en dispositivo físico |
| cPanel de inscripciones | ✅ el admin descarga planillas |
| RLS de `aspirantes` | ✅ 6 políticas, verificadas con JWT real |

---

## 6. Lo que está a medias — y su causa exacta

### 6.1 Planilla Oficial — **implementada y DESCONECTADA**

```
backend/src/dominio/planilla-oficial-tipos.ts     130 líneas
backend/src/infra/planilla-oficial-valores.ts     307 líneas
backend/src/infra/planilla-oficial-pdf.ts         277 líneas
backend/assets/planilla-oficial-template.pdf      el PDF oficial como plantilla
tests                                             6/6 ✓

imports desde backend/src                        0
rutas que lo invocan                             0
```

**Funciona en aislamiento y nadie la usa.** **Antes de conectarla:** resolver la ruta
de la plantilla en despliegue **y** decidir si el PDF se genera desde
`planilla_versiones.datos_snapshot` (contrato) o desde `datos_planilla` vivo.

### 6.2 Workflow de planilla (E-2) — servicio listo, medición HTTP pendiente

**Migraciones aplicadas:** `202610060001` (tablas) · `0002` (transiciones exactas) ·
`0003` (cierre de bypass admin) · `0004` (integridad de aprobación y observaciones) ·
`0005` + `0006` (observar atómico por RPC).

**Verificado con JWT reales a nivel DB/PostgREST:**

| Invariante | Estado |
|---|---|
| Transiciones exactas (4 ✓ / 3 ✗) | ✅ |
| Snapshot · `numero` · `aspirante_id` · `enviada_at` inmutables | ✅ |
| **Auditoría de aprobación inmutable** | ✅ 409, fila intacta |
| **DELETE administrativo** | ✅ las 4 versiones sobreviven |
| INSERT administrativo | ✅ 403 ×8, nada persistido |
| Observación sólo sobre `ENVIADA` | ✅ 403 |
| `p_admin_id = auth.uid()` | ✅ en la función |

**Servicio implementado** — `puertos.ts:905-909` y `repos-supabase.ts:3343-3411`:
`enviarPlanilla` · `reenviarPlanilla` · `versiones` · `observarPlanilla` ·
`aprobarPlanilla`. **Rutas:** `rutas/yo.ts:71,77,83` y `rutas/planilla.ts:114,122`.

**`observarPlanilla` usa el RPC `observar_planilla_atomico`** (transición + observación
en una sola función PL/pgSQL = una transacción).

**Validación canónica:** `this.cliente.rpc('validar_planilla', { p_datos })`
(`repos-supabase.ts:3284`). **Medido: planilla incompleta → `422 PLANILLA_INCOMPLETA`
con la lista de campos faltantes y `detalles.contexto`.** ✅ **Ya funciona.**

### 6.3 Error handler — **el defecto real, medido**

```
FST_ERR_CTP_EMPTY_JSON_BODY  →  Fastify trae statusCode 400  →  respuesta 500 ⚠️
23514 de transición E-2      →                              →  500 ⚠️
23514 de validar_planilla    →                              →  422 ✅ ya funciona
```

**Causa raíz:** `errores.ts:63` es un pozo genérico que convierte en 500 todo lo que
no sea `ErrorApi`. **`errores.ts:52` YA tiene rama para `FST_ERR_CTP_INVALID_MEDIA_TYPE`
→ 400** — falta la hermana.

**`traducir-error.ts` YA traduce** `23502`, `23505`, `23514`, `23503`, `42501` y
códigos PostgREST. **No falta traducir `23514`: falta que el contexto llegue.**
**Y el contexto ya viaja** — `traducirError(error, 'observar la planilla')` — **el
segundo argumento existe y se usa.**

**Solución propuesta, sin implementar:** dos ramas antes del pozo — (1) si el error
trae `statusCode` **4xx**, usarlo (cubre todos los `FST_ERR_CTP_*`, no enumerarlos);
(2) `23514` mapeado **por contexto**: transición→409, validación→422, resto→500.

**NO traducir por el texto del mensaje** — es lo que hizo `_razonDeGotrue` en el
registro y **fue un error**: comparaba subcadenas contra un cuerpo JSON y acertaba por
lo que el texto llevaba dentro.

### 6.4 Rol `jefe_cfs` — **NO EXISTE**

```sql
check (rol in ('admin', 'docente', 'estudiante'))   -- 202609100001_init.sql:17
```

`grep -rn "jefe|JEFE" supabase/migrations/*.sql` → **0 coincidencias**.

**Propuesta:** un rol más, **con `is_jefe_o_admin()` propia — NO reutilizando
`is_admin()`**, porque si comparten función las políticas no distinguen los roles y
el rol no sería una entidad de autorización real. **La persona no se hardcodea** —
`profiles.rol` es una columna.

### 6.5 `SEM-SOL-CL` — dato de sembrado visible en el portal público

```
id:  d7fc4be5-630d-433f-ba92-36934ad612ae
code: SEM-SOL-CL · name: "Soldadura Básica [SEMILLA]"
type: CURSO_LIBRE · is_active: true
creador: supabase/sembrar-datos.mjs
```

**La landing muestra los `CURSO_LIBRE` activos** → **el portal público está mostrando
un dato de sembrado como oferta institucional.** **No borrar** (hay FKs). **Es una
decisión de producto.**

### 6.6 Despliegue — **NO VERIFICADO**

```
backend/Dockerfile   EXISTE
docker-compose.yml   EXISTE
render.yaml          no existe
Procfile             no existe
proveedor real       NO VERIFICADO
```

**Y esto bloquea la plantilla del PDF:** el renderer la busca en **4 rutas
candidatas** y funciona porque `cwd` es `backend/`. **En despliegue podría no
encontrarla y el PDF saldría en blanco sin fallar.**

---

## 7. Reglas que costaron caro — **cada una salió de un error real**

**1 · Medir antes de afirmar.** «No está» se mide, no se deduce.

**2 · La ausencia en un renderer significa «no se renderiza aquí», NO «el sistema no
posee el dato».** Confundirlos produjo una conclusión falsa en la auditoría de la
planilla: `numero_preimpreso` **sí existía**, estaba en una migración.

**3 · Los errores del sistema traen el dato; usarlo antes de suponer.** Los tres
errores de provisión de identidades de esta sesión los dijo PostgreSQL con su código
y su mensaje: `PGRST204` (columna inexistente), `23502` (NOT NULL), `42702` (columna
ambigua). **Ninguno se adivinó.**

**4 · Una condición de salida debe ser imposible de satisfacer sin que ocurra lo que
dice medir.** `buttons > 2` se satisface con la pantalla anterior.

**5 · No mezclar métricas:** duración del test ≠ del comando ≠ del teardown. En una
corrida sana `comando − test ≈ 4 s`. Confundirlas produjo una hipótesis de
«acumulación» que era un artefacto.

**6 · Un instrumento que no comprueba su propia precondición miente.** **Seis
instrumentos escritos en una sesión, cuatro fallaron por su construcción** — y sus
fallos parecían del sistema. **Abortar si falta un token, si un paso previo falló, si
el cuerpo es obligatorio.**

**7 · Un verificador que da verde mientras el CI da rojo es peor que no tenerlo.**
`tsc --noEmit` daba 0 errores **y `npm run build` fallaba** — usan `tsconfig.json` y
`tsconfig.build.json`. **Ejecutar el build, no sólo el typecheck.**

**8 · Dos identidades no caben en una función.** `apikey` + `Bearer`:
```
service-role:  apikey: <SERVICE_KEY>  +  Bearer <SERVICE_KEY>
usuario:       apikey: <ANON_KEY>     +  Bearer <JWT del usuario>
```

**9 · Salida cruda a archivo, sin tuberías** — `| grep` retiene la salida.

**10 · Nunca editar una migración aplicada.** Nuevas: `YYYYMMDDNNN_descripcion.sql`.

**11 · Un trigger `security definer` salta la RLS por dentro** — compensarlo
re-comprobando `is_admin()` **explícitamente**.

**12 · Una función de trigger NO se puede llamar directamente** (`0A000`). Se prueba
ejerciendo el trigger con filas reales.

**13 · En RLS, el `with check` es lo que impide el auto-ascenso.** Sin acotar el
estado destino, un usuario puede insertar una fila ya `APROBADA` por PostgREST.

---

## 8. Trampas del entorno — medidas

**1 · `NO_PROXY="127.0.0.1,localhost"` SIEMPRE.** Sin él el proxy se come el
health-check, Playwright da el backend por «ya corriendo», **no lo arranca**, y el
navegador da `ERR_CONNECTION_REFUSED` **con el mismo texto que un 500**.

**2 · `flutter build web` NO arranca aquí** (`ERROR_PIPE_BUSY` 231). Tipos:
`node devops/analizar-dart.mjs .`. El bundle viene del artefacto `web-bundle` del CI.

**3 · `tasklist /FI` da falso negativo desde Git Bash.** Para procesos y puertos,
`netstat -ano`.

**4 · El *safe-delete shim* bloquea `test-results/`.** Usar `--output=/c/tmp/pw-$(date +%s)`.

**5 · El teardown de Playwright puede no volver.** `timeout` externo siempre.

**6 · El heredoc de Git Bash corrompe backslashes y `${…}`.** Pasar scripts como
**archivo**, no por stdin.

**7 · En CanvasKit:** `dispatchEvent('click')` **no siempre** dispara el gesto de
Flutter; y `locator.boundingBox()` sobre `flt-semantics` **da 0** mientras el centro
que publica el nodo semántico **da 3**.

**8 · `flutter analyze` SÍ falla por `info`.** El verificador local debe contar los
tres niveles.

---

## 9. Documentos del proyecto — leer antes de actuar

| Documento | Qué contiene |
|---|---|
| `ESTADO_DEL_SISTEMA.md` | estado vivo (gana el código) |
| `HANDOVER.md` | histórico, inmutable hacia atrás |
| `LEVANTAR_EN_LOCAL.md` | arranque + las 5 trampas del entorno |
| `AUDITORIA_PLANILLA.md` | trazabilidad de la planilla oficial |
| `CONTRATO_E2_PLANILLA_OFICIAL.md` | contrato funcional del workflow |
| `DISENO_E2_PERSISTENCIA.md` | diseño de las tablas y la inmutabilidad |
| `PLANILLA_OFICIAL_RENDERER_DISENO.md` | geometría medida del PDF oficial |
| `AUTOPROMPT_PLANILLA.md` | prompt autocontenido para retomar |
| `docs/CLINE_AUDITORIA_FASE_0.md` | auditoría del portal, roles, landing |
| `docs/CLINE_FASE_0_5_BLOQUEADORES.md` | bloqueadores y su estado |
| `docs/CLINE_BLOQUE_E_ERROR_HANDLER.md` | el error handler, medido |

**`PLAN_MAESTRO.md` NO se toca.** Es el plan del equipo.

---

## 10. Decisiones aprobadas — **no reabrir sin evidencia nueva**

1. **FECHA** = fecha de ENVÍO de la versión impresa
2. **PROYECTO** = `aspirantes.program_id → programs.code`
3. **EIS** = `schedule_slots.classroom_id → classrooms.name`
4. **Transiciones:** `ENVIADA→OBSERVADA` · `ENVIADA→APROBADA` · `OBSERVADA→REENVIADA` · `REENVIADA→APROBADA`. **Prohibidas:** `OBSERVADA→APROBADA` · `REENVIADA→OBSERVADA` · `APROBADA→cualquiera`
5. **Diversidad funcional y estado civil** = texto libre
6. **La aprobación registra** `approved_by`, `aprobada_at`, versión
7. **HORARIO** se deriva de matrícula `ENROLLED`
8. **El PDF oficial coexiste** con las exportaciones genéricas
9. **El PDF oficial representa una versión** (snapshot), no la ficha viva

**Y la cadena académica, verificada:**
```
auth.users → enrollments.student_id → sections.id → schedule_slots.section_id
                                                    ├→ classroom_id → classrooms
                                                    └→ profile_id   → el docente
```

---

## 11. Decisiones PENDIENTES — del propietario, no del agente

1. **¿Qué puede hacer el Jefe del CFS?** — sin esto `jefe_cfs` no se crea
2. **¿Portal público y académico comparten sesión?**
3. **¿La oferta pública son los `programs` `CURSO_LIBRE` activos?** — y **qué hacer con `SEM-SOL-CL`**
4. **¿Dónde corre el backend en despliegue?**
5. **¿`jefe_cfs` y `admin` comparten función o no?**

---

## 12. Estado del servidor de prueba

**El backend suele quedar vivo en `3001`** tras las pruebas. **Detenerlo** antes de
terminar. Para arrancarlo: `cd backend && node --env-file-if-exists=.env dist/server.js`
**y compilar antes con `npm run build`** — si `tsc` falla, `dist/` queda viejo y **las
rutas que responden no son las del código**.

---

## 13. Próximos pasos, en orden

```
1 · Bloque E — error handler
      Dos ramas: `statusCode` 4xx de Fastify, y `23514` por contexto.
      Es acotado, y todo lo que se construya encima hereda el defecto.
      Requiere: medir el 23514 del trigger por HTTP (pendiente).

2 · Medición HTTP del workflow (B1–B16)
      Con E arreglado, los 409 se distinguen de los 500.

3 · Decidir el despliegue → desbloquea la plantilla del PDF

4 · jefe_cfs (requiere la matriz aprobada)

5 · Conectar el renderer oficial (depende de 3 y 4)

6 · Portal / Landing (Fase 1–2)
```

---

## 14. Cómo trabaja el propietario — importante

- **Pide diagnóstico y plan ANTES de que se escriba código.** Trabaja por fases y **da luz verde explícita** antes de avanzar. **No adelantarse.**
- **Valora que se explique el «por qué»** de cada decisión arquitectónica. Está aprendiendo: **quiere criterio, no dependencia.**
- **Reacciona bien a que se le señalen bugs con evidencia** (archivo, línea, consecuencia). **No endulzar el diagnóstico.**
- **Le molesta** el relleno, las respuestas evasivas y **que se afirme algo sin verificarlo**.
- **Habla español, de tú.**
- **Restricción real del entorno:** hay problemas de suministro eléctrico en Venezuela. El sistema debe poder operar 24/7 en la nube **y** poder correr en un servidor local como respaldo. **Aunque en esta fase Cloud/Local está FUERA del alcance del portal.**

---

## 15. Y lo que hay que hacer con este documento

**Es contexto, no una tarea.** El chat nuevo **debe empezar verificando el estado
real** — `git status`, el ledger de migraciones, y **si el backend responde** —
**porque este documento describe el estado en `f53a3ac` y el árbol puede haber
cambiado.**

**Si algo de aquí contradice lo que el código dice: gana el código.** Este documento
es un mapa; **el territorio es el repositorio.**

**Y la advertencia que resume la sesión de la que sale:** **en el proyecto se han
sacado conclusiones falsas por inferir en vez de medir** — «el dato no existe»
(existía), «son 9 columnas» (son 8), «el Dockerfile no existe» (existía, estaba en
`backend/`). **Medir es más lento y siempre sale más barato.**
