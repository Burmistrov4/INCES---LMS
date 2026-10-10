# TODO — Auditoría de cierre funcional y UX/UI de INCES-LMS

> **Fecha de levantamiento:** 2026-10-08
> **Fuente primaria:** capturas de evidencia dejadas en el Escritorio + estructura/código real del proyecto + contrato OpenAPI.
> **Regla:** una capacidad existente en backend no se considera cerrada si la UI no permite utilizarla correctamente.
> **Regla de evidencia:** cada ítem debe cerrarse con reproducción, causa raíz, corrección, prueba de regresión y evidencia.

---

## 0. Objetivo de cierre

INCES-LMS debe pasar de "muchas piezas implementadas y algunas pruebas focalizadas" a un **producto demostrablemente completo**:

- ciclo de vida del aprendiz probado de extremo a extremo;
- todos los módulos administrativos recorridos;
- operaciones CRUD/estado/permisos verificadas;
- frontend y backend coherentes;
- errores de carga eliminados;
- estados loading/empty/error/success correctos;
- dashboard terminado;
- Usuarios y Roles realmente operativo;
- landing moderna;
- responsive;
- accesibilidad;
- performance;
- producción verificada;
- regresión integral.

---

# 1. Incidencias evidenciadas en capturas del Escritorio

## P0 — Módulos administrativos que no cargan

Estas capturas constituyen evidencia de que varios módulos no están funcionando correctamente desde la experiencia del usuario:

- [ ] **Auditoría de Accesos**
  - Evidencia: `Auditoria de acceso no carga.png`
  - Reproducir en producción y local.
  - Capturar Network/console y respuesta API.
  - Determinar si falla frontend, endpoint, permisos, RLS, datos o despliegue.
  - Corregir.
  - Probar con admin y usuario sin privilegios.
  - **Cierre:** carga real + filtros/paginación + estados vacíos/error + permisos.

- [ ] **Cuadrante y Horarios**
  - Evidencia: `Cuadrante y Horarios no se pudieron cargar.png`
  - Verificar datos de secciones, docentes, aulas y conflictos.
  - Revisar endpoint y contrato.
  - Validar reglas anti-colisión.
  - Probar creación/edición/consulta si corresponde.
  - **Cierre:** cuadrante funcional con datos reales.

- [ ] **Espacios y Aulas**
  - Evidencia: `Espacios y Aulas no se pudieron carar.png`
  - Revisar listado, estados, capacidad y relaciones.
  - Verificar que los errores de backend no se transformen en listas vacías.
  - **Cierre:** módulo cargando y operable.

- [ ] **Guardias Docentes**
  - Evidencia: `Guardias docentes no se pudo cargar.png`
  - Verificar relación con docentes, aulas/horarios y permisos.
  - Revisar si el módulo depende de datos inexistentes.
  - **Cierre:** carga + consulta + operaciones disponibles.

- [ ] **Inscripciones y Cupos**
  - Evidencia: `Inscripciones y cupones no se pudieron cargar.png`
  - Verificar cola, cupos, inscritos, ofertas y estados.
  - Probar ciclo: aspirante → solicitud → cupo → inscripción/espera.
  - **Cierre:** operación completa y consistente.

- [ ] **Lapsos Académicos**
  - Evidencia: `Lapsos Academicos No se pudieron cargar.png`
  - Revisar listado, vigencia y periodo activo.
  - Verificar coherencia con parámetros y currículo.
  - **Cierre:** administración real del periodo.

- [ ] **Programas Académicos**
  - Evidencia: `Programas academicos no se pudieron cargar.png`
  - Verificar programas, unidades curriculares y relaciones.
  - Revisar si el frontend interpreta correctamente el contrato.
  - **Cierre:** carga + gestión + persistencia.

- [ ] **Secciones**
  - Evidencia: `SEcciones no se pudieron cargar.png`
  - Verificar programa, lapso, docente, cupos y horarios.
  - **Cierre:** listado + gestión + relaciones correctas.

## P1 — Inconsistencias de UX/organización evidenciadas

- [ ] **Dashboard / organización general**
  - Evidencia: `FAlta más organizacion....png`
  - Revisar jerarquía visual, agrupación, espacios, prioridades y navegación.
  - No limitarse a cambiar colores: reorganizar información.

- [ ] **Parámetros**
  - Evidencia: `Parametros funciona, pero hay acaso un historial acumulativo de los periodos de formacion.png`
  - Mantener la funcionalidad actual.
  - Investigar si debe existir historial acumulativo de periodos de formación.
  - No inventar requisito: contrastarlo con modelo, documentación y flujo académico.
  - Si es necesario, diseñar historial real y no solamente un campo sobrescrito.

---

# 2. Usuarios y Roles — IMPLEMENTACIÓN PRIORITARIA

## Estado descubierto

El backend ya dispone de:

- `GET /api/v1/admin/usuarios`
- `PATCH /api/v1/admin/usuarios/{id}/rol`
- `POST /api/v1/admin/usuarios/invitaciones`

El contrato permite filtrar por:

- rol;
- activo/inactivo;
- búsqueda;
- paginación.

Los roles son:

- `admin`
- `docente`
- `estudiante`

El backend ya protege:

- auto-degradación;
- último administrador activo;
- UUID inválido;
- perfil inexistente.

También existe auditoría de cambios administrativos.

## Problema actual

La pantalla llamada:

> **Usuarios y Roles**

renderiza actualmente:

> **CpanelInvitacionesPanel**

y esa pantalla en realidad solamente invita docentes.

Esto es una inconsistencia de producto.

## Implementación

- [ ] Reemplazar la pantalla por un **panel real de Usuarios y Roles**.
- [ ] Mostrar resumen:
  - [ ] usuarios totales;
  - [ ] administradores;
  - [ ] docentes;
  - [ ] estudiantes;
  - [ ] activos/inactivos.
- [ ] Tabla de usuarios:
  - [ ] nombre;
  - [ ] correo;
  - [ ] cédula;
  - [ ] rol;
  - [ ] estado;
  - [ ] acciones.
- [ ] Búsqueda.
- [ ] Filtro por rol.
- [ ] Filtro por estado.
- [ ] Paginación.
- [ ] Cambio de rol.
- [ ] Promoción a administrador.
- [ ] Degradación de administrador cuando las reglas lo permitan.
- [ ] Confirmación explícita para otorgar privilegios administrativos.
- [ ] Mensajes específicos para:
  - [ ] AUTO_DEGRADACION;
  - [ ] ULTIMO_ADMIN;
  - [ ] PERFIL_INEXISTENTE;
  - [ ] permisos;
  - [ ] errores de red.
- [ ] Mantener la invitación de docentes dentro del mismo panel, como acción secundaria claramente identificada.
- [ ] No presentar "Invitar docente" como si fuera toda la gestión de usuarios.
- [ ] Registrar/verificar auditoría.
- [ ] Verificar que el administrador no pueda eliminar la última vía de acceso administrativo.

### Creación/invitación

El backend actual de invitación crea específicamente docentes.

Por seguridad y coherencia, NO convertir la invitación existente en una invitación arbitraria de administrador sin revisar primero el flujo de activación.

Flujo recomendado actual:

`Invitar docente → activar cuenta → usuario aparece → cambiar rol → admin`

Si se desea:

`Invitar administrador directamente`

debe diseñarse como una ampliación explícita del backend, con validación de que únicamente un administrador autorizado puede emitirla y con auditoría.

---

# 3. Auditoría de todos los módulos administrativos

Recorrer uno por uno:

- [ ] Parámetros
- [ ] Auditoría
- [ ] Auditoría de Accesos
- [ ] Usuarios y Roles
- [ ] Programas Académicos
- [ ] Inscripciones y Cupos
- [ ] Campos de Inscripción
- [ ] Secciones
- [ ] Lapsos Académicos
- [ ] Cuadrante y Horarios
- [ ] Espacios y Aulas
- [ ] Guardias Docentes
- [ ] Módulos del Sistema

Para cada uno:

- [ ] carga inicial;
- [ ] loading;
- [ ] datos reales;
- [ ] empty state;
- [ ] error state;
- [ ] crear;
- [ ] editar;
- [ ] desactivar/eliminar si aplica;
- [ ] filtros;
- [ ] búsqueda;
- [ ] paginación;
- [ ] permisos;
- [ ] auditoría;
- [ ] persistencia;
- [ ] regresión;
- [ ] responsive.

---

# 4. Ciclo de vida completo del aprendiz

- [ ] Landing
- [ ] Registro
- [ ] Onboarding
- [ ] Autenticación
- [ ] Perfil
- [ ] Inscripción
- [ ] Campos de inscripción
- [ ] Programa
- [ ] Sección
- [ ] Cupo
- [ ] Cola de espera
- [ ] Confirmación
- [ ] Aula Virtual
- [ ] Clases
- [ ] Materiales
- [ ] Asistencia
- [ ] Evaluaciones
- [ ] Notas
- [ ] Pasantías/prácticas si están habilitadas
- [ ] Egreso
- [ ] Certificado
- [ ] QR/verificación

Cada transición debe tener evidencia de:

`UI → API/DB → estado persistido → siguiente pantalla`

---

# 5. Ciclo Profesor

- [ ] Login
- [ ] Dashboard
- [ ] Secciones propias
- [ ] Horario
- [ ] Aula
- [ ] Materiales
- [ ] Clases
- [ ] Asistencia
- [ ] Evaluaciones
- [ ] Calificación
- [ ] Seguimiento del aprendiz
- [ ] Estados vacíos/error
- [ ] Restricción de acceso a datos ajenos

---

# 6. Dashboard

