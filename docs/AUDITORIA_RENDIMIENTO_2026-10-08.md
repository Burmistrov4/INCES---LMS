# Auditoría de rendimiento — INCES LMS

> Estado vivo de la fase Performance. Registra mediciones y decisiones, no intenciones.

**Fecha de corte:** 2026-10-08 00:56–01:00 (-04:00)
**Fase:** Performance — EN CURSO
**Regla:** medir → cambio mínimo → volver a medir → regresión.

## 1. Baseline funcional

- Aula Virtual E2E real: 7/7 PASS.
- Batería Flutter focalizada posterior a entregaId: 84/84 PASS, 29.55 s.
- Backend npm run verify: 658/658 PASS.
- Producción Pages: HTTP 200.
- API Render: HTTP 200 después de cold start; repetición inmediata ~1.32 s según plan de cierre.
- CORS Pages → API: 204 y origen exacto.
- Build release local: build/web-final, 39 archivos, ~41.43 MiB en disco.

## 2. Composición real del bundle

| Extensión | Archivos | Tamaño |
|---|---:|---:|
| .wasm | 6 | 27.50 MiB |
| .symbols | 6 | 8.18 MiB |
| .js | 10 | 4.01 MiB |
| otros | 17 | ~1.74 MiB |
| TOTAL | 39 | ~41.43 MiB |

Artefactos principales: main.dart.js 3.57 MiB; canvaskit.wasm 6.947 MiB; skwasm.wasm 3.427 MiB; chromium/canvaskit.wasm 5.177 MiB.

**Conclusión:** el mayor coste del bundle está en CanvasKit/WASM. No se debe atacar eliminando funcionalidad ni cambiando renderer sin A/B.

## 3. Producción: compresión y caché

HEAD real contra producción confirmó Brotli para main.dart.js, CanvasKit JS/WASM y flutter_bootstrap.js.

Hallazgo P-01: producción estaba respondiendo con:
public, max-age=0, must-revalidate

Eso obliga al navegador a revalidar los estáticos en cada visita.

### Cambio preparado

Se añadió web/_headers con:
- HTML, raíz y flutter_bootstrap.js: 5 min + revalidación.
- main.dart.js: 1 h + revalidación.
- flutter.js, CanvasKit, assets, iconos y favicon: 7 días.

No se marca P-01 cerrado hasta reconstruir, desplegar y verificar HEAD real.

## 4. Consultas Flutter

### Verde / razonable

- AulaVirtualDashboardScreen consume un gateway único.
- PanelMisAulas hace una lectura de /api/v1/mi-horario al montar; actualizar es explícito.
- Los tres dashboards cargan system_modules una vez mediante CargaDeModulos; no se detectó polling automático.
- cPanel de módulos usa Future.wait para módulos + auditoría y limita auditoría a 50.
- Auditoría de accesos tiene paginación/límite.
- Perfil propio usa columnas explícitas y maybeSingle.

### Amarillo / candidato P-02

supabase_service.dart mantiene lecturas amplias:
- porCedula(): select amplio, una ficha.
- todos(): devuelve todos los aspirantes sin límite.
- porId(): select amplio, una ficha.
- miFicha(): select amplio con relación programs(name).
- crear()/actualizar(): select amplio para devolver fila.
- modulos()/settings(): select completo, pero catálogos pequeños.

**No cambiar AspiranteModel a columnas parciales a ciegas.** Primero medir payload y revisar consumidores. todos() es prioritario si alimenta una lista administrativa.

## 5. Siguiente discriminador P-02

1. Identificar consumidores de obtenerTodos().
2. Medir filas y payload real.
3. Si es lista administrativa, paginar server-side y pedir columnas mínimas.
4. Mantener contratos de porCedula/porId/miFicha hasta tener lista segura de campos.
5. Ejecutar batería Flutter + backend/E2E relacionada.

## 6. Renderer

No cambiar renderer todavía. La evidencia demuestra peso CanvasKit/WASM y arranque funcional; no demuestra que otro renderer sea mejor para este proyecto.

