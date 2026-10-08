# AUDITORÍA DE ESTADO REAL — INCES-LMS-PROJECT

> **Fecha de ejecución:** 2026-10-05 (Auditoría Técnica Automatizada y Empírica)
> **Entorno:** Windows 10/11 · Node.js v24.15.0 · Python 3.12 · Dart SDK / Flutter
> **Repositorio:** `Burmistrov4/INCES---LMS` (rama `audit_and_implement_lms`, commit base `f53a3ac`)
> **Regla de verdad:** Código real > Pruebas reales > Configuración real > Base de datos real > Documentación.

---

## 1. RESUMEN EJECUTIVO Y FOTOGRAFÍA GLOBAL

| Componente | Estado Real | Pruebas Ejecutadas | Resultado Verificable |
|---|---|---|---|
| **Git / Repositorio** | 🟢 COMPLETADO | `git status`, `git log` | Working copy limpio, rama activa `audit_and_implement_lms` |
| **Backend API (Node/TS/Fastify)** | 🟢 COMPLETADO | `npm --prefix backend run verify` | `tsc --noEmit` (0 err), ESLint (0 err), Vitest (25 suites, 637 tests pasados) |
| **Frontend (Flutter Web / CanvasKit)** | 🟢 COMPLETADO | `node devops/analizar-dart.mjs .` | 207 archivos analizados: 0 errores, 0 avisos, 0 infos |
| **Base de Datos / Migraciones** | 🟢 COMPLETADO | Libro mayor + catálogo en la nube | 34 migraciones en disco coinciden 100% con hash SHA-256 (LF) en `public.schema_migrations`. 0 pendientes. |
| **Catálogo Supabase / RLS** | 🟢 COMPLETADO | `supabase/verificar-esquema.mjs` | 57 controles superados: RLS activo en todas las tablas, RPCs Security Definer verificadas, vistas con `security_invoker`. (1 advertencia explicada: 6 cursos libres vs 5 esperados debido a `SEM-SOL-CL` de la semilla E2E). |
| **Suite E2E (Playwright)** | 🟡 PARCIAL | Inspección de arnés y specs | 14 casos verdes en CI/local previo (`export_csv`, `stepper_inscripcion`, `aula_virtual`). Ciclo completo docente↔aprendiz pendiente de cierre. |
| **Planilla Digital (Genérica)** | 🟢 COMPLETADO | `backend/src/infra/planilla-pdf.ts`, `planilla-xlsx.ts` | Generación bajo demanda en A4 funcional y probada (10 tests Vitest cada una). |
| **Planilla Oficial INCES (Física)** | 🟡 PARCIAL | Medición geométrica y trazabilidad | Matriz 38/38 campos oficiales trazada. Geometría 612×792 pt y rectángulos de inserción **medidos empíricamente al 100%**. Pendiente implementación del adaptador y renderer oficial. |

---

## 2. AUDITORÍA DETALLADA POR CAPA