- [ ] Rediseño completo.
- [ ] Resumen ejecutivo.
- [ ] Métricas útiles.
- [ ] Acciones prioritarias.
- [ ] Actividad reciente.
- [ ] Alertas.
- [ ] Pendientes.
- [ ] Accesos rápidos.
- [ ] Datos diferentes por rol.
- [ ] Sin números inventados.
- [ ] Sin tarjetas repetitivas.
- [ ] Sin espacios muertos.
- [ ] Responsive.

---

# 7. Landing

- [ ] Hero moderno.
- [ ] Propuesta de valor clara.
- [ ] Capacidades.
- [ ] Ciclo del aprendiz.
- [ ] Aula virtual.
- [ ] Gestión administrativa.
- [ ] Beneficios.
- [ ] CTA.
- [ ] Información institucional.
- [ ] Footer.
- [ ] SEO.
- [ ] Accesibilidad.
- [ ] Performance.

Opcional:

- [ ] ilustraciones;
- [ ] imágenes propias/generadas;
- [ ] motion;
- [ ] 3D sutil con fallback.

---

# 8. Responsive

Validar:

- [ ] 375 px
- [ ] 768 px
- [ ] 1024 px
- [ ] 1280 px
- [ ] 1440 px

Especial atención:

- [ ] dashboard;
- [ ] tablas;
- [ ] formularios;
- [ ] sidebar;
- [ ] modales;
- [ ] aula virtual;
- [ ] landing.

---

# 9. Accesibilidad

- [ ] teclado;
- [ ] focus;
- [ ] labels;
- [ ] contraste;
- [ ] mensajes de error;
- [ ] navegación lógica;
- [ ] touch targets;
- [ ] reduced motion;
- [ ] semántica.

---

# 10. Performance

- [ ] no cargar datasets innecesarios;
- [ ] paginar;
- [ ] evitar consultas duplicadas;
- [ ] evitar reconstrucciones innecesarias;
- [ ] imágenes optimizadas;
- [ ] lazy loading;
- [ ] revisar bundle;
- [ ] revisar cold starts;
- [ ] comprobar producción.

---

# 11. Producción

- [ ] Cloudflare Pages HTTP 200.
- [ ] Bundle apunta al backend real.
- [ ] API Render responde.
- [ ] CORS.
- [ ] Supabase.
- [ ] Auth.
- [ ] Assets.
- [ ] Rutas.
- [ ] Network/console sin errores críticos.
- [ ] Login real.
- [ ] módulos administrativos reales.

---

# 12. Regla de cierre

Un ítem solamente puede pasar a CLOSED cuando existe:

1. causa raíz conocida;
2. implementación/corrección;
3. prueba;
4. regresión;
5. evidencia;
6. documentación actualizada.

**No cerrar por "parece funcionar".**

**No cerrar porque el backend responde 200 si la UI no puede utilizar la funcionalidad.**

**No cerrar un módulo que devuelve una pantalla vacía sin determinar si realmente está vacío o si falló la carga.**

---

# 13. Orden recomendado de ejecución

### P0 — Recuperar funcionalidad

1. [ ] Auditoría de Accesos
2. [ ] Cuadrante y Horarios
3. [ ] Espacios y Aulas
4. [ ] Guardias Docentes
5. [ ] Inscripciones y Cupos
6. [ ] Lapsos Académicos
7. [ ] Programas Académicos
8. [ ] Secciones

### P1 — Administración

9. [ ] Usuarios y Roles
10. [ ] Auditoría completa
11. [ ] Parámetros + historial si el requisito se confirma

### P1 — E2E

12. [ ] Ciclo completo aprendiz
13. [ ] Ciclo profesor
14. [ ] Ciclo administrador

### P2 — Producto

15. [ ] Dashboard
16. [ ] UI/UX global
17. [ ] Landing
18. [ ] Responsive
19. [ ] Accesibilidad
20. [ ] Performance

### P3 — Pulido

21. [ ] Motion
22. [ ] 3D/ilustraciones si aportan valor
23. [ ] producción
24. [ ] regresión final
25. [ ] documentación final

---

## Estado inicial histórico — 2026-10-08 (superado parcialmente)

El siguiente estado describe el punto de partida del TODO y **no es el estado actual**. Los checkpoints cronológicos posteriores prevalecen. Al 2026-10-09, la matriz UI de Usuarios y Roles + ocho módulos P0 está cerrada por E2E y la regresión seleccionada está 24/24; el ciclo de vida integral, Flutter completo, correo y producción siguen abiertos.

**P0 en el punto de partida:** ABIERTO  
**P1 en el punto de partida:** ABIERTO  
**E2E en el punto de partida:** ABIERTO  
**Dashboard/UX en el punto de partida:** ABIERTO  
**Producción en el punto de partida:** ABIERTO hasta completar regresión integral

## Progreso de la sesión 2026-10-08

- [x] Levantamiento del TODO persistido.
- [x] Confirmado en OpenAPI que existe `GET /admin/usuarios`, `PATCH /admin/usuarios/:id/rol` y `POST /admin/usuarios` para invitación de docente.
- [x] Confirmado que el backend protege `AUTO_DEGRADACION`, `ULTIMO_ADMIN`, `PERFIL_INEXISTENTE` y exige Administrador Maestro para cambiar roles.
- [x] Creado modelo Flutter `UsuarioAdmin` y repositorio paginado.
- [x] Sustituido el panel engañoso de invitaciones por un panel real de **Usuarios y Roles**.
- [x] Añadidos búsqueda, filtros, paginación, resumen por rol/estado y cambio de rol.
- [x] Añadida confirmación específica al promover a administrador.
- [x] Conservada la invitación de docentes como sección secundaria del mismo panel.
- [x] `dart analyze` del alcance modificado: **0 errores**, sólo 6 recomendaciones de lint.
- [ ] Ejecutar E2E real con sesión de Administrador Maestro.
- [ ] Verificar en navegador la respuesta real de `/admin/usuarios` y la promoción a administrador.
- [ ] Corregir los módulos administrativos que aparecen sin carga en las capturas.
- [ ] Ejecutar regresión integral del ciclo de vida.

**Próxima acción inmediata:**
1. validar Usuarios y Roles en navegador con la sesión real;
2. corregir los módulos evidenciados como no cargables;
3. ejecutar regresión;
4. continuar automáticamente con el siguiente bloque.



---

# CHECKPOINT — 2026-10-08

## Usuarios y Roles

- [x] Se creó `lib/models/usuario_admin.dart`.
- [x] Se creó `lib/repositories/usuario_admin_repository.dart`.
- [x] Se creó `lib/screens/admin/cpanel_usuarios_roles_panel.dart`.
- [x] `admin_dashboard.dart` ahora muestra el panel real de Usuarios y Roles.
- [x] Listado paginado.
- [x] Búsqueda.
- [x] Filtro por rol.
- [x] Filtro por estado.
- [x] Cambio de rol.
- [x] Confirmación adicional para otorgar `admin`.
- [x] Invitación de docente integrada como acción secundaria.
- [x] Se conserva la protección de último administrador en backend.
- [ ] Prueba E2E real de promoción de un usuario a administrador.
- [ ] Verificación visual del panel en producción.

## Verificación técnica

- [x] `dart format` procesó los nuevos archivos sin error de parseo.
- [ ] `flutter analyze` no completó en esta sesión: el proceso quedó sin progreso después de `Analyzing 4 items...`.
- [ ] `flutter build web --release --no-pub` no completó: el proceso quedó sin progreso y el `build/web/main.dart.js` no cambió, por lo que NO se marca PASS.

## Bloqueo técnico abierto

El build/analyzer de Flutter quedó aparentemente atascado en el entorno local durante esta sesión. No se debe confundir con un error confirmado del código nuevo. Debe reintentarse con diagnóstico del proceso Flutter/Dart antes de publicar.

## Próximo orden

1. Resolver/verificar el bloqueo del build/analyzer.
2. Ejecutar E2E de Usuarios y Roles.
3. Corregir los módulos evidenciados como no cargables.
4. Continuar con la matriz integral del ciclo de vida.


---

# CHECKPOINT — 2026-10-08 · CONTINUACIÓN

## Usuarios y Roles / administración

- [x] Backend administrativo: **61/61 pruebas PASS** (`admin.test.ts` + `reglas-admin.test.ts`).
- [x] Cambio de rol: promoción a docente, promoción a admin, degradación segura y validación UUID.
- [x] Protección `AUTO_DEGRADACION` y `ULTIMO_ADMIN` verificada.
- [x] Listado de usuarios: filtros, búsqueda, paginación y totales verificados.
- [x] Auditoría administrativa y auditoría de accesos verificadas en backend.
- [ ] Falta ejecutar la interacción UI autenticada de promoción en navegador.

## Catálogo de módulos — inconsistencia encontrada y corregida localmente

- [x] La nube real tenía **11 filas**: `m6_asistencia` (placeholder histórico) + `m7_asistencia` (implementación real).
- [x] Se comprobó el origen: `m6_asistencia` nació en `202609120002`; la asistencia funcional usa `m7_asistencia` desde `202609260002`.
- [x] Se comprobó que API, dashboards y rutas actuales consumen `m7_asistencia`.
- [x] Creada migración `supabase/migrations/202610080001_remove_legacy_m6_asistencia.sql` para retirar el placeholder.
- [x] Actualizado el icono del cPanel para `m7_asistencia` y retirado el mapping obsoleto de `m6_asistencia`.
- [x] Smoke actualizado para el catálogo funcional de 10 módulos.
- [x] Validación local de migraciones: **530/530 aserciones PASS, 0 fallos**.
- [ ] Aplicar `202610080001` en Supabase real.