Una futura A/B debe comparar:
- tiempo hasta flutter-view;
- primer contenido útil;
- errores de consola;
- C1 Aula Virtual;
- interacción semántica de pestañas;
- tamaño comprimido.

## 7. No tocar todavía

- F1 Resend/password recovery: DEFERIDA.
- Responsive: después de Performance.
- UI/UX: después de Responsive.
- 3D/animaciones: después de UI/UX y sólo con presupuesto.
- Android: al final.
- No borrar tareas E2E acumuladas con SQL destructivo.

## 8. Criterio de salida

Performance sólo se cierra con:
1. baseline antes/después;
2. caché de producción verificada;
3. consultas/payloads calientes auditados;
4. cargas iniciales de roles principales medidas;
5. al menos una mejora cuantificable sin regresión;
6. regresión funcional verde después del último cambio;
7. decisión documentada sobre renderer.

**Última acción:** auditoría estática + preparación de web/_headers. P-01 sigue abierto.

### P-01.1 Preparación del artefacto Pages

Flutter build web no copia automáticamente web/_headers al output: build/web-final-perf quedó con 21 archivos y HEADERS_PRESENT=NO.

Para no depender de memoria manual se creó devops/preparar-cloudflare-pages.mjs. Uso:

node devops/preparar-cloudflare-pages.mjs build/web

La prueba sobre build/web-final-perf copió _headers correctamente. El comando de despliegue de Cloudflare Pages deberá ejecutar el build y después este preparador, o equivalente.

### P-00.1 Payload comprimido observado en producción

Tres mediciones por recurso con curl + Accept-Encoding: br:

| Recurso | HTTP | Tamaño transferido observado | Tiempo observado |
|---|---:|---:|---:|
| / | 200 | 728 B | 0.230–0.308 s |
| flutter_bootstrap.js | 200 | 5,178 B | 0.263–0.347 s |
| main.dart.js | 200 | 1,075,185 B | 0.688–1.067 s |
| canvaskit/canvaskit.wasm | 200 | ~2.863–2.868 MB | 0.865–1.059 s |

Estas cifras son una medición desde la máquina de trabajo hacia Cloudflare; no equivalen a una métrica de usuario final ni a TTFB puro. Sirven como baseline reproducible para comparar después del cambio de caché.


### Verificación post-cambio

- Primer intento de flutter test falló antes de ejecutar pruebas por una variable de entorno ausente: PROGRAMFILES(X86). No fue fallo de código.
- Segundo intento, definiendo PROGRAMFILES(X86) sólo para el proceso, terminó **84/84 PASS**, exit 0, **27.75 s**.
- El build release con el cambio de headers terminó correctamente: flutter build web --release --dart-define-from-file=.env.json --output build/web-final-perf, **116.2 s**, exit 0.
- Wasm dry-run del build: PASS; sólo warning informativo que recomienda probar --wasm. No se cambia renderer en esta fase.
## P-02 — Consultas calientes y payloads — 2026-10-08

### Evidencia real Supabase

| Consulta | Filas | Bytes | Tiempo medido |
|---|---:|---:|---:|
| aspirantes select=* admin | 27 | 26,859 | 548.10 ms |
| aspirantes proyección mínima | 27 | 5,529 | 221.28 ms |
| profiles mínima | 63 | 9,008 | 180.15 ms |
| programs activos | 6 | 478 | 210.48 ms |
| system_modules | 11 | 3,627 | 430.99 ms |
| system_settings admin | 11 | 2,950 | 215.98 ms |
| audit limit 50 | 50 | 43,292 | 245.07 ms |

La consulta AspiranteGateway.todos() no tiene consumidores en lib/; por tanto NO se convirtió en una refactorización innecesaria.

### Ruta del aprendiz

Con sesión E2E real, aspirantes del usuario devolvió 1 fila. La medición de miFicha con relación devolvió 1,348 B.

Después de la corrección a proyección explícita: 1,348 B.

La comparación inmediata de tiempos fue variable (STAR 572.13 ms vs explícita 249.19 ms), por lo que NO se atribuye esa diferencia al cambio. La mejora es estructural: una columna futura en aspirantes no se añadirá silenciosamente al payload de cada apertura del dashboard.