### 2.1 Backend (Node.js + Fastify 5 + TypeScript + Zod)
- **Estado:** 🟢 COMPLETADO
- **Arquitectura:** Stateless, modular, con validación estricta Zod en rutas, soporte R2 (Cloudflare S3-compatible), endpoints de autenticación, cPanel administrativo, aula virtual, cuadrante, inscripciones, asistencia QR y planillas.
- **Evidencia empírica:**
  - `tsc --noEmit`: 0 errores de compilación.
  - `eslint .`: 0 advertencias o errores de linting.
  - `vitest run`: **25 suites ejecutadas, 637 aserciones pasadas en 49.64s**, 0 fallos.
    - `test/archivos.test.ts` (53 tests)
    - `test/asistencia.test.ts` (44 tests)
    - `test/cuadrante.test.ts` (62 tests)
    - `test/aula.test.ts` (53 tests)
    - `test/inscripciones.test.ts` (38 tests)
    - `test/admin.test.ts` (51 tests)
    - `test/openapi.test.ts` (9 tests)
    - `test/curriculo.test.ts` (37 tests)
    - `test/planilla.test.ts` (24 tests)
    - `test/secciones.test.ts` (23 tests)
    - `test/planilla-xlsx.test.ts` (10 tests)
    - `test/planilla-pdf.test.ts` (10 tests)
    - `test/autenticacion.test.ts` (12 tests)
    - `test/invitaciones.test.ts` (9 tests)
    - `test/resiliencia.test.ts` (13 tests)
    - `test/modulos.test.ts` (16 tests)
    - `test/r2.test.ts` (30 tests)
    - `test/salud.test.ts` (4 tests)
    - `test/esquemas.test.ts` (37 tests)
    - `test/reglas-cuadrante.test.ts` (28 tests)
    - `test/curriculo-repositorio.test.ts` (8 tests)
    - `test/env.test.ts` (10 tests)
    - `test/reglas-curriculo.test.ts` (18 tests)
    - `test/reglas-admin.test.ts` (10 tests)
    - `test/reglas-inscripciones.test.ts` (28 tests)

### 2.2 Frontend (Flutter Web CanvasKit)
- **Estado:** 🟢 COMPLETADO (en tipo y análisis)
- **Evidencia empírica:**
  - Dependencias offline sincronizadas con Dart SDK: `dart pub get --offline`.
  - Verificación estricta de tipos con `node devops/analizar-dart.mjs .`:
    - **207 archivos analizados**.
    - **0 errores, 0 avisos, 0 infos**.
    - Limpieza absoluta de tipos requerida por el listón del CI.

### 2.3 Base de Datos y Seguridad (Supabase PostgreSQL 17.6 + RLS)
- **Estado:** 🟢 COMPLETADO
- **Migraciones:**
  - 34 migraciones registradas en `supabase/migrations/`.
  - Comparación criptográfica directa contra la tabla `public.schema_migrations` en la nube: **34/34 coincidencia exacta de hash SHA-256 (LF)**.
  - 0 migraciones pendientes. 0 deriva real en el esquema.
- **Inspección del Catálogo (`supabase/verificar-esquema.mjs`):**
  - RLS activo en el 100% de las tablas públicas (incluidas `academic_periods`, `aspirantes`, `attendance_marks`, `attendance_sessions`, `auth_logs`, `classrooms`, `enrollments`, `files_metadata`, `inscripcion_campos`, `m6_anuncios`, `m6_entregas`, `m6_tareas`, `profiles`, `sections`, etc.).
  - Triggers de integridad activos (`system_modules_proteger_critico`, `proteger_ultimo_admin`, `aspirantes_validar_planilla`, etc.).
  - Funciones `security definer` con permisos de ejecución estrictamente restringidos (RPCs de inscripciones, de archivos R2, resolutores de asistencia QR, etc.).
  - Vistas configuradas con `security_invoker = true` (`v_cuadrante_clases`, `v_cuadrante_guardias`, `v_exportacion_hacer`, `v_ocupacion_secciones`, `v_periodo_vigente`).

### 2.4 Infraestructura E2E (Playwright)
- **Estado:** 🟡 PARCIAL
- **Evidencia empírica:**
  - Arnés local operativo contra bundle web compilado y backend en puerto local.
  - Specs funcionales en verde:
    - `export_csv.spec.ts` (10 casos)
    - `stepper_inscripcion.spec.ts` (1 caso)
    - `aula_virtual.spec.ts` (3 casos aprendiz)
  - Caso pendiente / en progreso: `aula_virtual_ciclo.spec.ts` (conmutación de pestañas docente-aprendiz e inmutabilidad de sembrado).

---

## 3. AUDITORÍA DE LA PLANILLA OFICIAL INCES