## Humo contra Supabase real

- [x] API local levantada en `127.0.0.1:3001` conectada a Supabase real.
- [x] Sesión real de Administrador Maestro obtenida mediante Supabase.
- [x] Salud, identidad, autenticación, permisos, auto-degradación, CORS y cabeceras: PASS.
- [x] Resultado previo: **24/25 PASS**.
- [x] Única falla: catálogo de 11 filas por `m6_asistencia` legado + `m7_asistencia` real.
- [ ] Repetir humo contra nube después de aplicar `202610080001`; el resultado esperado es **25/25**.

## Build

- [x] `flutter build web --release --dart-define-from-file=dart-define.example.json` completado.
- [x] Artefactos Web principales generados.
- [x] `dart analyze` del alcance modificado: 0 errores; sólo recomendaciones de lint.

## Bloqueos externos

- [ ] `SUPABASE_ACCESS_TOKEN` falta en el entorno; impide aplicar DDL mediante `supabase/apply-migrations.mjs`.
- [ ] La sesión actual de Desktop Commander no expone control de navegador gráfico autenticado; se continuará por Playwright/E2E desde terminal cuando el harness permita hacerlo.
- [x] Ambos bloqueos están registrados en `docs/AI_AGENT_BLOCKERS.md` y no detienen tareas independientes.

## Próximo orden ejecutable

1. Playwright/E2E de Usuarios y Roles con sesión real, si el harness disponible lo permite.
2. Auditoría/reparación de los módulos P0 de las capturas: Auditoría de Accesos, Cuadrante y Horarios, Espacios y Aulas, Guardias Docentes, Inscripciones y Cupos, Lapsos Académicos, Programas Académicos y Secciones.
3. Regresión backend + Flutter.
4. Dashboard/UI/UX.
5. Landing.
6. Responsive/accesibilidad/performance.
7. Aplicación de migración pendiente y humo 25/25.
8. Regresión final y producción.
---

# CHECKPOINT — 2026-10-08 · P0 / E2E

- [x] Regresión backend completa: **31 test files / 658 tests PASS**.
- [x] Migraciones locales: **530/530 aserciones PASS**.
- [x] Build Web release: PASS.
- [x] Usuarios y Roles implementado y analizado: backend 61/61 PASS.
- [ ] Usuarios y Roles UI E2E: pendiente por bloqueo Chromium/Playwright.
- [ ] Los 8 módulos P0 no se marcarán cerrados hasta una ejecución E2E real.
- [x] Harness E2E corregido para usar `../build/web` en local, no el bundle histórico `../build/e2e-web`.
- [ ] Resolver bloqueo de Chromium/Playwright antes de volver a ejecutar la matriz UI.
- [ ] Aplicar `202610080001_remove_legacy_m6_asistencia.sql` en Supabase real; falta `SUPABASE_ACCESS_TOKEN`.
- [ ] Repetir smoke real después de migración: objetivo 25/25.

### Hallazgo P0 confirmado

`m6_asistencia` es un placeholder histórico y `m7_asistencia` es la implementación real. La nube actual contiene ambos (11); el repositorio corregido deja 10 mediante `202610080001`. No se elimina ni se renombra una migración histórica ya aplicada: la corrección es una migración nueva e idempotente.

### Criterio de cierre P0

No se cerrará ningún módulo sólo porque el backend responda. Debe existir evidencia de navegación UI real, carga inicial, datos/empty state, error state y operación principal cuando aplique.

---

# CHECKPOINT — 2026-10-08 · Reanudación, Supabase y dirección premium

## Registro de contexto y evidencia

- [x] Se comprobó que `backend/.env` contiene `SUPABASE_ACCESS_TOKEN` y `SUPABASE_URL`; los valores no se imprimieron ni se copiaron a documentación.
- [x] La Management API autenticó el token y confirmó el proyecto `twdppwnxlnmxkiejbrei` en estado `ACTIVE_HEALTHY`; el ref coincide con `SUPABASE_URL`.
- [x] `node supabase/apply-migrations.mjs --check`: 44 migraciones en disco, 42 registradas, 2 pendientes, 0 derivas.
- [x] Se revisó el alcance de ambas pendientes: `202610070001_remove_semilla_soldadura_basica.sql` cambia el nombre exacto de `SEM-SOL-CL` de `Soldadura Básica [SEMILLA]` a `Soldadura Básica`; `202610080001_remove_legacy_m6_asistencia.sql` elimina el placeholder `m6_asistencia` sólo si existe `m7_asistencia`.
- [x] Precondiciones de sólo lectura: `SEM-SOL-CL` existe, está activo y es `CURSO_LIBRE`; `m7_asistencia` está habilitado y `m6_asistencia` deshabilitado.
- [ ] Aplicación remota pendiente: Desktop Commander bloqueó por su control de seguridad la invocación del aplicador. No se intentó eludir la restricción ni se aplicó ninguna migración en esta sesión.
- [ ] Tras resolver el bloqueo: aplicar mediante el flujo autorizado, comprobar que el libro mayor registra las dos versiones, que `system_modules` queda en 10 filas y repetir el smoke contra Supabase (objetivo histórico: 25/25).

## Dirección de producto premium

- [x] Creado `docs/INCES_PREMIUM_PRODUCT_DESIGN_SYSTEM.md` con investigación de referencia, identidad INCES propia, landing, dashboards por rol, accesibilidad WCAG 2.2 AA como objetivo, rendimiento, reglas de movimiento y puertas de aceptación.
- [x] Inspeccionada la técnica de la landing TechLoan: DOM real con CSS 3D (sin WebGL), interpolación con `requestAnimationFrame`, interacción de puntero, arrastre con pointer capture, reposo automático y respeto de `prefers-reduced-motion`.
- [ ] Portar sólo el patrón técnico de 3D ligero a INCES, sin copiar branding ni contenido de TechLoan.
- [ ] Antes de cambiar landing/dashboard, auditar archivos reales, módulos funcionales, activos oficiales de marca y la secuencia de puertas del plan maestro.
- [ ] Implementar, probar por rol y viewport, verificar accesibilidad y medir rendimiento antes/después.

## Bloqueos y estado real

- [ ] Usuarios y Roles E2E y los ocho módulos P0 siguen sin cierre visual: Chromium/Playwright continúa bloqueándose antes del primer caso.
- [ ] Flutter test runner completo sigue pendiente de resolver su variable de entorno Windows; las pruebas focalizadas ya registradas no sustituyen la regresión integral.
- [x] Las dos migraciones pendientes se aplicaron al proyecto Supabase remoto el 2026-10-09 y el `--check` posterior confirmó 0 pendientes y 0 con deriva. La UI premium sigue sin implementarse y no se afirma conformidad WCAG.


### Seguimiento de la continuación

- [x] Actualizado `supabase/verificar-esquema.mjs` para que el criterio final espere 10 módulos y no exija el placeholder retirado `m6_asistencia`.
- [x] `node --check supabase/verificar-esquema.mjs` y `node --check supabase/apply-migrations.mjs`: sin errores de sintaxis.
- [x] `git diff --check`: sin errores de whitespace; Git mostró sólo avisos de conversión LF/CRLF.
- [ ] No se hizo commit ni push. `git status --short` muestra archivos E2E de diagnóstico, scripts auxiliares y `backend/server-e2.err` sin seguimiento; no eliminarlos ni incorporarlos sin inspección individual.


### Revalidación local adicional — 2026-10-08

- [x] Ejecutado `node supabase/tests/validate.mjs` completo después de ajustar el catálogo esperado.
- [x] El proceso terminó con código de salida 0; las migraciones históricas y las dos nuevas se aplicaron al entorno de prueba local (shim/PGlite) sin errores, y el verificador confirmó 10 módulos sembrados y los estados esperados.
- [x] Esta prueba valida el código SQL en el entorno local aislado; **no** significa que las migraciones estén aplicadas en el proyecto Supabase remoto.


### Corrección de migración remota — 2026-10-09
- [x] Diagnóstico del fallo remoto: `202610070001_remove_semilla_soldadura_basica.sql` empezaba con BOM UTF-8 (`EF BB BF`), que Supabase interpretaba como un carácter SQL inválido (`syntax error at or near "﻿"`, SQLSTATE `42601`).
- [x] Retirado únicamente el BOM inicial del archivo; se conservó el contenido SQL restante.
- [x] Escaneo de `supabase/migrations/*.sql`: no quedan archivos SQL con BOM UTF-8.
- [x] `node supabase/tests/validate.mjs`: 530 aserciones pasadas, 0 fallidas; ambas migraciones nuevas pasan en el entorno local aislado.
- [x] `git diff --check` terminó sin errores; sólo mostró avisos de normalización LF/CRLF.
- [x] Aplicación remota completada: ambas migraciones se registraron correctamente y el `node .\supabase\apply-migrations.mjs --check` posterior confirmó `0 pendiente(s), 0 con deriva` y `Modo --check: no se aplicó nada`.


---

# CHECKPOINT — 2026-10-09 · PROMPT MAESTRO Y ESTADO REMOTO

## Migraciones Supabase

- [x] Se aplicaron en el proyecto remoto las migraciones 202610070001_remove_semilla_soldadura_basica.sql y 202610080001_remove_legacy_m6_asistencia.sql.
- [x] El aplicador verificó 10 módulos y la existencia de teacher_invitations y auth_logs.
- [x] La comprobación remota posterior confirmó 44 registradas, 0 pendientes y 0 con deriva. --check no aplicó cambios.
- [x] Actualizados ESTADO_DEL_SISTEMA.md y docs/AI_AGENT_BLOCKERS.md para cerrar el bloqueo de migraciones.