### Cambio aplicado

SupabaseService.miFicha() ahora proyecta exactamente los campos consumidos por AspiranteModel, incluida datos_planilla, y conserva programs(name).

### Regresión

Suite focalizada después del cambio:

**85/85 PASS — 76.25 s — exit 0.**

Incluye onboarding, libro de calificaciones, Aula Virtual, perfil y dashboards relacionados.

### Decisión P-02

**VERIFICADO LOCAL / CERRADO como intervención estructural de payload.**

No se afirma una reducción de bytes en el dataset actual porque no la hubo: los 1,348 B son equivalentes. El beneficio es control de crecimiento del contrato.

### Próximo discriminador de Performance

Auditar las cargas reales de:
1. dashboard por rol;
2. Mis Aulas;
3. Aula Virtual;
4. Inscripciones/catálogo;
5. cPanel administrativo.
Buscar requests duplicados, secuencialidad evitable, payloads grandes y rutas backend que devuelvan más datos de los necesarios.


---

## CONTRATO AI v2 — IMPACTO SOBRE PERFORMANCE

La auditoría de rendimiento queda integrada en el protocolo de ejecución autónoma.

El agente futuro debe continuar desde el siguiente discriminador real y no reiniciar auditorías ya cerradas:

**Dashboard por rol → Mis Aulas → Aula Virtual → Inscripciones/catálogo → cPanel.**

Para cada ruta debe obtener baseline real, localizar requests/consultas/payloads innecesarios, aplicar cambios pequeños, medir después y ejecutar regresión.

P-02 permanece cerrado como intervención estructural de payload. P-01 permanece abierto hasta despliegue real y verificación de headers/cache en producción.

Responsive no debe comenzar hasta que Performance satisfaga su criterio de salida documentado.



---

## Medición de seguimiento — producción Cloudflare Pages — 2026-10-09

**Origen:** máquina de trabajo → `https://inces-lms.pages.dev`. GETs de solo lectura con `Accept-Encoding: br`; no son métricas RUM ni representan todas las redes/dispositivos. Tiempos en segundos, muestra pequeña, no usar como p95.

### Recursos comprimidos y tiempos observados

| Recurso | HTTP | Transferencia Brotli observada | TTFB aproximado (s) | Tiempo total (s) |
|---|---:|---:|---:|---:|
| `/` | 200 | 946 B | 0.272 | 0.309 |
| `/flutter_bootstrap.js` | 200 | 5,181 B | 0.247 | 0.287 |
| `/main.dart.js` | 200 | 1,072,212 B | 0.588 | 0.961 |
| `/canvaskit/canvaskit.wasm` | 200 | 2,867,428 B | 0.742 | 1.201 |

El HTML tuvo una primera solicitud de ~1.39 s y las dos siguientes ~0.275 s en otra tanda, compatible con variación de conexión/caché. No se infiere una mejora causal a partir de esas muestras.

### Política de caché verificada en vivo

- `/`: `public, max-age=300, must-revalidate`.
- `/flutter_bootstrap.js`: `public, max-age=300, must-revalidate`.
- `/main.dart.js`: `public, max-age=3600, must-revalidate`.
- `/canvaskit/canvaskit.wasm`: `public, max-age=604800`.
- Los cuatro recursos respondieron `Content-Encoding: br` con petición explícita `Accept-Encoding: br`.

Esto confirma que la política de caché y Brotli de `web/_headers` está activa en producción. **No basta para cerrar la sincronización del release:** `build/web/main.dart.js` local (3,773,439 B, generado el 2026-10-09 12:39 -04:00) contiene el marcador de ruta `restablecer-codigo`; el bundle descargado de producción (3,729,033 B) no lo contiene. Por tanto, la producción aún no refleja todo el código local sin commit. No se hizo commit, push ni despliegue.

### Siguiente discriminador de G3

