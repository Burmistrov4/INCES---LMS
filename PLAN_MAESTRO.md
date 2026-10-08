# Plan Maestro — LMS INCES La Isabelica

> **Documento de traspaso para un arquitecto de software senior.**
> Todo lo que sigue está **medido**, no supuesto. Donde una cifra o una causa no
> se pudo medir, se dice explícitamente y se marca como **ABIERTO**.
>
> **Fecha:** 2026-10-02 · **Autor del levantamiento:** sesión de trabajo sobre el
> repositorio `github.com/Burmistrov4/INCES---LMS` (rama `main`, `a76116b`).

## ESTADO DE EJECUCIÓN VIGENTE — 2026-10-08

**Fase activa: PERFORMANCE.** F1 (correo/password recovery con Resend) está DEFERIDA por decisión de producto. El orden vigente es: Performance → Responsive (375/768/1024/1280/1440) → UI/UX global → 3D/animaciones con presupuesto de rendimiento → Android → regresión/auditoría final.

**Evidencia de cierre funcional reciente:** Aula Virtual real 7/7 PASS; batería Flutter focalizada 84/84 PASS; backend verify 658/658 PASS; invitaciones 19/19 PASS; R2 52/52 PASS; F2 Planilla VERDE/CERRADA. Producción Pages HTTP 200, API Render HTTP 200 después de cold start y CORS correcto.

**Performance ya medido:** build/web-final ≈41.43 MiB en 39 archivos; 27.50 MiB son WASM, 8.18 MiB symbols y 4.01 MiB JS. main.dart.js ≈3.57 MiB sin compresión. Producción sirve Brotli, pero sus estáticos estaban con Cache-Control: public, max-age=0, must-revalidate.

**Acción actual:** se añadió web/_headers para cachear HTML/bootstrap durante 5 min, main.dart.js 1 h y artefactos estáticos 7 días. **P-01 no está cerrado** hasta reconstruir, desplegar y verificar HEAD real. El renderer Flutter Web no se cambia todavía.

**Siguiente discriminador:** medir AspiranteRepository.obtenerTodos() / SupabaseService.todos() y su payload real; sólo después decidir paginación/columnas mínimas. No modificar contratos por intuición.

**Handover obligatorio:** MEMORY.md y docs/AUDITORIA_RENDIMIENTO_2026-10-08.md son la memoria operativa de esta fase. No borrar probes/documentos sin clasificarlos primero.

---

---

## 0. Contexto y objetivo

**Qué es.** LMS a la medida del CFS Nacional de Soldadura «Rafael Urdaneta»
(INCES La Isabelica). Es un **Trabajo Especial de Grado** de Análisis de
Sistemas (IUTEPI, 4.º semestre, lapso SA26-2), así que el peso académico es real:
lo que se construya se defiende ante un jurado.

**Meta declarada del autor:** superar a Google Classroom, 100 % a la medida del
INCES, digitalizando la **Planilla de Inscripción** física y sus procesos.

**Nota de contexto (2026-10-02).** En esta conversación circuló una instrucción
que pedía diseñar una **arquitectura dual Cloud/Local** —servidor local, modo
offline, selector de servidor, sincronización— apoyándose en los cortes
eléctricos del país. **Esa instrucción pertenecía a OTRO proyecto y fue un error
humano de contexto: queda fuera del alcance de INCES-LMS-PROJECT.** La
arquitectura objetivo de este proyecto se determina **exclusivamente** por su
código, su base de datos, sus migraciones, su configuración, su documentación
real, sus pruebas y sus requisitos funcionales. Ver §4.

**Stack real** (corrige una suposición frecuente: **no es Next.js**):

| Capa | Tecnología |
|---|---|
| Frontend | **Flutter Web** compilado a **CanvasKit** |
| Backend | **Node/TypeScript — Fastify 5 + Zod**, ESM |
| Base de datos | **Supabase (PostgreSQL 17.6 + RLS)** |
| Almacenamiento | **Cloudflare R2** |
| E2E | **Playwright** contra la app servida y el backend reales |

**Roles:** 3 — administrador, docente, aprendiz.

---

## 1. Reglas de ingeniería del proyecto (no negociables)

Estas reglas no son estilo: cada una costó un fallo real y está aquí para que no
se repita.