## Continuidad entre agentes

- [x] Creado PROMPT_MAESTRO_CICLO_VIDA_COMPLETO_AGENTE_IA.md como prompt universal para Antigravity/Gemini y otros agentes.
- [x] AGENT_START_HERE.md actualizado para incluir el nuevo prompt y el prompt operativo específico de Antigravity.
- [x] El nuevo prompt define el ciclo completo de aprendiz, docente y administrador; gates; seguridad; ingeniería inversa legítima; pruebas con evidencia; documentación canónica; checkpoints; protección Git; criterios de cierre y reanudación.
- [x] docs/AI_AGENT_BLOCKERS.md reescrito para retirar como abierto el bloqueo resuelto de Supabase y conservar sólo bloqueos vigentes.
- [ ] Validar UI autenticada de Usuarios y Roles y módulos P0; Chromium/Playwright sigue siendo un riesgo técnico sin cerrar.
- [ ] Resolver el entorno de Flutter test runner y ejecutar la regresión integral.
- [ ] Cerrar la entrega real de correo tras corregir la configuración/credencial externa de Resend.
- [ ] Continuar el ciclo E2E completo de aprendiz/docente/administrador, performance, responsive, accesibilidad, producción y auditoría final según los gates.

## Nota de interpretación histórica

Los checkpoints anteriores que muestran las migraciones 202610070001 y 202610080001 como pendientes describen el estado de ese momento. Quedan supersedidos por la evidencia del 2026-10-09: aplicación remota completada y verificación posterior con 0 pendientes y 0 con deriva. No se realizó commit ni push.

---

# CHECKPOINT — 2026-10-09 · P0 / E2E — CAUSA RAÍZ Y CIERRE VISUAL

**Fase/gate:** G1 (funcionalidad P0) — desbloqueo del cierre visual de Usuarios y Roles y los ocho módulos P0.

## Estado anterior → posterior
- **Antes:** «Chromium/Playwright se bloquea antes del primer caso»; el cierre visual de los P0 y de Usuarios y Roles estaba abierto.
- **Después:** **10/10 pruebas E2E en verde** contra la nube real, con peticiones reales al backend. Bloqueo **cerrado**.

## Hallazgo / causa raíz (confianza: alta, medida)
El bundle local `build/web` estaba compilado con **`dart-define.example.json`** (plantilla), no con `.env.json`. El artefacto contiene `("<clave-publicable>","https://<project-ref>.supabase.co")`. La app arranca y pinta el login, pero al pulsar «Ingresar al sistema» el SDK construye una URL inválida y **lanza antes de emitir ninguna petición**: ni error visible, ni nada en la pestaña de red. `AppConfig.validate()` no lo detecta (sólo comprueba que no esté vacío).

## Discriminadores ejecutados (cada uno descartó una hipótesis)
1. Credenciales `E2E_ADMIN_*` contra `POST /auth/v1/token` → **200** (no son las credenciales).
2. `pulsar` (dispatchEvent) y `pulsarReal` (click real) → fallan igual (no es el gesto).
3. Control «Mostrar contraseña» → cambia el `type` del input (los clicks **sí** llegan a Flutter).
4. Volcado del árbol tras pulsar → SnackBar «No pudimos completar la operación» (el click **sí** dispara el login; falla la autenticación).
5. Red completa durante el login → **cero** peticiones nuevas (el SDK falla antes de la red).
6. `fetch` directo del navegador a Supabase → **200** (no es proxy ni CORS).
7. `grep` del artefacto → los marcadores `<project-ref>` / `<clave-publicable>` (causa raíz).

## Archivos modificados
- `e2e/playwright.config.ts` — **guardia**: si el bundle trae los marcadores de la plantilla, falla de inmediato con la causa escrita (control negativo y positivo verificados).
- `e2e/tests/admin_cpanel_p0.spec.ts` — el buscador se comprueba con `campo('Buscar usuario').count()` y no con `cuantos('Buscar usuario')`, que da 0 porque un `textbox` no es control con rol ni hoja de texto.
- Bundle corregido en `C:/tmp/web-fixed` (copia parcheada de `build/web`; script `C:/tmp/parchear-bundle.mjs`). **`build/web` es un artefacto ignorado por git**: no se toca el original ni se versiona.

## Comandos y resultados
- `node supabase/apply-migrations.mjs --check` → 44 registradas, **0 pendientes, 0 con deriva**.
- `CI=true E2E_WEB_DIR=C:/tmp/web-fixed npx playwright test tests/admin_cpanel_p0.spec.ts` → **10 ok, 0 fallos** (login + los ocho módulos P0 + Usuarios y Roles). Backend: `/api/v1/admin/{ocupacion,periodos,programas,secciones,usuarios}` → 200.
- `npx playwright test --list` con el bundle de la plantilla → **falla con el mensaje de la guardia**; con el bundle corregido → 46 pruebas en 16 archivos.

## Evidencia real
Panel de Usuarios y Roles medido en el árbol semántico: `USUARIOS Y ROLES — Gestiona usuarios, roles y acceso administrativo.` · `63 Usuarios` · `7 Administradores` · `4 Docentes` · `14 Estudiantes` · `textbox "Buscar usuario"` · tabla `Usuario | Correo | Rol | Estado | Acciones` con botones `Cambiar rol` · paginación `Página 1 de 3`. Llamada `GET /api/v1/admin/usuarios?limite=25&desplazamiento=0` → **200**.

## Riesgos / regresiones / decisiones
- No se hizo commit ni push.
- El build web local sigue bloqueado por el `231`; la vía vigente para un bundle fresco es el artefacto `web-bundle` de `e2e.yml`.
- El arnés local es sensible a **servidores estáticos obsoletos** de corridas anteriores (`reuseExistingServer: true` sin `CI`): un servidor zombi murió a mitad de una corrida y produjo `ERR_CONNECTION_REFUSED`. Se recomienda correr con `CI=true` en local, que fuerza servidores nuevos.

## Siguiente discriminador
Ejecutar la **suite E2E completa** (`CI=true`, bundle corregido) para confirmar que la guardia y el ajuste del spec no rompen `export_csv`, `aula_virtual`, `aula_virtual_ciclo` ni `stepper_inscripcion`. Criterio de cierre: sin fallos nuevos y sin `flaky` no explicados.

---

# CHECKPOINT — 2026-10-09 (2) · AUTENTICACIÓN SIN RESEND

**Fase/gate:** G1 (funcionalidad) + G2 (seguridad) — cierre de la decisión innegociable: recuperar cuentas y activar docentes **sin depender de un proveedor de correo**.

## Estado anterior → posterior
- **Antes:** el restablecimiento de contraseña sólo existía por correo (Resend, HTTP 401 ⇒ no llegaba nada). Las invitaciones se creaban pero no se podían revocar ni renovar, y el consumo del token no era atómico. No había límite de intentos.
- **Después:** recorrido interno completo, con migraciones aplicadas, 17 pruebas nuevas en el backend, 6 en Dart y verificación de permisos reales en la nube.

## Migraciones aplicadas (aditivas, con libro mayor)
- `202610090001_invitaciones_revocacion.sql` — `revoked_at`, `revoked_by` en `teacher_invitations` + índice parcial de pendientes.
- `202610090002_recuperacion_interna.sql` — tabla `password_resets` (RLS, sólo lectura para admin, sin política de escritura) + función `public.revocar_sesiones_usuario(uuid)` **security definer**.
- Aplicadas con `apply-migrations.mjs`: **46 versiones registradas, 0 pendientes, 0 con deriva**. Verificado en la nube que `EXECUTE` de la función queda **revocado de `anon` y `authenticated`** y concedido sólo a `service_role`.

## Implementación
- **Invitación:** consumo **atómico** (`update … where is_used = false and revoked_at is null returning id`) reclamado **antes** de crear la cuenta, con liberación si la creación falla; revocar (no borra la fila); renovar (revoca la anterior y emite otra); listado con el estado **resuelto por el dominio** (revocada > usada > caducada > válida).
- **Recuperación interna:** el administrador emite un **código de 12 caracteres** (~59 bits, alfabeto sin 0/O/1/I/L) que se devuelve **una sola vez**; en la base vive sólo su SHA-256; caduca en 30 minutos; un solo uso; emitir uno nuevo anula los anteriores; el canje fija la contraseña contra GoTrue y **cierra todas las sesiones** del usuario. El administrador nunca ve ni elige la contraseña.
- **Seguridad:** respuestas genéricas (un código inexistente, caducado, revocado o usado responden lo mismo: `404 CODIGO_INVALIDO`); **límite de intentos** por IP (20/15 min) con 429 `DEMASIADOS_INTENTOS`; rutas de emisión con `exigirAdmin`; auditoría en `auth_logs` sin registrar contraseñas.
- **UI:** pantalla pública de canje; el login ya **no promete un correo que no llega** (explica el trámite interno y ofrece canjear); el cPanel emite el código y lo muestra una vez, lista las invitaciones con estado real y permite anular y renovar.

## Comandos y resultados
- `node supabase/tests/validate.mjs` → **546 aserciones, 0 fallos** (16 nuevas: permisos de la función, borrado real de sesiones, revocación de tokens, RLS de `password_resets`).
- `npm run verify` (backend) → typecheck + ESLint + **675 pruebas en 32 archivos, 0 fallos** (658 → 675 = +17).
- `node devops/analizar-dart.mjs` → **218 archivos, sin errores, avisos ni infos**.
- Nube: `apply-migrations.mjs` → 2 aplicadas; consulta de verificación → columnas, tabla con RLS y permisos de la función correctos; `system_modules` sigue en 10.