1. Medir con Playwright, en el bundle local fresco y sin mutaciones, login y navegación por rol: administrador/cPanel, docente/Mis Aulas y aprendiz/Mis Aulas/Aula Virtual.
2. Registrar duración de cada transición, requests por ruta, solicitudes repetidas, estado HTTP y payload/transferencia cuando esté disponible.
3. Repetir muestras suficientes para distinguir cold start de navegación caliente; reportar mediana y rango, no p95 con una muestra pequeña.
4. Auditar el mayor coste observado y sólo entonces decidir un cambio de código.
5. Mantener responsive bloqueado hasta completar G3. El despliegue de los cambios locales requiere autorización explícita.


## G3 — Primer baseline E2E por rol y cambio mínimo — 2026-10-09

### Instrumento reproducible

Se añadió `e2e/tests/performance_baseline.spec.ts`, de sólo lectura y excluido de la regresión normal. Ejecución opt-in:

```powershell
$env:E2E_MEDIR_PERFORMANCE='1'
npx playwright test tests/performance_baseline.spec.ts
```

Mide arranque Flutter, login hasta señal del rol, transición a la vista y tiempos aproximados de respuestas API. Sólo registra método, ruta sin query, estado y duración; no registra credenciales, cuerpos ni tokens. Usa el bundle local y el backend de prueba configurado.

### Baseline previo (muestras de la primera corrida)

| Medición | Administrador | Docente | Aprendiz |
|---|---:|---:|---:|
| Arranque Flutter | 5.74 s | 3.57 s | 2.72 s |
| Login hasta panel | 8.64 s | 7.21 s | 6.90 s |
| Transición medida | 2.77 s (Usuarios y Roles) | 2.24 s (Mis Aulas/Aula) | 2.47 s (Mis Aulas/Aula) |

El tiempo del arranque es variable y sensible al estado frío/caliente del navegador. No se usa una sola muestra para afirmar percentiles.

### Hallazgo en código

`GET /api/v1/mi-horario` leía el período vigente, después las clases y, para docente, las guardias en serie. Las lecturas de clases y guardias son independientes una vez conocido el período y usan el mismo cliente/RLS. La serie sumaba latencias de red que no tenían dependencia de datos.

### Cambio mínimo

En `backend/src/infra/repos-supabase.ts`, `CuadranteSupabase.miHorario()` conserva la lectura del período y la ruta de estudiante; para docente, ejecuta en `Promise.all` las consultas independientes de clases y guardias. No cambian filtros, columnas, permisos, RLS ni respuesta.

### Verificación posterior

- `npm run verify`: **32 archivos / 675 pruebas PASS**, incluyendo typecheck y ESLint.
- `npm run build`: exit 0.
- Baseline opt-in por rol: **3/3 PASS**.
- Tres muestras posteriores de `GET /api/v1/mi-horario` para docente: **1.856 s, 1.433 s y 1.153 s** (medición de respuesta del servidor; mediana ≈ **1.433 s**).
- Muestras previas observadas en servidor: **1.996 s y 2.396 s** (mediana ≈ **2.196 s**). La mediana posterior es ~**35 % menor** en esta muestra pequeña; esto es evidencia preliminar, no una garantía ni una prueba causal robusta frente a la variabilidad de red/BD.
- Las lecturas de Aula Virtual siguieron respondiendo 200. Sin cambio de datos ni operaciones mutantes.
- **Outlier de 31.7 s explicado y corregido en el arnés E2E:** `AulaVirtualPage.irAMisAulas()` esperaba hasta 30 s una respuesta que podía haberse recibido durante el login, aunque la tarjeta ya estaba montada. Se añadió el parámetro opcional `seccion` y una señal alternativa por tarjeta real; la prueba de Aula Virtual ahora pasa la sección esperada. Esto corrige tiempo perdido de automatización, no una demora del producto.
- Corrida docente repetida 3 veces después de separar las etapas: `solicitudMiHorario` **792 ms, 44 ms, 43 ms**; `renderTarjetaAula` **379 ms, 33 ms, 29 ms**; `abrirAulaYRespuesta` **797 ms, 790 ms, 762 ms**; `montajeAula` **85 ms, 78 ms, 74 ms**. No reapareció el outlier.
- `GET /api/v1/mi-horario` docente en las tres últimas muestras: **1.894 s, 1.330 s, 1.061 s** (mediana ≈ **1.330 s**). Frente a las dos muestras previas de 1.996 s y 2.396 s (mediana ≈ 2.196 s), la mediana posterior es ~**39 % menor**; muestra pequeña y ambiente variable, evidencia preliminar.
- `tests/aula_virtual.spec.ts`: **3/3 PASS**, 18.9 s total, después de pasar `SECCION` al helper.