### 3.1 Documento Físico vs Modelo Digital
- **Documento original:** `PLANILLA DE INSCRIPCION INCES - Requiere digitalizacion y automatizacion en el nuevo sistema.pdf`.
  - Tamaño: **612.00 × 792.00 pt** (US Letter exacto).
  - Páginas: **1 página**.
  - Estructura: Formulario preimpreso con 425 segmentos de línea vectorial (`m ... l`), 10 rectángulos (`re`), y 175 elementos de texto/casillas (`□`).
- **Trazabilidad de datos:**
  - 38/38 campos oficiales existen en el catálogo `inscripcion_campos` y se persisten en `aspirantes.datos_planilla`.
  - 4 campos de cabecera son derivados de la sección (`FECHA`, `PROYECTO`, `ESPACIO INTEGRAL SOCIALISTA`, `HORARIO`).
  - Misiones: **20/20 misiones exactas**, dispuestas en una matriz de 5 columnas × 4 filas, todas con casilla `□` y campo subrayado `Desde`.
  - Familiares: **8 columnas exactas** (`cedula`, `nombres`, `apellidos`, `fecha_nac`, `genero`, `parentesco`, `diversidad_funcional`, `estado_civil`) con capacidad de hasta 5 filas en la tabla del documento.

---

## 4. MAPA GEOMÉTRICO MEDIDO (RECTÁNGULOS DE INSERCIÓN)

A continuación se presentan las coordenadas empíricas reales extraídas directamente de los operadores vectoriales del PDF oficial (origen en esquina inferior izquierda, 612 × 792 pt):