## Riesgos / decisiones
- **Se aplicaron migraciones a la nube** (aditivas: columnas nulables, tabla nueva y función; sin pérdida de datos y reversibles). No hubo commit, push ni despliegue.
- La **verificación de identidad es un procedimiento institucional** (presencial, con cédula) que el sistema no puede sustituir. Queda documentado como decisión del INCES; el software no finge un autoservicio que no puede garantizar.
- El correo externo queda como notificación **opcional**; su HTTP 401 ya no bloquea ninguna funcionalidad.

## Siguiente discriminador
E2E real del ciclo completo con **cuenta desechable**: emitir código → canjear → iniciar sesión con la contraseña nueva → rechazar la antigua → comprobar que las sesiones previas quedaron cerradas. Requiere bundle fresco (el build local sigue bloqueado por el `231`) y una cuenta de prueba aislada.


---

# CHECKPOINT — 2026-10-09 · Regresión E2E revalidada

## Evidencia ejecutada en esta continuación

- [x] Bundle de prueba servido desde `C:/tmp/web-fixed`, copia corregida del bundle local; `build/web` original no se modificó.
- [x] Playwright ejecutado con `CI=true` para forzar servidores nuevos y evitar reutilizar procesos estáticos obsoletos.
- [x] Suites ejecutadas: `admin_cpanel_p0.spec.ts`, `export_csv.spec.ts`, `aula_virtual.spec.ts`, `stepper_inscripcion.spec.ts`.
- [x] Resultado JSON de Playwright: **24 esperadas, 0 omitidas, 0 inesperadas, 0 flaky**, duración aproximada **136,4 s**; proceso finalizó con código 0.
- [x] El inicio de sesión administrativo y los ocho módulos P0 quedan confirmados en esta corrida, junto con exportación CSV, Aula Virtual del aprendiz y Stepper de inscripción.
- [x] `git diff --check`: sin errores; únicamente advertencias de normalización LF/CRLF.

## Límites explícitos de esta evidencia

- [ ] No se ejecutó `aula_virtual_ciclo.spec.ts`: crea/publica una tarea, entrega y califica con nota 18, y devuelve la entrega usando la sección/cuentas configuradas. No repetir contra datos compartidos hasta disponer de sección y cuentas desechables o un mecanismo de limpieza verificable.
- [ ] No se ejecutó la suite Flutter completa: sigue bloqueada por el fallo del entorno Windows `CreateFile failed 231`, no por una variable ausente.
- [ ] El correo de invitación/recuperación sigue sin cierre de entrega real mientras Resend devuelva HTTP 401.
- [ ] La configuración reproducible del build local sigue pendiente; la corrida utilizó la copia de bundle corregida y no afirma que `flutter build web` funcione en este entorno.
- [ ] No se hizo commit, push ni despliegue.

## Próxima acción

Preparar un ciclo E2E docente-aprendiz seguro: inspeccionar si existen fixtures/cuentas y sección de pruebas aisladas, y si el sistema permite borrar la tarea/entrega creada sin afectar datos institucionales. Si no hay aislamiento ni limpieza demostrable, mantener el ciclo como bloqueado por seguridad de datos y avanzar en pruebas no mutantes, contratos, autorización y documentación. Después continuar con la matriz funcional integral y las puertas de rendimiento, responsive, accesibilidad y producción.


---

# CHECKPOINT — 2026-10-09 · Regresión backend y análisis Dart

- [x] `npm run verify` en `backend/`: `tsc --noEmit` PASS, ESLint PASS, Vitest **31 archivos / 658 tests PASS**, código de salida 0.
- [x] `node devops/analizar-dart.mjs`: **213 archivos analizados, 0 errores, 0 avisos y 0 infos**, código de salida 0.
- [x] El analizador alternativo identificó seis infos de lint en `lib/screens/admin/cpanel_usuarios_roles_panel.dart`: llaves en `if`, seguridad de `mounted` tras `await`, interpolación de cadenas y API `initialValue` en `DropdownButtonFormField`. Se corrigieron sin cambiar la regla de negocio de gestión de roles.
- [x] `dart format lib/screens/admin/cpanel_usuarios_roles_panel.dart`: `Formatted 1 file (0 changed)`.
- [ ] La corrida E2E 24/24 utilizó el bundle disponible antes de esta última limpieza de lint. Como no se pudo recompilar Flutter localmente, **los cambios recientes de lint/`initialValue` no han sido comprobados visualmente en un bundle nuevo**; deben entrar en el próximo build de CI y repetirse la prueba de Usuarios y Roles.
- [ ] Esto no sustituye `flutter test` ni `flutter build web`: ambos siguen pendientes de validación mediante CI por el bloqueo local `CreateFile failed 231`.
- [ ] No se hizo commit ni push.


---

# CHECKPOINT — 2026-10-09 · Protección de la suite E2E por defecto

- [x] Añadido `testIgnore` en `e2e/playwright.config.ts` para excluir siempre las sondas diagnósticas `_*.spec.ts`.
- [x] `aula_virtual_ciclo.spec.ts` queda fuera de la regresión normal porque publica tarea, crea entregas y escribe una nota persistente. Sólo puede listarse/ejecutarse si se opta explícitamente con `E2E_PERMITIR_CICLO_MUTANTE=1`.
- [x] Documentada la protección en `e2e/README.md`, incluyendo el aviso de que el opt-in no crea aislamiento ni limpia datos por sí solo.
- [x] `npx playwright test --list` con el bundle corregido y sin opt-in: **24 tests en 4 archivos** (`admin_cpanel_p0`, `aula_virtual`, `export_csv`, `stepper_inscripcion`).
- [x] Con `E2E_PERMITIR_CICLO_MUTANTE=1`, `npx playwright test --list tests/aula_virtual_ciclo.spec.ts` descubre **7 tests**; sólo se verificó la lista, **no se ejecutó el ciclo mutante**.
- [ ] La regresión 24/24 fue ejecutada antes de este ajuste de `testIgnore`; después del cambio se validó descubrimiento de pruebas, no se repitieron las 24 ejecuciones.


---

# CHECKPOINT — 2026-10-09 · Preparación de handoff y megaprompt operativo

## Objetivo
Dejar el trabajo pendiente organizado en los documentos canónicos y preparar una instrucción ejecutable para el siguiente agente, sin depender del historial de chat.

## Cambios documentales
- [x] Creado `PROMPT_MAESTRO_CONTINUACION_CIERRE_INTEGRAL_2026-10-09.md`: misión, lectura obligatoria, baseline histórico a revalidar, prioridades, estrategia segura del ciclo E2E mutante, build/CI, Resend, matriz funcional, gates, seguridad, documentación, autonomía y formato de handoff.
- [x] Actualizado `AGENT_START_HERE.md`: incorpora el nuevo megaprompt en la lectura obligatoria y lo enlaza desde la siguiente secuencia de trabajo.
- [x] Actualizado el encabezado vigente de `ESTADO_DEL_SISTEMA.md`: remite al megaprompt y mantiene explícito el bloqueo de datos del ciclo mutante.
- [x] Revisión final de estado y existencia de los cinco documentos: completada. `git diff --check` terminó con código 0; sólo emitió advertencias conocidas de normalización LF/CRLF, sin errores.

## Orden de trabajo que debe respetar el siguiente agente
1. Revalidar raíz, rama, estado Git, diffs existentes, procesos y resultados previos.
2. Auditar `aula_virtual_ciclo.spec.ts`, fixtures, cuentas/sección, entorno de CI y rutas de persistencia/eliminación; **no ejecutarlo contra datos compartidos**.
3. Implementar o demostrar aislamiento y limpieza verificable; si no es posible, dejarlo bloqueado y seguir con pruebas no mutantes.
4. Conseguir un build Flutter/bundle fresco ligado al código evaluado por un camino permitido, sin hacer commit/push para activar CI sin autorización.
5. Continuar la matriz funcional y de seguridad por rol; tratar Resend 401 como bloqueo externo de entrega real.
6. Cumplir gates de performance → responsive → UX/accesibilidad → Android si está en alcance → regresión → producción → auditoría final.
7. Actualizar estado, checklist, bloqueadores y handoff con evidencia exacta.

## Límites de esta sesión
Este checkpoint registra documentación e instrucciones, no afirma que se haya cerrado un nuevo flujo funcional, ejecutado el ciclo mutante, generado un build Flutter nuevo, validado Resend ni desplegado. No se hizo commit, push ni despliegue.

## Criterio de cierre del checkpoint
Megaprompt creado y enlazado desde el punto de entrada; las comprobaciones finales de diff y consistencia documental deben completarse antes de dar por terminada esta tarea.


---

# CHECKPOINT — 2026-10-09 · Cambio de decisión: recuperación interna de contraseña

## Decisión del usuario
Se prefiere un sistema interno de recuperación de contraseña en INCES-LMS, en vez de depender de Resend. Esta decisión cambia la prioridad: la recuperación de cuentas no debe quedar bloqueada por HTTP 401 del proveedor de correo.