### Estado de G3

**EN CURSO, no cerrado.** El baseline por rol y el primer cambio están validados; el falso outlier de automatización está corregido. Falta repetir muestras de administrador/aprendiz, medir Inscripciones/catálogo y cPanel, revisar el doble viaje secuencial del listado administrativo y fijar gates de aceptación antes de iniciar Responsive.


## G3 — Revalidación local de baseline por rol — 2026-10-09 14:44–14:46 (-04:00)

**Bundle:** `build/web/main.dart.js` local fresco (3,773,739 bytes). **Backend:** local `:3001`, iniciado por Playwright. **Prueba:** `E2E_MEDIR_PERFORMANCE=1 npx playwright test tests/performance_baseline.spec.ts` → **3/3 PASS**; segunda tanda `--repeat-each=2` → **6/6 PASS**, exit 0. Total: 3 muestras por rol. Son mediciones de navegador local contra el backend conectado al proyecto configurado; no son métricas RUM ni un p95.

### Medianas observadas (3 muestras; tiempos en ms)

| Etapa | Admin | Docente | Aprendiz |
|---|---:|---:|---:|
| Arranque Flutter | 2,218 | 2,399 | 2,650 |
| Login hasta panel | 5,846 | 5,301 | 5,913 |
| Admin: Usuarios y Roles | 2,274 | — | — |
| Solicitud Mi Horario | — | 931 | 1,246 |
| Abrir aula + respuesta | — | 772 | 811 |
| Montaje aula | — | 92 | 75 |
| Trabajo de Clase | — | 385 | — |

### Rutas API observadas

| Ruta | Tiempo aproximado hasta respuesta (muestras) | Estado |
|---|---:|---:|
| `GET /api/v1/admin/usuarios` | 1,002–1,660 ms | 200 |
| `GET /api/v1/mi-horario` | 1,071–2,208 ms | 200 |
| `GET /api/v1/aula/secciones/:id/tablon` | 581–696 ms | 200 |
| `GET /api/v1/aula/secciones/:id/trabajo` | 626–827 ms | 200 |
| `GET /api/v1/aula/mis-entregas` | ~881 ms en la muestra observada | 200 |
| `POST /auth/v1/token` | 403–732 ms | 200 |

### Interpretación y siguiente discriminador

- La carga inicial del motor Flutter/CanvasKit varía entre muestras; no atribuir esa variación a un cambio de código.
- Los candidatos medibles más claros son `GET /api/v1/mi-horario` (1.07–2.21 s), `GET /api/v1/admin/usuarios` (1.00–1.66 s) y las dos lecturas de aula que ocurren en paralelo durante la apertura. Las cifras incluyen latencia observada desde el navegador y no identifican por sí solas el coste SQL.
- **No se cambió código como resultado de estas mediciones.** Antes de optimizar, instrumentar por separado duración del handler, consultas/repositorio, tamaño de respuesta y cold/warm; revisar además si tablon/trabajo duplican trabajo o compiten por conexión. No eliminar datos ni modificar contratos por inferencia.
- Esta tanda cubre tres roles, pero no cPanel completo, Inscripciones/catálogo ni payload comprimido de las respuestas API. G3 sigue **EN CURSO**; responsive continúa bloqueado hasta tener una mejora cuantificable y regresión verde.
- La suite fue de sólo lectura. No se ejecutó el ciclo mutante ni se modificaron datos de aula.


## G3 — Causa raíz del coste de las rutas lentas y cambios mínimos — 2026-10-09 (sesión 2)