1. **Medir antes de afirmar.** «No está» se mide, no se deduce. Una nota de
   «falta hacer X» envejece peor que una cifra y **provoca trabajo**: en este
   repositorio hubo una nota que decía «el registro de aspirantes NUNCA ha
   funcionado» que era cierta el 2026-09-29 y **caducó** al día siguiente.
   **Incluye los comentarios del código**: un comentario que explica *por qué*
   algo está cubierto es una afirmación, y si el mecanismo que cita es falso, la
   cobertura es casual.
2. **Una cifra de contraste no entra en un comentario si no sale del medidor.**
   La aritmética a mano se equivocó **dos veces en el mismo día**.
3. **Dart local: `analyze`, `test` y `build web` NO arrancan en este equipo**
   (`ERROR_PIPE_BUSY` 231: el VM de Dart no puede crear procesos hijos). Los
   sustitutos, en orden de lo que cubren:
   - `node devops/analizar-dart.mjs .` → **verifica tipos de verdad** (207
     archivos, protocolo `analyzer`, JSON por saltos de línea). Es el listón del CI.
   - `dart pub get --offline` **sí** funciona.
   - `dart format` **comprueba sintaxis, no tipos** — un identificador inexistente
     lo atraviesa.
   - `flutter test` y el build web son cosa de **CI**.
4. **El `push` es el respaldo.** Hubo un `.git` dañado; el remoto es la copia sana.
5. **Migraciones `YYYYMMDDNNN_*.sql`; NUNCA editar una aplicada.** El libro mayor
   detecta deriva.
6. **La frontera de autorización es la RLS, no la API.** El administrador y el
   catálogo leen por **PostgREST directo**, no por Fastify.
7. **Una política RLS que llama a una función con `EXECUTE` revocado es
   inalcanzable.** PostgreSQL evalúa el `EXECUTE` **contra el rol que consulta**,
   así que la política muere con `42501` **antes de decidir nada**.
8. **Los verificadores viven fuera del repo** (`C:/tmp/...`), salvo
   `devops/analizar-dart.mjs` —dentro a propósito, porque compensa el `231`
   crónico— y los de `supabase/` que sí van contra la nube.

---

## 2. Estado actual del sistema

### 2.1 Lo que está en verde

| Componente | Estado | Evidencia |
|---|---|---|
| Módulos del sistema | **11 filas, 8 encendidas** | apagadas: `m6_asistencia`, `m7_calificaciones`, `m8_pasantias` |
| Migraciones | **34 aplicadas, 0 pendientes, 0 con deriva** | `apply-migrations.mjs --check` |
| Catálogo | 58 funciones / 52 políticas | `verificar-esquema.mjs` |
| CI de esquema | **530 aserciones, 0 fallidas** | `Supabase CI` (PGlite) |
| CI de Flutter | verde | `Flutter CI` |
| **CI de E2E** | **14 casos en verde** | `export_csv` 10 · `stepper_inscripcion` 1 · `aula_virtual` (aprendiz) 3 |
| Registro de aspirantes | **funciona** | `POST /auth/v1/signup` → 200 y `aspirantes` pasa de 0 a 1 fila |
| Asistencia QR (M7) | funcional en la nube | cámara y UI Dart hechas; **falta validación en dispositivo físico** |

### 2.2 Infraestructura de pruebas E2E — construida y funcionando

El arnés local es la pieza que hace barato escribir E2E aquí:

```bash
# El bundle se descarga del artefacto que publica el propio CI,
# porque `flutter build web` no arranca en el equipo de desarrollo (el 231).
gh run download <run-id> -n web-bundle -D /c/tmp/web-bundle
cp -r /c/tmp/web-bundle build/web

cd e2e && CI=true NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost" \
  npx playwright test <spec> --reporter=list --output=/c/tmp/pw-out-$(date +%s)
```

**Cuatro trampas del entorno, las cuatro medidas, las cuatro producen un mensaje
que señala al sitio equivocado:**

1. **`HTTP_PROXY` presente.** El chequeo de salud del backend va por el proxy, el
   proxy responde, Playwright da el backend por «ya corriendo» y **no lo
   arranca**. El navegador recibe `ERR_CONNECTION_REFUSED` y la app muestra «No
   pudimos conectar con el servidor» — el mismo texto que daría un 500.