## Documentos actualizados
- [x] `PROMPT_MAESTRO_CONTINUACION_CIERRE_INTEGRAL_2026-10-09.md`: sustituida la sección centrada en resolver Resend por un frente prioritario de recuperación interna con investigación, diseño de amenazas, seguridad, pruebas y criterios de cierre.
- [x] `PROMPT_MAESTRO_CICLO_VIDA_COMPLETO_AGENTE_IA.md`: el ciclo de vida de aprendiz ahora exige recuperación interna independiente de Resend, correo y SMS; el correo para invitaciones queda separado.
- [x] `AGENT_START_HERE.md`: la siguiente secuencia prioriza diseñar e implementar el flujo interno; Resend queda como pendiente independiente para invitaciones/notificaciones externas.
- [x] `ESTADO_DEL_SISTEMA.md`: la fotografía vigente distingue recuperación interna pendiente y correo externo pendiente.
- [x] `docs/AI_AGENT_BLOCKERS.md`: se separaron dos tareas: recuperación interna de contraseña (prioridad de producto) y entrega externa de correo para invitaciones/notificaciones.

## Criterios de diseño y seguridad que el agente debe respetar
1. Inspeccionar primero proveedor de identidad, Auth, endpoints, roles/RLS y auditoría; no crear un sistema paralelo de contraseñas.
2. Preferir un flujo asistido por personal autorizado si no existe verificación de identidad autoservicio segura.
3. Evaluar códigos de recuperación aleatorios, de alta entropía, de un solo uso y almacenados sólo como hash únicamente si existe un canal interno seguro para entregarlos/validarlos.
4. No utilizar preguntas de seguridad débiles, contraseñas fijas, datos personales fáciles de conocer ni mecanismos que revelen si existe una cuenta.
5. Aplicar rate limiting, caducidad/revocación, protección anti-replay, autorización en backend, auditoría mínima, forzar nueva contraseña y revocar sesiones cuando el proveedor lo permita.
6. No exponer service-role keys ni credenciales privilegiadas en Flutter, cliente, logs o documentación.
7. Probar el flujo completo, incluida la contraseña nueva, rechazo de la antigua, intentos inválidos/repetidos, permisos y sesiones.
8. Mantener Resend HTTP 401 como bloqueo separado de invitaciones/notificaciones que todavía requieran correo externo.

## Alcance de este checkpoint
Sólo se actualizó documentación y prompts. **No se implementó todavía** el mecanismo de recuperación ni se modificaron Auth, backend, base de datos o UI. La arquitectura debe verificarse contra el código real antes de elegir la implementación. No se hizo commit, push ni despliegue.

## Siguiente acción inequívoca
El siguiente agente debe inspeccionar el flujo actual de autenticación y presentar/implementar una propuesta compatible con el proveedor de identidad real, priorizando el mecanismo interno asistido y sólo habilitando autoservicio si puede verificar identidad de forma segura. Registrar el contrato, amenazas, cambios y pruebas en los documentos canónicos.


---

# CHECKPOINT — 2026-10-09 · Invitación docente y recuperación sin dependencia de Resend

## Decisión de producto
La invitación/activación de docentes y la recuperación de contraseñas deben ser flujos internos de primera clase. Ninguna de las dos operaciones puede depender de Resend, SMTP, email ni SMS. Resend HTTP 401 queda separado como incidencia de notificaciones externas opcionales.

## Documentos actualizados en este checkpoint
- [x] `PROMPT_MAESTRO_CONTINUACION_CIERRE_INTEGRAL_2026-10-09.md`: ampliado el frente de identidad con especificación de invitación/activación interna, tokens de un solo uso, estados honestos y E2E; correo opcional separado.
- [x] `PROMPT_MAESTRO_CICLO_VIDA_COMPLETO_AGENTE_IA.md`: requisito docente actualizado para que la invitación/activación funcione sin correo.
- [x] `AGENT_START_HERE.md`: orden de trabajo actualizado para cerrar recuperación e invitación internas.
- [x] `ESTADO_DEL_SISTEMA.md`: decisión vigente y pendientes actualizados.
- [x] `docs/AI_AGENT_BLOCKERS.md`: bloqueadores separados para recuperación, invitación/activación interna y correo opcional.
- [x] `PLAN_MAESTRO.md`: prioridad de identidad y gates actualizados.
- [x] `PLAN_CIERRE_100_FUNCIONAL_2026.md`: añadido aviso de decisión vigente que supersede los apartados históricos orientados a reparar Resend como requisito principal.
- [x] `PROMPT_ANTIGRAVITY_AUTONOMOUS_CLOSURE.md`: añadida instrucción específica que prevalece sobre referencias históricas a Resend.

## Criterios técnicos no negociables
1. Auditar el flujo existente, `teacher_invitations`, proveedor de identidad, RLS, rutas, permisos y auditoría antes de diseñar cambios.
2. Crear invitaciones sólo desde backend confiable y por personal autorizado; generar token criptográficamente aleatorio, guardar sólo su hash, mostrarlo una sola vez, expirar/revocar y consumir atómicamente.
3. El docente establece su propia contraseña; nunca enviar/mostrar una contraseña compartida ni permitir autoasignación de roles.
4. La entrega debe identificarse como pendiente de entrega institucional cuando sólo se ha creado la invitación; no fingir correo enviado/entregado.
5. Recuperación: verificar identidad por procedimiento institucional; si no existe autoservicio seguro, preferir flujo asistido y documentar el canal aprobado. No usar preguntas débiles ni datos personales como secreto.
6. Rate limiting, anti-replay, protección de enumeración, auditoría mínima, sesiones invalidadas cuando sea posible, sin secretos en logs ni service-role en cliente.
7. E2E real y aislado para invitación→activación→contraseña→login, y recuperación→nueva contraseña→login/rechazo de antigua; cubrir tokens inválidos/reutilizados/expirados/revocados, permisos negativos, concurrencia y auditoría.
8. Las decisiones sobre el canal institucional de entrega que requieran aprobación deben registrarse como bloqueo acotado; el agente sigue con tareas independientes.

## Alcance real de este checkpoint
Se actualizaron documentos y prompts; no se afirma que los flujos estén implementados ni que Auth, backend, base de datos o UI hayan cambiado en esta sesión. No se hizo commit, push ni despliegue.

## Siguiente acción
Inspeccionar el código real de Auth/invitaciones y sus contratos; elegir la implementación interna más segura compatible con el proveedor de identidad actual; implementar por cortes pequeños, probar en entorno aislado, documentar y continuar con el siguiente gate.


---

# CHECKPOINT — 2026-10-09 · Revalidación local del cierre de identidad

## Revalidación ejecutada sobre el worktree actual
- [x] `cd backend && npm run verify`: **exit 0**; TypeScript, ESLint y Vitest; **32 archivos / 675 pruebas PASS** (incluye 12 de recuperación y 14 de invitaciones).
- [x] `node supabase/tests/validate.mjs`: **546 aserciones PASS, 0 fallos**, incluidas revocación de sesiones y permisos de la función.
- [x] `git diff --check`: **exit 0**; sólo avisos conocidos de normalización LF/CRLF.
- [x] Inspeccionado `backend/src/infra/correo.ts`: el adaptador Resend devuelve `entregado: false` ante ausencia de clave, respuesta no-OK (incluido 401) o excepción de red; no lanza. La invitación devuelve además el enlace/token al administrador. Por ello el proveedor no es una dependencia de ejecución para el adaptador actual, aunque la UI debe comunicar honestamente que el correo es opcional y la entrega institucional sigue pendiente.

## Bloqueo real para E2E de identidad
El código actual continúa sin commit en el worktree; `HEAD` sigue en `978e52f`. La última corrida GitHub E2E visible (`37930879226`) corresponde a ese mismo SHA y, por tanto, **no contiene estas modificaciones locales**. Descargar su `web-bundle` no sería una prueba del código actual. El build Flutter local continúa bloqueado por `CreateFile failed 231`.

No se hizo commit, push ni despliegue para activar CI. Tampoco se cambió la contraseña de una cuenta real ni se creó una cuenta temporal en la nube: no había una vía E2E reproducible con artefacto fresco e identidad desechable disponible en este corte.

## Próxima acción inequívoca
1. Preparar una estrategia E2E aislada para identidad: cuenta de Auth temporal, perfil mínimo y limpieza verificable, o entorno Supabase de pruebas.
2. Incorporar una prueba real para invitación→activación→login y recuperación→nueva contraseña→login/rechazo de la antigua/sesiones revocadas; nunca usar la cuenta institucional real como sujeto de cambio de contraseña.
3. Obtener un bundle compilado a partir de este código mediante una vía autorizada. Para CI, el código tiene que estar disponible en un commit; no hacer commit/push sin autorización del propietario. Mientras tanto, seguir con revisiones de seguridad y pruebas no destructivas.
4. Actualizar este checkpoint con el resultado de E2E, no con una inferencia basada en pruebas unitarias.

---

# CHECKPOINT — 2026-10-09 (sesión 2) · Build local, `flutter test` e identidad verificada contra el motor real

**Fecha/hora:** 2026-10-09 · **Rama:** `main` · **HEAD de referencia:** `978e52f` (los cambios de esta sesión siguen **sin commit**).

## 1. El bloqueo del toolchain de Flutter no existe en esta sesión (medido)
- `flutter.bat --version` → OK.
- `flutter build web --release --dart-define-from-file=.env.json` → **`√ Built build\web`**, exit 0 (157 s / 116,5 s en dos corridas).
- `flutter test --no-pub` → **974 pruebas, `All tests passed!`, exit 0** (2,5 min).
- El histórico `CreateFile failed 231` era **del sandbox de la sesión anterior**. Se deja de citar como bloqueo.
- **Artefacto verificado:** `build/web/main.dart.js` contiene la URL real, **cero** marcadores de plantilla, `restablecer-codigo` y `mobile_scanner`. Corresponde al código actual, incluido lo no commiteado.