### Instrumento (medición separada, no una sola cifra)

`C:/tmp/medir-rutas.mjs` · `medir-control.mjs` · `medir-cpanel.mjs` · `medir-foco.mjs`. Cada uno mide
(a) el **total de la ruta** contra el backend local y (b) **cada consulta PostgREST por separado**,
contra el mismo proyecto y con el **mismo JWT de rol**, para que la RLS y las columnas sean
equivalentes. Mediana de 5–7 muestras **+1 de calentamiento** (así el cold start no contamina).
Sólo registran método, ruta sin query, estado, ms y bytes: nunca credenciales, tokens ni cuerpos.

### Causa raíz medida: dos viajes de red en serie en CADA petición autenticada

`/api/v1/yo` y `/api/v1/modulos` **no ejecutan ninguna consulta propia** (leen módulos de caché), así
que su tiempo es el **coste fijo** del hook de autenticación. Medido:

| Componente | Mediana |
|---|---:|
| `GET /auth/v1/user` (GoTrue, verificar el token) | **239 ms** |
| `GET /rest/v1/profiles` (leer perfil y rol) | **216 ms** |
| **`GET /api/v1/yo`** (hook, 0 consultas propias) | **421 ms** |

Los dos viajes iban **en serie** aunque la dependencia era aparente: el perfil se lee por el `sub`,
y el `sub` ya viaja en el token. A eso se sumaba, **por cada consulta adicional de la ruta**, otro
viaje de ~170–320 ms. Resultado: ninguna ruta autenticada bajaba de ~420 ms, y las que encadenaban
2–4 consultas llegaban a 1,4 s.

**No hay `SUPABASE_JWT_SECRET` en `backend/.env`**, así que verificar el JWT en local (que eliminaría
el viaje a GoTrue) **no es posible hoy**: requiere una credencial que sólo el propietario puede dar.

### Cambios aplicados (mínimos, sin tocar contratos ni RLS)

1. **`backend/src/http/plugins/autenticacion.ts`** — verificación del token y lectura del perfil **en
   paralelo** (`Promise.allSettled`). El `sub` se lee sin verificar **sólo para arrancar la lectura**;
   el resultado **se acepta únicamente si coincide con la identidad verificada** y, si no, se relee
   por el id de confianza. La consulta del perfil va firmada con el propio token, así que PostgREST
   valida la firma y aplica RLS. Un fallo de la verificación **se propaga (500)**, como antes; un
   token inválido sigue dejando la petición sin usuario (401).
2. **`PerfilesSupabase.listar`** (`admin/usuarios`) — recuento y página **en paralelo**. El `range()`
   deja de recortarse contra `total`; PostgREST sólo responde 416 si el **inicio** del rango queda
   más allá del final, y ese caso sigue devolviendo página vacía + total.
3. **`InscripcionesSupabase.detallar`** — las tres lecturas independientes (secciones, cola de
   espera, estudiantes) **en paralelo**; `resolverNombres` ya paralelizaba. Beneficia a tres rutas.
4. **`InscripcionesSupabase.listarOcupacionCon`** — recuento y página **en paralelo** (mismo criterio
   que el punto 2).

### Antes / después (mismas operaciones, mediana de 5 muestras)

| Ruta | Antes | Después | Δ |
|---|---:|---:|---:|
| `GET /api/v1/mi-horario` (docente) | 1.120 ms | **757 ms** | −363 ms (−32 %) |
| `GET /api/v1/mi-horario` (estudiante) | 874 ms | **613 ms** | −261 ms (−30 %) |
| `GET /api/v1/admin/usuarios` | 1.462 ms | **521 ms** | **−941 ms (−64 %)** |
| `GET /api/v1/aula/secciones/:id/tablon` | 661 ms | **413 ms** | −248 ms (−38 %) |
| `GET /api/v1/aula/secciones/:id/trabajo` | 743 ms | **396 ms** | −347 ms (−47 %) |
| `GET /api/v1/aula/mis-entregas` | 806 ms | **461 ms** | −345 ms (−43 %) |
| `GET /api/v1/admin/secciones/:id/inscripciones` | 1.349 ms | **~900 ms** | −~450 ms (−33 %) |
| `GET /api/v1/admin/ocupacion` | 992 ms | **836 ms** | −156 ms (−16 %) |
| `GET /api/v1/mis-inscripciones` | 1.041 ms | **953 ms** | −88 ms (−9 %) |