2. **El *safe-delete shim* de la CLI** bloquea la limpieza de `test-results/` y el
   fallo aparece como error de Playwright. Se evita con `--output=<dir nuevo>`.
3. **Backend arrancado a mano** usa la `CORS_ORIGINS` de `backend/.env`
   (`localhost:8090`) en vez de la que el arnés inyecta (`127.0.0.1:8090`).
   **Para el navegador son dos orígenes distintos.**
4. **El teardown se cuelga**, así que `EXIT=124` con los `ok` ya impresos **es un
   verde**, no un fallo.

### 2.3 Dos hallazgos de CanvasKit que gobiernan toda la interacción

* **`dispatchEvent('click')` no conmuta un `role="tab"`.** Medido con diferencia
  de conjuntos de etiquetas: **0** nuevas con el evento despachado, **3** con un
  `mouse.click` real. El `TapGestureRecognizer` de Flutter no registra el evento
  sintético sobre una pestaña —y sí sobre un botón—. Por eso `pulsar` conserva el
  despachado y el gesto de pestaña vive aislado en `FlutterApp.pulsarPestana`.
* **La geometría del nodo semántico no es la del DOM.**
  `locator.boundingBox()` sobre `flt-semantics` da **0** etiquetas nuevas; el
  centro que publica `nodos()` da **3**. Sólo la segunda sirve.

---

## 3. BLOQUE 1 — El ciclo docente↔aprendiz del Aula Virtual

**Estado: EN PROGRESO, con un bloqueante abierto y nombrado.**

### 3.1 Lo que ya está resuelto

* `AulaVirtualPage.ts` — navegación, apertura del aula, pestañas, conteo y firma
  del árbol, todo por la capa semántica del repositorio.
* `aula_virtual.spec.ts` — mitad del aprendiz, **3/3 verde en local y CI**.
* Rótulos **medidos** del panel docente y de los dos modales:

```
Panel de trabajo:  «Nueva tarea»  ·  «Calificar»
Tarea sembrada:    «Práctica 1: junta a tope [SEMILLA] · Tarea de ejemplo del
                    sembrado. Publícala para generar las entregas. · Tarea · 10 pts»
Modal de creación: NUEVA TAREA O MATERIAL · Tipo · «Crear y publicar» (confirmar)
                   · Tarea (se califica) · Fecha límite… · Permitir entrega tardía · Back
Campos del modal:  {"aria":"Título","tipo":"text"}
                   {"aria":"Puntos máximos (0–20, opcional)","tipo":"text"}
                   {"aria":"Tema / agrupación (opcional)","tipo":"text"}
```

**El modal crea y publica en un solo gesto.** No hay `Publicar` ni `Aceptar`; el
`BORRADOR` del sembrado es estado del seed, **no del flujo**.

### 3.1-bis Arranque de Flutter Web — **RESUELTO / VERIFICADO**

Medido el 2026-10-02 con captura de consola, errores de página y red:

```
script[src*="flutter_bootstrap"]          (1350 ms)
script[src*="main.dart"]                  (1410 ms)
flutter-view                              (8025 ms)
flt-glass-pane                            (8049 ms)   ← APARECE
flt-semantics-placeholder, flt-semantics  (8066 ms)
Errores de página: NINGUNO · Red fallida: NINGUNA
ARRANQUE COMPLETO: 8081 ms
```

`AppConfig.validate()`, `Supabase.initialize()` y `runApp()` **completan**.
Único mensaje de consola: un *warning* de rendimiento de WebGL
(`GPU stall due to ReadPixels`). **Un timeout de 8 s dentro de un límite de 60 s
no es bloqueante hoy**, aunque conviene tenerlo presente en runners en frío.

**No volver a investigar `flt-glass-pane` sin evidencia nueva que contradiga
esto.**

### 3.2 El bloqueante abierto

El spec del ciclo (`aula_virtual_ciclo.spec.ts`) **falla al conmutar de pestaña**,
y la causa **NO está identificada**. Lo que sí está medido:

| Configuración | Conmutación |
|---|---|
| Sonda con **un `test()` plano** | ✅ **funciona** (1.3 min) |
| Spec con **`test.describe.serial` + `beforeAll`** | ❌ **falla siempre** |
| Spec con `bringToFront()` antes del click | ❌ |
| Spec con login perezoso (un solo contexto vivo) | ❌ |