## 2. Defecto real encontrado y corregido
`POST /api/v1/admin/usuarios/:id/restablecer` devolvía **403 PERMISO_DENEGADO** (`contexto: anular códigos previos`) porque escribía `password_resets` con el cliente del llamante, y esa tabla **sólo concede `SELECT` a `authenticated`** (escritura sólo por `service_role`, por diseño).
- **Por qué se escapó:** el arnés de backend devolvía **el mismo objeto** de repositorios para `reposAdmin` y `reposDePeticion`; la escritura «funcionaba» en memoria. Sólo aparecía contra Postgres.
- **Corrección:** la ruta usa `deps.reposAdmin.recuperacion` (la lectura del perfil sigue por RLS) **y** el arnés devuelve una vista del llamante cuyo `recuperacion.emitir` falla a propósito, imitando la RLS. Cualquier regresión futura falla en la prueba, no en la nube.
- Archivos: `backend/src/http/rutas/admin.ts`, `backend/test/support/arnes.ts`.

## 3. Flujos de identidad — evidencia contra el motor real (A y B)
| Instrumento | Resultado | Residuo |
|---|---|---|
| `node supabase/humo-invitaciones.mjs --confirmar` (ampliado con revocar/renovar) | **34 OK / 0 fallos** | 0/0/0 |
| `node supabase/humo-recuperacion.mjs --confirmar` (**nuevo**) | **27 OK / 0 fallos** | 0/0/0 |

Cubre: token de un solo uso, revocar (403 al activar, sin crear cuenta, 409 al revocar dos veces), renovar (la vieja queda revocada y no activa; la nueva sí), listado del panel que no expone el hash; y en recuperación: emisión → huella SHA-256 → emitir otro anula el anterior → canje → la contraseña nueva entra y la vieja no → **el refresh token previo muere** → no reutilizable → código inválido responde igual → auditoría sin secretos. Aislamiento por cuentas `humo-*@ejemplo.invalid` con purga por prefijo.

## 4. Regresión completa (todo verde)
| Comando | Resultado |
|---|---|
| `cd backend && npm run verify` | **675 pruebas / 32 archivos, exit 0** (también con la guardia del arnés) |
| `node supabase/tests/validate.mjs` | **546 aserciones, exit 0** |
| `node devops/analizar-dart.mjs` | **219 archivos, sin errores/avisos/infos** |
| `flutter test --no-pub` | **974 pruebas, exit 0** |
| E2E `CI=true E2E_ARRANCAR_BACKEND=0 E2E_WEB_DIR=../build/web npx playwright test` | **24/24 passed (2,2 min), exit 0** sobre bundle fresco |

## 5. Cambio de producto mínimo
`/restablecer-codigo` queda **registrada** en `lib/main.dart` (además de empujarse desde el login), para que el enlace directo funcione. Reconstruido y revalidado con la suite E2E completa.

## 6. Lo que NO se ejecutó, y por qué
- ~~`e2e/tests/aula_virtual_ciclo.spec.ts`~~ — **SÍ se ejecutó**: **6 passed + 1 flaky (C7), exit 0**, con limpieza verificada. Se creó `supabase/limpiar-ciclo-aula.mjs` (sin `--confirmar` no borra nada; borra sólo las tareas del ciclo dentro de una ventana temporal y comprueba huérfanas). Medido: tareas **78 → 76**, entregas **231 → 225** (línea base exacta), **0 huérfanas**.
  - **Hallazgo de calidad de prueba:** C7 es flaky porque su primera aserción espera `LIBRO DE CALIFICACIONES`, un texto que **no existe en la app**; la satisface la etiqueta del botón «Ver libro de calificaciones», que sólo aparece cuando la tarea tiene entregas. La verificación real del libro es su tercera aserción (la fila del `estudianteId`). Mejora pendiente, no defecto de producto.
- No se ejecutaron las sondas `_*.spec.ts` (diagnóstico) ni la suite E2E contra producción.

## 7. Estado de Git y despliegue
**Sin commit, sin push, sin despliegue.** Migraciones: **46 registradas, 0 pendientes, 0 con deriva** (aplicadas en una sesión anterior). `build/web` y `.env.json` están ignorados por git.

## 8. Próxima acción inequívoca
Sustituir la primera aserción de C7 por una que mida el libro en sí y espere la propagación de la entrega, para eliminar el flaky; después, performance medida por rol y el barrido responsive.

---

# CHECKPOINT — 2026-10-09 (sesión 2) · G3 Rendimiento: causa raíz y cambios mínimos

**Fecha/hora:** 2026-10-09 · **Rama:** `main` · **HEAD de referencia:** `978e52f` (sin commit).
**Documento de detalle:** `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md` (sección «G3 — Causa raíz del coste de las rutas lentas y cambios mínimos»).

## Causa raíz medida
`GET /api/v1/yo` y `/api/v1/modulos` **no ejecutan consultas propias** (leen módulos de caché), así que su tiempo es el **coste fijo** del hook de autenticación: **421 ms**, compuesto por `GET /auth/v1/user` (GoTrue, 239 ms) + `GET /rest/v1/profiles` (216 ms) **en serie**. A eso se sumaba ~170–320 ms **por cada consulta** adicional de la ruta, también encadenada. Ninguna ruta autenticada bajaba de ~420 ms.
**No hay `SUPABASE_JWT_SECRET` en `backend/.env`**, así que verificar el JWT en local (que eliminaría el viaje a GoTrue) requiere una credencial del propietario: **bloqueo acotado**, no una decisión del agente.

## Cambios aplicados (4, mínimos, sin tocar contratos ni RLS)
1. `backend/src/http/plugins/autenticacion.ts` — verificación del token y lectura del perfil **en paralelo** (`Promise.allSettled`); el `sub` se lee sin verificar sólo para arrancar la lectura, y el resultado se acepta únicamente si coincide con la identidad verificada. Un fallo de verificación sigue propagando (500); un token inválido sigue dando 401.
2. `PerfilesSupabase.listar` (`admin/usuarios`) — recuento y página **en paralelo**.
3. `InscripcionesSupabase.detallar` — secciones, cola y estudiantes **en paralelo** (beneficia a 3 rutas).
4. `InscripcionesSupabase.listarOcupacionCon` — recuento y página **en paralelo**.

## Antes / después (mediana de 5 muestras, mismas operaciones)
| Ruta | Antes | Después | Δ |
|---|---:|---:|---:|
| `mi-horario` (docente) | 1.120 ms | **757 ms** | −32 % |
| `mi-horario` (estudiante) | 874 ms | **613 ms** | −30 % |
| `admin/usuarios` | 1.462 ms | **521 ms** | **−64 %** |
| `aula/.../tablon` | 661 ms | **413 ms** | −38 % |
| `aula/.../trabajo` | 743 ms | **396 ms** | −47 % |
| `aula/mis-entregas` | 806 ms | **461 ms** | −43 % |
| `admin/secciones/:id/inscripciones` | 1.349 ms | **~900 ms** | −33 % |
| `admin/ocupacion` | 992 ms | **836 ms** | −16 % |
| `mis-inscripciones` | 1.041 ms | **953 ms** | −9 % |
Controles: `/yo` 421 → **275 ms**; `/modulos` 418 → **219 ms**. La mejora del hook la hereda toda ruta autenticada.

## Verificación
- `npm run verify` → **675/675, 32 archivos, exit 0** (typecheck + ESLint + Vitest).
- Casos límite de `admin/usuarios`: página normal 25/63 · última parcial 13 · **desplazamiento más allá del final → 200, 0 filas, total 63** · filtro por rol 10/12 · sin token 401 · token inválido 401 · token de alumno 403.
- `humo-invitaciones.mjs` → **34 OK / 0 fallos** · `humo-recuperacion.mjs` → **27 OK / 0 fallos** (residuo 0/0/0).
- E2E completo: ver más abajo.

## Siguiente discriminador
`admin/cuadrante` (899 ms), `admin/aulas` (820 ms), `admin/programas` (718 ms), `admin/acceso` (718 ms) siguen por encima de 700 ms: medir cuántos viajes encadena cada uno antes de tocar nada. Responsive sigue bloqueado hasta cerrar G3.


---

# CHECKPOINT — 2026-10-09 · C7 estabilizado y ciclo E2E completo

## Corrección
- [x] En `e2e/tests/aula_virtual_ciclo.spec.ts`, C7 dejó de buscar el texto inexistente `LIBRO DE CALIFICACIONES` y ahora espera el título real `Calificaciones`. La prueba valida además que las acciones del libro estén montadas y que aparezca la fila del estudiante.
- [x] La corrección cambia la aserción de la prueba, no el producto. No se alteró la lógica de calificación.

## Ejecución real
- [x] Bundle local fresco ya generado en esta sesión por `flutter build web --release --dart-define-from-file=.env.json`.
- [x] `E2E_PERMITIR_CICLO_MUTANTE=1 npx playwright test tests/aula_virtual_ciclo.spec.ts` desde `e2e/`: **7/7 PASS, 0 flaky, exit 0**, duración aproximada 2,6 minutos.
- [x] La ruta real docente → publicación → entrega del aprendiz → libro `Calificaciones` → nota 18 → devolución → visualización de la nota por el aprendiz quedó validada.
- [x] Limpieza acotada ejecutada con `node supabase/limpiar-ciclo-aula.mjs --confirmar --desde "2026-10-09T17:35:07.532Z"`: borró sólo la tarea de esta corrida.
- [x] Limpieza comprobada: tareas **77 → 76**, entregas **228 → 225**, **0 huérfanas**; línea base restaurada.

## Estado del repositorio
- El cambio de la prueba y estos checkpoints permanecen locales.
- No se hizo commit, push ni despliegue.
- No se ejecutaron las sondas `_*.spec.ts` ni el ciclo contra producción.