Controles de la misma corrida: `/yo` 421 → **275 ms**; `/modulos` 418 → **219 ms** (−35 % y −48 %).
La mejora del hook la hereda **toda** ruta autenticada, porque es el mismo camino de código.

### Casos límite verificados (el contrato no cambió)

`GET /api/v1/admin/usuarios`: página normal 25 filas/total 63 · última página parcial 13 filas ·
**desplazamiento más allá del final → 200 con 0 filas y total 63** (el camino del 416) · filtro por
rol 10/12 · búsqueda `semilla` 1/1 · `limite=200` → **400** (el esquema admite ≤100; comportamiento
previo, no del cambio). Sin token → **401** · token inválido → **401** · token de alumno → **403**.

### Regresión

- `npm run verify` (typecheck + ESLint + Vitest): **675/675, 32 archivos, exit 0**.
- `npm run typecheck`: limpio tras cada cambio.
- Smokes de identidad y E2E: ver el bloque siguiente.

### Siguiente discriminador

`admin/cuadrante` (899 ms), `admin/aulas` (820 ms), `admin/programas` (718 ms) y `admin/acceso`
(718 ms) siguen por encima de 700 ms; conviene medir cuántos viajes encadena cada uno antes de
tocar nada. `ofertas` (855 ms) y `mis-inscripciones` (953 ms) ya se benefician de los cambios 3 y 4.
Responsive sigue bloqueado hasta cerrar G3.


## G3 — Seguimiento con build fresco en puerto aislado — 2026-10-09 (sesión 3)

### Por qué un puerto aislado

`127.0.0.1:3001` sigue sirviendo un `dist` **antiguo**: `GET /api/v1/yo` en 3001 mide **473 ms**
(hook en serie) y en 3002 (build fresco) **243 ms** (hook en paralelo). **La medición del
servidor 3001 no es una medida posterior**: no se usa para «antes/después». 3001 no se detiene.

### Medición (puerto 3002, `npm run build` fresco; 1 calentamiento + 7 muestras)

| Endpoint | Antes (línea base) | Con cambios | Nota |
|---|---:|---:|---|
| `admin/cuadrante` | 1.155 ms | **679 ms** `[646–713]` | −41 %, **estable** |
| `admin/aulas?limite=25` | 897 ms | **552 ms** | −38 % |
| `admin/programas?limite=25` | 1.020 ms | **557 ms** | −45 % |
| `admin/acceso?limite=50` | 961 ms | **572 ms** | −41 % |
| Control `GET /api/v1/yo` | — | **241 ms** `[206–255]` | coste fijo del hook ya paralelo |

**Sobre la variabilidad de cuadrante que preocupaba:** la muestra anterior `[1111, 1167, 621]` era
ruido del entorno (3001 con `dist` viejo + contención), no de la ruta. Con el build fresco y 7
muestras, cuadrante es **estable** (dispersión 67 ms). El desglose lo explica: coste fijo del hook
(**241 ms**) + etapa 1 (periodo∥aulas∥docentes, **~220 ms**) + etapa 2 (clases∥guardias, **~220 ms**)
≈ **680 ms**. Son **3 esperas secuenciales** y la etapa 2 no puede bajar de la 1: las clases filtran
por el período que se lee en la 1. Está **en su suelo** dado el modelo de datos actual.

### ¿El paralelismo es real? Sí, medido.

| Caso | Mediana |
|---|---:|
| 1 consulta | 218 ms |
| 2 en serie | 405 ms |
| **2 en paralelo** | **193 ms** (≈ una) |
| **3 en paralelo** | **223 ms** (≈ una) |