#### Bisectado ejecutado — **A y B descartadas**

Un solo archivo con **tres casos que ejecutan la misma secuencia** y sólo difieren
en el elemento estructural. El primero es el control y **tiene que pasar**.

| Caso | Estructura | Resultado | Tiempo |
|---|---|---|---|
| **T1** CONTROL | `test()` plano, login dentro | ✅ **PASA** | 24.0 s |
| **T2** = A | dentro de `describe.serial`, login en el test | ✅ **PASA** | 14.6 s |
| **T3** = A+B | `describe.serial` + login en `beforeAll` | ✅ **PASA** | 5.2 s |

**Conclusión: `describe.serial` (A) y `beforeAll` (B) quedan DESCARTADAS por
medición.** La conmutación de pestaña funciona en las tres estructuras, incluida
la que el spec del ciclo usa. **El control pasó**, así que el experimento es
válido.

**Lo que esto implica:** la diferencia **no es estructural**. Sigue en pie el
sospechoso **C (orden/dependencia entre casos)** o **D (estado persistente)** — el
spec del ciclo tiene **cuatro** casos y el que falla es el primero, que corre
después del `beforeAll`… exactamente como T3, que pasa. Queda un elemento sin
reproducir: **el resto del archivo** (los otros tres casos declarados).

**Hipótesis refutadas por medición, acumuladas:** concurrencia de contextos ·
`bringToFront` · login perezoso · `describe.serial` · `beforeAll` · arranque de
Flutter.

**Hipótesis vivas:** orden/dependencia entre casos · estado persistente del
navegador o del contexto · algo específico del contenido del spec del ciclo que
el bisectado no reprodujo.

**Siguiente discriminador, y no es otra hipótesis:** reproducir el spec del ciclo
**recortado a un solo caso** —el primero, idéntico— y ejecutarlo. Si pasa, el
culpable es el resto del archivo; si falla, el culpable es algo del propio caso
que el bisectado no replicó, y se compara línea a línea.

### 3.3 Decisión de producto que hay que tomar (no se cierra midiendo)

El ciclo debe ser **autocontenido**: crear y publicar → entregas → entregar como
aprendiz → calificar → devolver. Pero **publicar muta los datos de la demo**, lo
que choca con el principio de sembrado inmutable.

**Decisión ya tomada por el autor: Opción A** — el spec crea su **propia** tarea y
**no toca la sembrada**. Consecuencia asumida: quedan tareas acumuladas en la demo.

### 3.4 Lo que falta medir

**`CAMPO_NOTA` y `BOTON_DEVOLVER`** del libro de calificaciones. **No son
medibles con el estado sembrado**: la tarea está en `BORRADOR` y no tiene
entregas, así que el libro abre vacío y no hay ni campo de nota ni botón de
devolución que observar. Se medirán en cuanto el ciclo publique su primera tarea.

**Regla que sale de aquí:** en esta sesión la inferencia de rótulos falló **cuatro
veces medidas** (el regex de los corchetes, el panel «vacío», el click despachado,
y `BOTON_CONFIRMAR = 'Aceptar'` cuando el real es `Crear y publicar`). **No se
inventan localizadores.**

---

## 4. BLOQUE 2 — RETIRADO: la línea de «modo local» no pertenece a este proyecto

> **Corrección de contexto (2026-10-02).** Una instrucción anterior de esta
> conversación pidió diseñar e implementar un «modo local / Cloud vs Local»:
> pantalla para introducir la IP de un servidor local, persistencia de esa
> configuración, resolución en cascada de `API_BASE_URL`, indicador de modo,
> arquitectura offline-first. **Esa instrucción pertenecía a OTRO proyecto y fue
> un error humano de contexto. Queda eliminada de este documento y del alcance
> de INCES-LMS-PROJECT.**
>
> **Nada de eso se implementa, se diseña ni se registra como deuda pendiente.**
> Si aparece en cualquier otro documento del repositorio, se corrige.

**Lo que sí es cierto, y es sólo un dato descriptivo, no una tarea:**
`lib/core/config/app_config.dart` define la configuración con
`String.fromEnvironment(...)`, es decir **constantes de compilación** resueltas
con `--dart-define` en el momento del build. Eso es una propiedad de la
arquitectura actual y se documenta como tal.