## Siguiente paso
Continuar con la puerta de performance: medir cargas y operaciones representativas por rol, registrar métricas repetibles y definir el gate de aceptación antes de iniciar el barrido responsive. La suite mutante debe seguir excluida de la regresión predeterminada salvo que se prepare un entorno aislado dedicado.


---

# CHECKPOINT — 2026-10-09 · G3 iniciado tras estabilizar C7

## Cambios
- [x] C7 usa el título real `Calificaciones`; ciclo E2E **7/7 PASS, 0 flaky**. Limpieza restaurada: tareas 77→76, entregas 228→225, 0 huérfanas.
- [x] Añadido `e2e/tests/performance_baseline.spec.ts`, sólo lectura y opt-in mediante `E2E_MEDIR_PERFORMANCE=1`; la suite normal no lo ejecuta por defecto.
- [x] En `backend/src/infra/repos-supabase.ts`, `miHorario()` ejecuta en paralelo las lecturas independientes de clases y guardias para docente después de resolver el período vigente. No cambia la autorización ni el contrato.
- [x] Producción Cloudflare Pages: política de caché de HTML/bootstrap 5 min, JS 1 h, WASM 7 días, Brotli verificados por GET real. Sin embargo, el bundle de producción **no incluye** `restablecer-codigo`, presente en el bundle local; no declarar que producción esté sincronizada con los cambios locales.

## Verificación
- `backend/npm run verify`: **675/675 PASS**, 32 archivos; typecheck, lint y tests.
- `backend/npm run build`: exit 0.
- `E2E_MEDIR_PERFORMANCE=1 npx playwright test tests/performance_baseline.spec.ts`: **3/3 PASS** antes y después del cambio.
- Tres muestras posteriores de `GET /api/v1/mi-horario` docente: 1.856 s, 1.433 s, 1.153 s. Dos muestras previas: 1.996 s, 2.396 s. Mejora preliminar; la muestra es pequeña.
- Una corrida tuvo un outlier de 31.7 s en la transición UI docente aunque las rutas respondieron 200. Debe investigarse, no ocultarse.
- La auditoría detallada y las mediciones de producción están en `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md`.

## Límites y siguiente paso
- G3 sigue **EN CURSO**; Responsive no debe empezar todavía.
- Separar las etapas de `Mis Aulas → tarjeta → apertura de aula` y repetir para diagnosticar el outlier.
- Medir Inscripciones/catálogo y otras vistas calientes; evaluar el doble viaje secuencial del listado administrativo de usuarios antes de tocarlo.
- La sección `SA` sigue siendo datos compartidos: no repetir el E2E mutante hasta disponer de sección aislada.
- Sin commit, push ni despliegue. El bundle local fresco no equivale a producción.


---

# CHECKPOINT — 2026-10-09 · Outlier de E2E explicado y helper optimizado

## Causa raíz del falso outlier
- La medición de 31.7 s no era una demora de respuesta del producto: `AulaVirtualPage.irAMisAulas()` esperaba hasta 30 s una respuesta que podía haberse recibido durante el login, aun cuando la tarjeta de sección ya estaba montada.
- Se añadió el parámetro opcional `seccion`. Cuando la tarjeta existe, el helper evita una espera de red innecesaria; si no, acepta la respuesta del listado o la aparición de la tarjeta real.
- La prueba de rendimiento ahora separa solicitud de horario, render de tarjeta, apertura del aula y montaje.

## Verificación nueva
- `E2E_MEDIR_PERFORMANCE=1 npx playwright test tests/performance_baseline.spec.ts --grep 'docente: arranque' --repeat-each=3`: **3/3 PASS**.
- Etapas docentes (tres muestras): `solicitudMiHorario` 792/44/43 ms; `renderTarjetaAula` 379/33/29 ms; `abrirAulaYRespuesta` 797/790/762 ms; `montajeAula` 85/78/74 ms. El outlier no reapareció.
- `npx playwright test tests/aula_virtual.spec.ts`: **3/3 PASS**, 18.9 s.
- Backend sigue en **675/675 PASS** y `npm run build` terminó con exit 0.

## Estado
G3 continúa **EN CURSO**: ya existe un baseline opt-in por rol, se paralelizaron lecturas independientes del horario docente y se eliminó la espera falsa del helper. Próximo: medir Inscripciones/catálogo y cPanel, repetir muestras de los tres roles y fijar gates de rendimiento antes de Responsive.

Sin commit, push ni despliegue.


# CHECKPOINT — 2026-10-09 · Baseline G3 de performance por rol

- [x] Confirmado bundle local `build/web/main.dart.js` presente y entorno E2E con variables requeridas configuradas (sin imprimir valores secretos).
- [x] Ejecutado `E2E_MEDIR_PERFORMANCE=1 npx playwright test tests/performance_baseline.spec.ts`: **3/3 PASS**, exit 0.
- [x] Repetido con `--repeat-each=2`: **6/6 PASS**, exit 0. Tres muestras por rol; pruebas de solo lectura.
- [x] Medianes de etapas documentadas en `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md`.
- [x] Observaciones: `GET /api/v1/mi-horario` 1.07–2.21 s; `GET /api/v1/admin/usuarios` 1.00–1.66 s; lecturas del aula aproximadamente 0.58–0.83 s. Todas las respuestas observadas fueron HTTP 200.
- [ ] No se aplicó optimización todavía: falta separar tiempo del handler/repositorio/SQL, payload de respuesta y efecto cold/warm para identificar la causa raíz antes de cambiar código.
- [ ] G3 no está cerrado: ampliar medición a cPanel/inscripciones y medir payloads; lograr al menos una mejora cuantificable y ejecutar regresión relacionada.
- [ ] Responsive permanece en espera hasta cerrar la puerta de performance.
- Estado Git: cambios locales conservados; sin commit, push ni despliegue.

---

# CHECKPOINT — 2026-10-09 (sesión 3) · G3: cuadrante medido, paginación validada, E2E verde

**Fecha/hora:** 2026-10-09 · **Rama:** `main` · **HEAD de referencia:** `978e52f` (sin commit).
**Detalle y tablas:** `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md`.

## Medición con build fresco en puerto aislado
`127.0.0.1:3001` seguía sirviendo un `dist` **viejo** (`GET /yo` 473 ms vs **243 ms** en 3002, el build
fresco). **La medida de 3001 no es un «después» válido.** Se levantó el build recién compilado en
3002 (sin tocar 3001) y se midió con la cuenta E2E admin (1 calentamiento + 7 muestras):

| Endpoint | Antes | Con cambios | Δ |
|---|---:|---:|---:|
| `admin/cuadrante` | 1.155 ms | **679 ms** `[646–713]` | −41 %, **estable** |
| `admin/aulas` | 897 ms | **552 ms** | −38 % |
| `admin/programas` | 1.020 ms | **557 ms** | −45 % |
| `admin/acceso` | 961 ms | **572 ms** | −41 % |

**La variabilidad alta anterior de cuadrante era ruido ambiental** (3001 con dist viejo + contención),
no la ruta: ahora es estable (dispersión 67 ms). Desglose: hook **241 ms** + etapa 1 **~220 ms** +
etapa 2 **~220 ms** ≈ 680 ms — **3 esperas secuenciales, en su suelo** con el modelo actual.
**El paralelismo es real y medido:** 2 consultas en paralelo cuestan como 1 (193 ms vs 405 en serie).

## Paginación y contrato (acto previo del cierre)
`C:/tmp/validar-paginacion.mjs` → **44 OK / 0 fallos** sobre `usuarios`, `programas`, `aulas`, `acceso`:
total estable entre páginas · última página exacta · **desplazamiento fuera de rango → 200 con 0 filas**
(nunca 500) · con `limite≥total` las filas son exactamente el total (recuento y página filtran igual).
Añadidas 3 pruebas de contrato + 1 control negativo a `curriculo-repositorio.test.ts` (la rama del
416 y la igualdad de filtros recuento/página), reproduciendo el 416 sin red con `secuencias` en el doble.

## Verificación
`git diff --check` limpio · `npm run verify` → **679/679 en 32 archivos, exit 0** (675 + 4 nuevas) ·
`npm run build` → exit 0 · `npx tsc`/`eslint` limpio. · **E2E completo contra el build fresco y el
backend de 3002: 24 ok / 0 fallos** (Stepper incluido). `EXIT=124` es el `timeout` del teardown, tras
los 24 `ok`.

## Hallazgos de trampa (dejar registrados)
- **El servicio de 3001 se cayó a mitad de sesión** (no por mí). El Stepper falló 2× con
  `ECONNREFUSED` antes de reapuntar `E2E_BACKEND_URL=3002`. La salud de la ruta bajo medición debe
  comprobarse en el **mismo puerto** que se quiere medir.
- **El `231` (`CreateFile failed 231`) es intermitente**: esta sesión el build de Flutter **sí** corrió
  para `build/web` (12:39), pero los dos intentos de reconstruir apuntando a 3002 murieron con el 231
  (al hacer Flutter llamar a `git.EXE`). Es **agotamiento de tuberías nombradas** del entorno, no del
  proyecto; el frontend ya estaba al día, así que **no recompilé**: parcheé una **copia** del bundle
  (`/c/tmp/parchear-3002.mjs`) para apuntarlo a 3002 — reversible, sin tocar el artefacto real.

## Estado
G3 **sigue EN CURSO** — no se cierra: ya hay una mejora cuantificable y regresión verde, pero falta la
**medición estable ya en producción** y la decisión sobre caché del período / JWT local. Responsive
sigue **bloqueado**. Sin commit, push ni despliegue.