Tres consultas concurrentes cuestan lo mismo que una. Así que paralelizar lecturas independientes
**no reparte el coste, lo elimina**.

### Paginación y consistencia de filtros (44 OK / 0 fallos, puerto 3002)

Script `C:/tmp/validar-paginacion.mjs` sobre `admin/usuarios`, `admin/programas`, `admin/aulas`,
`admin/acceso` (primeros y últimos filtros: tipo, activo, estado, búsqueda). Comprobado:

- el `total` no cambia entre páginas;
- la última página trae exactamente `total − desplazamiento` filas;
- **desplazamiento más allá del final → 200 con 0 filas y el total real** (nunca 500);
- **el invariante de consistencia**: con `limite ≥ total`, las filas son **exactamente** el total
  → recuento y página aplican el mismo filtro;
- el eco devuelve el `limite`/`desplazamiento` pedidos.

### Pruebas de contrato añadidas (no sólo reflejan la implementación)

`backend/test/curriculo-repositorio.test.ts` ahora puede reproducir respuestas por llamada
(`secuencias`) y registrar los filtros por consulta. Añadidas 3 pruebas sobre el listado paginado:
recuento y página aplican los mismos filtros · desplazamiento más allá del total → página vacía ·
si la página responde **416 con el desplazamiento dentro del total**, degrada a página vacía (la
rama del 416, que previo a la paralelización era la única guarda), más un **control negativo** (un
error que no es 416 sí se propaga). Y la ya existente prueba de escaping de la búsqueda.

### Verificación

- `git diff --check`: limpio. · `npm run verify`: **679/679 en 32 archivos, exit 0** ·
  `npm run build`: exit 0. · `npx tsc --noEmit` y `npx eslint` sobre los archivos tocados: limpio.
- Estas pruebas son de sólo lectura. No se ejecutó el ciclo mutante del aula ni se mutaron datos.

### Pendientes para cerrar G3

- **E2E/browser hecho y teardown aislado limpio (2026-10-10):**
  - Se probó la suite completa en tandas divididas y contra el build fresco con backend activo en 3001:
    - `export_csv.spec.ts`: **10/10 passed (20.0s), exit 0**.
    - `admin_cpanel_p0.spec.ts`: **10/10 passed (2.1m), exit 0**.
    - `aula_virtual.spec.ts` + `stepper_inscripcion.spec.ts`: **4/4 passed (33.2s), exit 0**.
  - Total verificado de la suite de regresión: **24/24 passed, exit 0**.
  - Diagnóstico del timeout 124 histórico: ocurría por contención de puertos huérfanos/child process de Node `serve.mjs` bajo el monitor en background acumulando conexiones en TIME_WAIT. Ejecutando de forma controlada o con el servidor backend ya vivo, el proceso Playwright cierra limpiamente con exit code 0 sin timeout de teardown.
- **Medición reproducible de endpoints en build fresco (2026-10-10, puerto 3001, 1 calentamiento + 7 muestras, admin E2E):**
  - `control_yo`: calentamiento 506 ms, muestras `[207, 212, 258, 264, 299, 306, 350]` ms, mediana **264 ms**.
  - `acceso?limite=50`: calentamiento 664 ms, muestras `[599, 614, 619, 668, 820, 833, 919]` ms, mediana **668 ms**.
  - `aulas?limite=25`: calentamiento 575 ms, muestras `[548, 666, 681, 769, 805, 887, 1024]` ms, mediana **769 ms**.
  - `programas?limite=25`: calentamiento 664 ms, muestras `[608, 616, 725, 821, 865, 925, 1071]` ms, mediana **821 ms**.
  - `cuadrante`: calentamiento 2890 ms, muestras `[866, 908, 1027, 1043, 1131, 1179, 1226]` ms, mediana **1043 ms** (rango 866–1226 ms, 100% respuestas HTTP 200 con payload íntegro).
- Los servidores de prueba han sido debidamente cerrados al terminar la medición (puertos 3001 y 8090 liberados).
- Responsive sigue bloqueado hasta el cierre formal del gate G3 y aprobación para avanzar de fase.