**Y lo que importa para diagnosticar el arranque (§6, P0):** si el bundle se
compila **sin** esas variables, o con valores vacíos o inválidos, `AppConfig`
queda mal formada y `Supabase.initialize(...)` puede fallar **antes de
`runApp(...)`** — que es exactamente la clase de fallo que produce que
`flt-glass-pane` no llegue a aparecer. La pregunta correcta **no** es «cómo
apuntar a un servidor local», sino:

* ¿qué variables existen y cuáles son obligatorias?
* ¿cómo se proporcionan durante el build del E2E y del despliegue?
* ¿qué ocurre si faltan?
* ¿qué ocurre si tienen un valor inválido?
* ¿`AppConfig.validate()` corre antes o después de `Supabase.initialize()`?

---

## 5. BLOQUE 3 — Deudas técnicas abiertas, con su evidencia

### 5.1 Login con cédula — **resuelto en este ciclo** (`d63d3b6` + `a76116b`)

Estaba **muerto por construcción**, con dos causas apiladas:

1. `profiles.cedula` está rellena en **1 de 6** perfiles. La cédula real vive en
   `aspirantes`.
2. Las tres políticas de `profiles` son **todas para `authenticated`**. Ninguna
   incluye `anon`, así que una consulta sin sesión devuelve **0 filas** y el
   cliente lo lee como «la cédula no existe».

**Arreglado** con la RPC `email_por_cedula(text) returns text` — `security
definer`, contrato de retorno único, normalización por dígitos en ambos lados,
`REVOKE ALL FROM PUBLIC` antes del `GRANT`, y autocomprobación de cuatro
aserciones al aplicar.

**Riesgo aceptado y documentado en el propio archivo:** la función es un
**oráculo de existencia** —un anónimo puede comprobar si una cédula está
registrada—. Se aceptó a cambio de un login coherente.

**Pendiente:** aplicar la migración ya se hizo; **falta verificar el login con
cédula de extremo a extremo en la app** (el cambio de cliente está empujado pero
no ejercitado por ninguna prueba).

### 5.2 El «botón de reinicio» del sembrado no es incondicional

`node supabase/sembrar-datos.mjs --limpiar --confirmar` **se detiene** con
`23503` porque **una ficha real** —la del propio autor— referencia un programa del
sembrado. Los programas del sembrado nacen **activos**, así que cualquiera puede
inscribirse en ellos y a partir de ahí su ficha es dato real que la clave foránea
protege.

**Corrección correcta:** que el script **enumere** las fichas ajenas antes de
intentar el borrado y se detenga con un mensaje que diga **cuáles**, en vez de un
`23503` crudo. **No** borrar «en cascada»: eso destruiría una inscripción real.

**Y una lección operativa que hay que dejar escrita:** una limpieza que se
detiene **no deja el sistema como estaba** —borra hacia arriba hasta donde
llega—. Tras cualquier limpieza fallida hay que **volver a sembrar**, no dar por
hecho que no cambió nada. (Esto costó un diagnóstico falso: «Mis aulas» salía
vacío porque una limpieza detenida había borrado el cuadrante.)

### 5.3 La cuenta personal del autor no tiene matrícula

`lorenzoroca333@gmail.com` entra bien, pero «Mis aulas» responde «Todavía no
tienes aulas activas». Por eso el aprendiz del E2E es una cuenta del sembrado.
**Es una decisión de datos, no un bug** — pero conviene decidir si la cuenta del
autor debe tener ficha y matrícula para las pruebas manuales.

---

## 6. BLOQUE 4 — Correcciones de UI/UX pendientes (pedidas por el autor)

Todas verificadas contra el código; ninguna implementada todavía.