```
+========================================================================================================+
| ZONA / CAMPO                              | X (pt) | Y (pt) | ANCHO (pt) | ALTO (pt) | TIPO DE ENTRADA |
+========================================================================================================+
| ENCABEZADO (y=643.3 .. 719.4)                                                                          |
| - Fecha de Inscripción                    | 250.0  | 708.0  | 75.0       | 11.0      | Texto derivado  |
| - N° Preimpreso                           | 395.0  | 708.0  | 185.0      | 11.0      | Texto / Vacío   |
| - Proyecto (Programa)                     | 275.0  | 682.0  | 305.0      | 11.0      | Texto derivado  |
| - Espacio Integral Socialista             | 145.0  | 657.0  | 180.0      | 11.0      | Texto derivado  |
| - Horario                                 | 375.0  | 657.0  | 205.0      | 11.0      | Texto derivado  |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| DATOS PERSONALES: IDENTIFICACIÓN (y=580.1 .. 615.6)                                                    |
| - 1er. Nombre                             |  31.2  | 583.0  | 104.0      | 17.0      | Texto           |
| - 2do. Nombre                             | 141.0  | 583.0  | 104.0      | 17.0      | Texto           |
| - 1er. Apellido                           | 250.0  | 583.0  | 104.0      | 17.0      | Texto           |
| - 2do. Apellido                           | 360.0  | 583.0  | 104.0      | 17.0      | Texto           |
| - N° de C.I. / Pasaporte                  | 470.0  | 583.0  | 111.0      | 17.0      | Texto           |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| DATOS PERSONALES: DEMOGRAFÍA (y=538.4 .. 580.1)                                                        |
| - Nacionalidad                            |  32.0  | 542.0  | 128.0      | 22.0      | Texto           |
| - F. de Nacimiento - Día                  | 167.0  | 542.0  |  23.0      | 15.0      | 2 dígitos       |
| - F. de Nacimiento - Mes                  | 196.0  | 542.0  |  20.0      | 15.0      | 2 dígitos       |
| - F. de Nacimiento - Año                  | 222.0  | 542.0  |  20.0      | 15.0      | 4 dígitos       |
| - Edad                                    | 248.0  | 542.0  |  26.0      | 15.0      | Entero          |
| - Género Femenino (□ F)                   | 303.3  | 551.4  |   8.0      |  8.0      | Checkmark (X)   |
| - Género Masculino (□ M)                  | 324.7  | 551.4  |   8.0      |  8.0      | Checkmark (X)   |
| - Estado Civil: Soltero (□)               | 351.2  | 556.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Estado Civil: Casado (□)                | 386.7  | 556.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Estado Civil: Divorciado (□)            | 427.8  | 556.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Estado Civil: Viudo (□)                 | 370.9  | 547.5  |   8.0      |  8.0      | Checkmark (X)   |
| - Estado Civil: Concubinato (□)           | 399.4  | 547.5  |   8.0      |  8.0      | Checkmark (X)   |
| - Pueblo Indígena: SI (□)                 | 507.3  | 556.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Pueblo Indígena: NO (□)                 | 522.9  | 556.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Pueblo Indígena: Cuál                   | 530.0  | 542.0  |  50.0      | 10.0      | Texto           |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| DIVERSIDAD FUNCIONAL Y PRÁCTICAS (y=456.1 .. 538.4)                                                    |
| - Discapacidad: Física Mano (□)           |  31.2  | 504.1  |   8.0      |  8.0      | Checkmark (X)   |
| - Discapacidad: Sensorial Ceguera (□)     |  94.2  | 504.1  |   8.0      |  8.0      | Checkmark (X)   |
| - Discapacidad: Física Piernas (□)        |  31.2  | 494.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Discapacidad: Debilidad Intelectual (□) |  94.2  | 494.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Discapacidad: Sensorial Auditiva (□)    |  31.2  | 485.5  |   8.0      |  8.0      | Checkmark (X)   |
| - Discapacidad: Ninguna (□)               |  94.2  | 485.5  |   8.0      |  8.0      | Checkmark (X)   |
| - Discapacidad: Indique Cuál              |  85.0  | 465.0  |  75.0      | 11.0      | Texto           |
| - Deporte Practicado                      | 166.0  | 460.0  |  92.0      | 45.0      | Texto           |
| - Deporte: Desde                          | 262.0  | 460.0  |  36.0      | 45.0      | Texto / Fecha   |
| - Actividad Cultural                      | 304.0  | 460.0  |  92.0      | 45.0      | Texto           |
| - Cultural: Desde                         | 397.0  | 460.0  |  42.0      | 45.0      | Texto / Fecha   |
| - Organización Social                     | 445.0  | 460.0  |  92.0      | 45.0      | Texto           |
| - Organización: Desde                     | 539.0  | 460.0  |  42.0      | 45.0      | Texto / Fecha   |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| UBICACIÓN Y CONTACTO (y=361.3 .. 456.1)                                                                |
| - Estado                                  |  65.0  | 415.0  |  72.0      | 14.0      | Texto           |
| - Municipio                               | 185.0  | 415.0  |  88.0      | 14.0      | Texto           |
| - Parroquia                               | 330.0  | 415.0  | 112.0      | 14.0      | Texto           |
| - Comunidad                               | 495.0  | 415.0  |  86.0      | 14.0      | Texto           |
| - Dirección de Habitación                 |  31.2  | 389.0  | 390.0      | 13.0      | Texto           |
| - Teléfono Celular                        | 429.0  | 389.0  |  72.0      | 13.0      | Texto           |
| - Teléfono Fijo                           | 507.0  | 389.0  |  74.0      | 13.0      | Texto           |
| - Correo Electrónico                      | 115.0  | 364.0  | 165.0      | 13.0      | Texto           |
| - Twitter                                 | 315.0  | 364.0  | 100.0      | 13.0      | Texto           |
| - Facebook                                | 460.0  | 364.0  | 120.0      | 13.0      | Texto           |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| TABLA DE FAMILIARES (y=245.8 .. 333.3, 5 filas de alto = 17.5 pt c/u)                                  |
| - Columna 1: Cédula de Identidad          |  31.2  | y_row  |  75.0      | 14.0      | Texto           |
| - Columna 2: Nombres                      | 110.0  | y_row  |  76.0      | 14.0      | Texto           |
| - Columna 3: Apellidos                    | 190.0  | y_row  |  82.0      | 14.0      | Texto           |
| - Columna 4: Fecha de Nacimiento          | 276.0  | y_row  |  67.0      | 14.0      | Texto / Fecha   |
| - Columna 5: Género (F/M)                 | 347.0  | y_row  |  31.0      | 14.0      | Centrado F/M    |
| - Columna 6: Parentesco                   | 381.0  | y_row  |  62.0      | 14.0      | Texto           |
| - Columna 7: Diversidad Funcional         | 446.0  | y_row  |  71.0      | 14.0      | Texto           |
| - Columna 8: Estado Civil                 | 521.0  | y_row  |  61.0      | 14.0      | Texto           |
| * y_row Fila 1: 318.0 | Fila 2: 300.5 | Fila 3: 283.0 | Fila 4: 265.5 | Fila 5: 248.0                  |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| MISIONES (5 columnas x 4 filas, y=167.8 .. 227.3)                                                      |
| - Columna 1 (x=31.2 box, Desde=95.2..137) | Fila 1: RIBAS          (y=216.9)                           |
|                                           | Fila 2: MERCAL         (y=202.9)                           |
|                                           | Fila 3: MADRES BARRIO  (y=189.0)                           |
|                                           | Fila 4: HÁBITAT        (y=175.0)                           |
| - Columna 2 (x=142.3 box, Desde=202..248) | Fila 1: PIAR           (y=216.9)                           |
|                                           | Fila 2: NEGRA HIPÓLITA (y=202.9)                           |
|                                           | Fila 3: BARRIO ADENTRO (y=189.0)                           |
|                                           | Fila 4: MIRANDA        (y=175.0)                           |
| - Columna 3 (x=253.3 box, Desde=321..359) | Fila 1: IDENTIDAD      (y=216.9)                           |
|                                           | Fila 2: CASA ALIMENTAC (y=202.9)                           |
|                                           | Fila 3: GUAICAIPURO    (y=189.0)                           |
|                                           | Fila 4: ROBINSON I-II  (y=175.0)                           |
| - Columna 4 (x=364.4 box, Desde=432..470) | Fila 1: HIJOS DE VZLA  (y=216.9)                           |
|                                           | Fila 2: SUCRE          (y=202.9)                           |
|                                           | Fila 3: VUELVAN CARAS  (y=189.0)                           |
|                                           | Fila 4: V.C. JÓVENES   (y=175.0)                           |
| - Columna 5 (x=475.4 box, Desde=541..580) | Fila 1: G.M. VIVIENDA  (y=216.9)                           |
|                                           | Fila 2: G.M. AGRO VZLA (y=202.9)                           |
|                                           | Fila 3: G.M. SABER-TRAB(y=189.0)                           |
|                                           | Fila 4: NINGUNA        (y=175.0)                           |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| FORMACIÓN (y=116.6 .. 167.8)                                                                           |
| - Nivel Educativo                         |  31.2  | 122.0  | 124.0      | 18.0      | Texto           |
| - Avance: Culminó (□)                     | 160.2  | 128.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Avance: No Completó (□)                 | 201.2  | 128.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Avance: En Progreso (□)                 | 256.2  | 128.8  |   8.0      |  8.0      | Checkmark (X)   |
| - Último Año Cursado                      | 312.0  | 122.0  | 130.0      | 18.0      | Texto           |
| - Especialidad                            | 448.0  | 122.0  | 133.0      | 18.0      | Texto           |
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| OTRAS FORMACIONES (y=81.1 .. 116.6)                                                                    |
| - Descripción                             |  31.2  |  83.0  | 550.0      | 22.0      | Texto multi-línea|
+-------------------------------------------+--------+--------+------------+-----------+-----------------+
| EXPERIENCIAS EMPÍRICAS (y=32.7 .. 81.1, Fila de datos y=34.0 .. 52.0)                                  |
| - Área del Conocimiento                   |  31.2  |  34.0  | 133.0      | 17.0      | Texto           |
| - Tiempo (Meses)                          | 170.0  |  34.0  | 133.0      | 17.0      | Texto           |
| - ¿Portafolio de Evidencias? (SI/NO)      | 309.0  |  34.0  | 133.0      | 17.0      | Texto / Check   |
| - Enlace                                  | 448.0  |  34.0  | 133.0      | 17.0      | Texto URL       |
+========================================================================================================+
```