| # | Corrección | Estado en el código |
|---|---|---|
| 1 | **Modo claro por defecto** con paleta institucional | El modo oscuro es el actual; paleta acordada: primario `#003366`, fondo `#F8F9FA`, texto `#1A1A1A` |
| 2 | **Localización `es_VE`** del `DatePicker` | Hoy se renderiza en inglés (`February 2000`, `Cancel`, `OK`). Falta `flutter_localizations` + `locale: Locale('es','VE')` |
| 3 | **Género: sólo Femenino / Masculino** | El catálogo incluye «Otro». La planilla física del INCES sólo contempla dos |
| 4 | **Representante legal condicional** | Debe colapsarse si la fecha de nacimiento calcula ≥ 18 años |
| 5 | **Solape de etiquetas flotantes** en los `TextField` de inscripción | Bug de renderizado reportado |
| 6 | **Descarga de la planilla PDF desde el Dashboard** | Si el aprendiz omite la descarga en la confirmación, la opción desaparece |
| 7 | **Sidebar colapsable** | Mejora de UX pendiente |
| 8 | **Permisos en «Material de apoyo»** | Un **aprendiz** ve botones de carga que sólo debería tener el docente. **Bug de permisos** |
| 9 | **Sanitizar el sufijo `[SEMILLA]`** en la UI | Aparece en la oferta de cupos y en «Mi inscripción» |
| 10 | **Anuncios del tablón con jerga interna** | Hay textos como «creado por el sembrado. El tablón de m6 ya tiene contenido» que un aprendiz no debe leer |
| 11 | **Vocabulario de asignación de cupos** | «Bids» / «Pujas» deben pasar a «Solicitud de cupo» / «Asignación de cupo» / «Lista de espera» |

**Nota de orden:** el punto 9 y el secreto `E2E_SECCION` están **acoplados**. El
título de la tarjeta **es** el texto que busca el E2E; sanitizar el sufijo cambia
ese texto y vuelve a dejar obsoleto el secreto. **Se hacen juntos o no se hacen.**

---

## 7. BLOQUE 5 — Horizontes siguientes

| Fase | Contenido | Nota |
|---|---|---|
| **M7 Calificaciones** | El módulo `m7_calificaciones` está **apagado**; el menú ya anuncia «pendiente de construir» | El libro de calificaciones del aula **sí** funciona (es de M6) |
| **M7 Asistencia — validación física** | Cámara `mobile_scanner`: capa nativa y UI Dart hechas | **Bloqueado**: no hay JDK ≥ 17 en el equipo, y en `flutter test` no hay cámara |
| **HACER (D17)** | Exportación de la planilla al sistema HACER | Falta **sólo la lista de campos**; las reglas de formato ya están implementadas y cubiertas por 10 casos E2E |
| **SMTP propio** | Hoy `mailer_autoconfirm = true`, así que el registro no envía correo | **Si algún día se apaga esa bandera, el registro se cae.** Arreglarlo de verdad necesita un dominio propio verificado en Resend — **bloqueado en el usuario** |

---

## 8. Cómo verificar cualquier cambio (comandos exactos)

```bash
# --- Esquema y migraciones (contra la nube) ---
export SUPABASE_ACCESS_TOKEN=$(grep '^SUPABASE_ACCESS_TOKEN=' backend/.env | cut -d= -f2-)
node supabase/apply-migrations.mjs --check          # libro mayor: pendientes y deriva
node supabase/verificar-esquema.mjs                 # inspecciona el catálogo

# --- Backend ---
npm --prefix backend run verify                     # tipos + pruebas

# --- Dart (el toolchain nativo NO arranca en este equipo) ---
node devops/analizar-dart.mjs .                     # TIPOS, 207 archivos
C:/Users/Loro/develop/flutter/bin/cache/dart-sdk/bin/dart.exe pub get --offline

# --- E2E (arnés local, paridad con CI) ---
cd e2e && CI=true NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost" \
  npx playwright test --reporter=list --output=/c/tmp/pw-out-$(date +%s)
```

**El listón del verificador es el del CI, y son los TRES niveles.** Hubo un
verificador que filtraba las `info` —con un comentario que afirmaba, falso, que
«las infos no lo tumban»— y daba «sin errores ni avisos» con el CI rojo.
`flutter analyze` **sí** falla por `info`. Un verificador que da verde mientras el
CI da rojo **es peor que no tenerlo**.

---

## 9. Preguntas abiertas para el arquitecto que retome esto

1. **¿El bloqueante del §3.2 es `describe.serial`, `beforeAll`, o el orden entre
   casos?** El bisectado de tres corridas lo nombra. **Es lo primero que hay que
   hacer**, porque bloquea el cierre del Bloque 1.
2. **¿La pantalla de servidor local del §4 existió?** Si existió, recuperar su
   contrato antes de rediseñarla.
3. **¿Cómo se restaura el estado de la demo tras un ciclo E2E que publica?** Se
   eligió la Opción A (tarea propia), pero las tareas se acumulan.
4. **¿La cuenta del autor debe tener matrícula?** (§5.3)
5. **¿Se acepta el oráculo de existencia del login con cédula a largo plazo?**
   (§5.1) Hoy está aceptado y documentado; conviene revisarlo con la mirada de un
   arquitecto de seguridad.

---

## 10. Glosario de artefactos citados

| Artefacto | Qué es |
|---|---|
| `devops/analizar-dart.mjs` | Verificador de **tipos** de Dart sin `dart.exe` |
| `supabase/apply-migrations.mjs` | Aplica/verifica migraciones contra la nube (`--check`, `--confirmar`, `--adoptar`) |
| `supabase/sembrar-datos.mjs` | Siembra la demo. Idempotente. `--limpiar` **no es incondicional** (§5.2) |
| `supabase/verificar-esquema.mjs` | Inspecciona el catálogo real |
| `e2e/src/pages/FlutterApp.ts` | Capa de acceso al árbol semántico de CanvasKit |
| `e2e/src/pages/AulaVirtualPage.ts` | Page Object del aula (M6) |
| `ESTADO_DEL_SISTEMA.md` | **Documento vivo del estado.** Gana el código; §13 cubre el E2E |
| `HANDOVER.md` | Registro histórico, **inmutable hacia atrás** |

## ACTUALIZACIÓN DE EJECUCIÓN — 2026-10-08 (P-02)

P-02 de Performance queda **VERIFICADO LOCAL/CERRADO**: se midieron consultas Supabase reales y se sustituyó select(*) de SupabaseService.miFicha() por una proyección explícita de los campos consumidos por AspiranteModel, incluida datos_planilla y programs(name). No se declara reducción de bytes en el dataset actual: la ficha sigue en 1,348 B; el beneficio es evitar crecimiento silencioso futuro.

Regresión focalizada posterior: **85/85 PASS — 76.25 s**.

El repositorio conserva deliberadamente su estado sin commit/push nuevo. No se realizó limpieza agresiva de cambios históricos ni artefactos no rastreados. Los tres probes temporales de esta sesión fueron eliminados.

Para continuidad de agentes AI, el contrato operativo está ahora en **MEMORY.md**, **docs/AI_AGENT_OPERATING_PROTOCOL.md** y **AUTONOMOUS_AGENT_MASTER_PROMPT.md**. Estos documentos son obligatorios para retomar el trabajo con contexto limitado.

**Fase sigue siendo PERFORMANCE.** Próximo discriminador: medir cargas reales por rol y las rutas Mis Aulas, Aula Virtual, Inscripciones/catálogo y cPanel. P-01 de caché sigue abierto hasta despliegue real en Cloudflare Pages y verificación HEAD.


---

## CONTRATO DE EJECUCIÓN AUTÓNOMA AI — 2026-10-08

Se establece como política de ejecución del proyecto que los agentes AI con acceso autorizado al repositorio deben trabajar de forma continua hasta cerrar todos los hitos aplicables.

Documentos normativos:
- `docs/AI_AGENT_OPERATING_PROTOCOL.md`
- `AUTONOMOUS_AGENT_MASTER_PROMPT.md`

La autonomía permite:
- inspección;
- implementación;
- pruebas;
- creación de datos/credenciales E2E temporales legítimas;
- corrección de bugs;
- optimización;
- despliegue cuando exista autorización/credencial disponible;
- documentación;
- regresión;
- continuación automática al siguiente hito.

La autonomía NO permite:
- saltarse MFA/CAPTCHA;
- desactivar RLS;
- exponer secretos;
- destruir datos reales sin autorización;
- realizar acciones irreversibles sin autorización;
- inventar credenciales de terceros;
- afirmar evidencia que no existe.

Únicamente H1/H2/H3/H4 pueden requerir intervención humana, según el protocolo.

El objetivo del plan sigue siendo el cierre total:
**Performance → Cloudflare → Responsive → UI/UX → Animaciones/3D → Android → Regresión → Producción → Documentación final.**