---

## 5. MATRIZ DE ESTADO REAL POR FASE DEL PROYECTO

```
+==================================================================================+
| FASE | NOMBRE                           | ESTADO REAL    | OBSERVACIONES         |
+==================================================================================+
| F0   | Auditoría Base                   | 🟢 COMPLETADO  | Fotografía real       |
| F1   | Integridad de Base de Datos      | 🟢 COMPLETADO  | 34 migraciones, RLS OK|
| F2   | Seguridad y Roles                | 🟢 COMPLETADO  | RPCs Security Definer |
| F3   | Onboarding / Registro            | 🟢 COMPLETADO  | Flujo aspirante activo|
| F4   | Programas                        | 🟢 COMPLETADO  | Curriculo M2 activo   |
| F5   | Secciones                        | 🟢 COMPLETADO  | Cuadrante M3 activo   |
| F6   | Inscripciones                    | 🟢 COMPLETADO  | Máquina estados M4 OK |
| F7   | Planilla Digital (Genérica A4)   | 🟢 COMPLETADO  | PDF y XLSX bajo demanda|
| F8   | Planilla Oficial INCES (Física)  | 🟡 PARCIAL     | Geometría cerrada;    |
|      |                                  |                | falta adaptador/render|
| F9   | Endpoints Planilla Oficial       | 🔴 PENDIENTE   | Requiere F8           |
| F10  | Workflow Digital Planilla        | 🔴 PENDIENTE   | BORRADOR->ENVIADA->...|
| F11  | Bloqueo de Edición               | 🔴 PENDIENTE   | Guardias por estado   |
| F12  | Observaciones Admin              | 🔴 PENDIENTE   | Motivo y corrección   |
| F13  | Versionado Histórico             | 🔴 PENDIENTE   | Snapshots JSONB       |
| F14  | Clases                           | 🟢 COMPLETADO  | Cuadrante M3 activo   |
| F15  | Asistencia QR en vivo            | 🟢 COMPLETADO  | M7 desplegado y probado|
| F16  | Evaluaciones y Notas             | 🟡 PARCIAL     | Tareas M6 activas;    |
|      |                                  |                | M7 actas apagado      |
| F17  | Aula Virtual                     | 🟢 COMPLETADO  | M6 activo (Playwright)|
| F18  | Prácticas (Pasantías)            | ⚫ APAGADO     | M8 apagado intencional|
| F19  | Egreso                           | 🔴 PENDIENTE   | Consolidación final    |
| F20  | Certificados                     | 🔴 PENDIENTE   | Generación con QR     |
| F21  | Administración (cPanel)          | 🟢 COMPLETADO  | Panel módulos activo  |
| F22  | Responsive                       | 🟡 PARCIAL     | Web CanvasKit desktop |
| F23  | Performance                      | 🟢 COMPLETADO  | Consultas directas    |
| F24  | Testing Automatizado             | 🟢 COMPLETADO  | 637 tests backend, E2E|
| F25  | E2E Integral Ciclo Completo      | 🟡 PARCIAL     | Requiere F8-F12        |
+==================================================================================+
```

---

## 6. PRIMERA FASE PENDIENTE: FASE 8 (PLANILLA OFICIAL INCES)

Con la geometría y los rectángulos de inserción totalmente cerrados y medidos mediante análisis vectorial del PDF oficial, la primera fase técnica pendiente es la **Fase 8: Construcción del Adaptador Semántico (`PlanillaOficialData`) y el Renderer PDF Oficial (`planilla-oficial-pdf.ts`)**, sin alterar el renderer genérico existente.
