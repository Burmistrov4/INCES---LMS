# Auditoría — Planilla Oficial de Inscripción INCES

> **Fecha:** 2026-10-05 · **Alcance:** `INCES-LMS-PROJECT` · **Estado:** diagnóstico
> **No se ha modificado ni una línea de código.** Todo lo que sigue está medido;
> lo que no se pudo medir va marcado como **NO VERIFICADO** con la razón.

---

## 1. Estado actual

**Lo que funciona, con evidencia:**

| Pieza | Estado | Evidencia |
|---|---|---|
| El aspirante rellena la planilla y se persiste | ✅ | `PUT /api/v1/yo/planilla` (`rutas/yo.ts`), exige sesión |
| El PDF se genera **bajo demanda** | ✅ | `generarPdf(usuarioId)` — no hay archivo guardado |
| El `.xlsx` editable, ídem | ✅ | `generarXlsx(usuarioId)` |
| El **admin** descarga la planilla de cualquier aspirante | ✅ | `GET /api/v1/inscripcion/planilla/:usuarioId/pdf` con `exigirAdmin()` + RLS `aspirantes_admin_all` |
| Hay UI para hacerlo | ✅ | `lib/screens/admin/cpanel_inscripciones_inscritos_dialog.dart` — «inscritos vivos de una sección y la descarga de su planilla» |
| **No hay duplicación de documentos** | ✅ | Ver §9 |
| El PDF se genera sin reventar | ✅ | `planilla-pdf.ts`, 349 líneas, `pdf-lib` |

---

## 2. Hallazgo principal

**El PDF actual no es una copia del formulario oficial. Es un documento distinto, y lo dice su propio código.**

Cabecera de `backend/src/infra/planilla-pdf.ts`, líneas 14-23:

> «**LA FUENTE DE VERDAD ES EL CATÁLOGO, NO UN DISEÑO A MANO.** El PDF no tiene
> los campos hardcodeados. Los lee del catálogo que le pasa el adaptador […]
> Lo que sí es fijo es la **forma de cada tipo**: cómo se pinta un `tabla`, un
> `rejilla`, un `seleccion`.»

**Eso es un renderizador de documento genérico, no un formulario.** Y el original
es exactamente lo contrario: **una planilla preimpresa de una sola página con
casillas en posiciones fijas.**

Diferencias medidas entre los dos artefactos:

| | Original oficial | Implementación actual |
|---|---|---|
| Páginas | **1** | **1 o varias** («un PDF de una o varias páginas») |
| Tamaño | **612×792 pt — US Letter** | **595,28×841,89 pt — A4** (`ANCHO`/`ALTO`, líneas 50-51) |
| Campos | **fijos**, preimpresos | **leídos del catálogo**, dinámicos |
| Estructura | casillas, líneas y tablas en posición fija | lista de etiqueta/valor por grupos |
| Casillas `□` | **el elemento central** del formulario | `esVerdadero` + `seleccion` — forma genérica |

**La consecuencia arquitectónica, dicha sin rodeos:** no se puede «mover
coordenadas» para que el actual se parezca al oficial, porque **el actual no tiene
coordenadas que mover** — dibuja en flujo, no en posiciones. Reproducir el
formulario oficial **no es un ajuste del renderizador: es otro renderizador.**

---

## 3. Arquitectura actual del flujo

```
Aspirante
  ↓  formulario Flutter (campos definidos por el CATÁLOGO `inscripcion_campos`)
  ↓  validación (Zod en el backend)
  ↓  PUT /api/v1/yo/planilla
  ↓  aspirantes.datos_planilla  (jsonb: {campo: valor})
  ↓
  ├─→ planilla-valores.ts   → EntradaPlanilla[]  (etiqueta + valor, genérico)
  │      ↓
  │   planilla-pdf.ts       → PDF A4, flujo, tipos fijos por `tipo` de campo
  │      ↓
  │   GET /api/v1/yo/planilla/pdf          (aspirante, su propia ficha)
  │   GET /api/v1/inscripcion/planilla/:id/pdf   (admin, cualquier ficha)
  │
  └─→ planilla-xlsx.ts      → .xlsx editable (mismo `EntradaPlanilla`)
```

**El punto clave:** hay **un solo origen de datos** (`datos_planilla`) y **dos
renderizadores que comparten el mismo contrato** (`EntradaPlanilla`). Añadir un
tercer renderizador —el de la planilla oficial— **no rompe nada de esto**: se
enchufa al mismo contrato.

---

## 4. Matriz de trazabilidad

**Cómo leerla.** «Existe en modelo» se refiere al catálogo `inscripcion_campos` +
`datos_planilla`. **El catálogo vive en la base de datos y no lo he consultado** —
ver §7, riesgo 1. Por eso la columna 3 va marcada **NO VERIFICADO** salvo donde
hay evidencia de código.

| # | Campo oficial | Existe en modelo | Fuente de datos | En PDF actual | Acción |
|---|---|---|---|---|---|
| **Encabezado** | | | | | |
| 1 | FECHA | **NO VERIFICADO** | ? | genérico | B/C — verificar catálogo |
| 2 | N.º PREIMPRESO | **NO VERIFICADO** | ? | genérico | **A/D — es preimpreso: ¿se captura?** |
| 3 | PROYECTO | **NO VERIFICADO** | ? | genérico | verificar |
| 4 | ESPACIO INTEGRAL SOCIALISTA | **NO VERIFICADO** | ? | genérico | verificar |
| 5 | HORARIO | **NO VERIFICADO** | ? | genérico | verificar |
| **Datos personales** | | | | | |
| 6-9 | 1er./2do. nombre, 1er./2do. apellido | sí (nombres/apellidos) | `planilla-valores.ts` emite `nombres` y `apellidos` | sí | **E — el oficial separa 1º y 2º; ¿lo hace el modelo?** |
| 10 | N.º de CI / PASAPORTE | sí | `identidad`, `cedula` | sí | **E — el oficial admite pasaporte; ¿el modelo distingue tipo?** |
| 11 | NACIONALIDAD | **NO VERIFICADO** | ? | genérico | verificar |
| 12 | F. DE NACIMIENTO (DÍA/MES/AÑO) | sí | `formatearFecha` | sí | **F — el oficial la parte en tres casillas** |
| 13 | EDAD (AÑOS) | **NO VERIFICADO** | ? | genérico | **C — ¿se calcula o se captura?** |
| 14 | GÉNERO (□F □M) | **NO VERIFICADO** | ? | genérico | **E — sólo dos casillas; el catálogo admite más** |
| 15 | ESTADO CIVIL (5 casillas) | **NO VERIFICADO** | ? | genérico | verificar las 5 |
| 16 | PUEBLO INDÍGENA (□SI □NO + cuál) | **NO VERIFICADO** | ? | genérico | **C — dos partes: booleano + texto** |
| 17 | DIVERSIDAD FUNCIONAL (6 casillas) | **NO VERIFICADO** | ? | genérico | verificar las 6 |
| 18-20 | DEPORTES / CULTURALES / ORGANIZACIONES (+DESDE) | **NO VERIFICADO** | ? | genérico | **C — cada una es valor + fecha** |
| **Ubicación y contacto** | | | | | |
| 21-24 | ESTADO · MUNICIPIO · PARROQUIA · COMUNIDAD | **NO VERIFICADO** | ? | genérico | verificar (¿dependen del catálogo territorial?) |
| 25 | DIRECCIÓN DE HABITACIÓN | **NO VERIFICADO** | ? | genérico | verificar |
| 26-27 | TELÉFONO CELULAR · FIJO | **NO VERIFICADO** | ? | genérico | verificar |
| 28 | CORREO ELECTRÓNICO | sí | `email` | sí | ✅ |
| 29-30 | Twiter · Facebook | **NO VERIFICADO** | ? | genérico | **A — probablemente no se capturan** |
| **Familiares (tabla variable)** | | | | | |
| 31 | CÉDULA, 1er/2do nombres, 1er/2do apellidos, F. nacimiento, género, parentesco, diversidad funcional, estado civil | **NO VERIFICADO** | ? | tipo `tabla` genérico | **G — 9 columnas; ver §7 riesgo 3** |
| **Misiones (20 casillas + «desde cuándo»)** | | | | | |
| 32 | RIBAS · MERCAL · MADRES DEL BARRIO · HÁBITAT · PIAR · NEGRA HIPÓLITA · BARRIO ADENTRO · MIRANDA · IDENTIDAD · CASA DE ALIMENTACIÓN · GUAICAIPURO · ROBINSON I y II · HIJOS DE VZLA. · SUCRE · VUELVAN CARAS · VUELVAN CARAS JÓVENES · G.M. VIVIENDA VZLA. · G.M. AGROVENEZUELA · G.M. SABER Y TRABAJO · **NINGUNA** | **NO VERIFICADO** | ? | genérico | **G — 20 opciones, y cada marcada lleva su «desde cuándo»** |
| **Formación** | | | | | |
| 33 | NIVEL EDUCATIVO | **NO VERIFICADO** | ? | genérico | verificar |
| 34 | ESTADO DEL AVANCE (□CULMINÓ □NO COMPLETÓ □EN PROGRESO) | **NO VERIFICADO** | ? | genérico | **C — tres casillas excluyentes** |
| 35-36 | ÚLTIMO AÑO CURSADO · ESPECIALIDAD | **NO VERIFICADO** | ? | genérico | verificar |
| 37 | OTRAS FORMACIONES | **NO VERIFICADO** | ? | genérico | **G — sección libre; el oficial no la detalla** |
| **Experiencias empíricas (tabla)** | | | | | |
| 38 | ÁREA DEL CONOCIMIENTO · TIEMPO (MESES) · ¿PORTAFOLIO? · ENLACE | **NO VERIFICADO** | ? | tipo `tabla` genérico | verificar |

**Y un hallazgo que la matriz destapa:** el encabezado pide **N.º PREIMPRESO**,
que es el número del **talonario físico**. Eso no es un dato del aspirante: es un
dato del **papel**. Si el sistema genera la planilla, **ese número hay que
capturarlo al entregarla o el campo queda vacío para siempre** — y el formulario
oficial lo tiene en el encabezado, así que su ausencia se nota.

---

## 5. Campos faltantes

**No puedo dar la lista exacta, y ésa es la conclusión más importante de esta sección.**

La matriz tiene **38 filas** y **36 van marcadas NO VERIFICADO** en la columna
decisiva —*¿existe en el modelo?*—. La razón es concreta: **el catálogo de campos
vive en la tabla `inscripcion_campos` de Supabase, y no la he consultado.** Sin
esa consulta, decir «falta el campo X» sería deducirlo del PDF, no medirlo — y en
este proyecto eso ya ha costado caro varias veces.

**Lo que sí está claro por código:** `planilla-valores.ts` emite `nombres`,
`apellidos`, `cedula`, `identidad`, `email` y un `campos[]` genérico. **Todo lo
demás depende del catálogo**, así que la lista de faltantes **es una consulta, no
una lectura de código.**

---

## 6. Diferencias visuales

Medidas, no estimadas:

1. **Tamaño de página distinto.** Oficial **612×792 (US Letter)**; el renderizador **595,28×841,89 (A4)**. Imprimir el actual en papel oficial **no cuadra**.
2. **Flujo contra posición.** El oficial tiene casillas en sitios fijos; el actual dibuja etiqueta/valor en secuencia.
3. **Las casillas `□` son el elemento central del original** —hay más de 40— y en el actual son una forma genérica (`seleccion`).
4. **El original es una página; el actual puede ser varias.** Un formulario oficial de una hoja que salga en dos **no es la misma planilla**.
5. **El orden de lectura no coincide:** el oficial agrupa por secciones con reglas y recuadros; el actual por grupos del catálogo.

---

## 7. Riesgos

**Riesgo 1 — el catálogo es la incógnita, y es la que decide.** Sin consultar
`inscripcion_campos` no se sabe si faltan campos **o si están y sólo hay que
pintarlos**. Son dos trabajos de tamaño muy distinto: uno es de datos, el otro de
renderizado.

**Riesgo 2 — `N.º PREIMPRESO` no es un dato del aspirante.** Es del talonario. Si
no se captura en algún punto del flujo, el campo queda vacío y el formulario sale
incompleto por un motivo que no es un bug.

**Riesgo 3 — la tabla de familiares tiene 9 columnas.** En A4 vertical, 9 columnas
con nombres y apellidos completos **no caben legibles**. El oficial lo resuelve
porque es **preimpreso**: las columnas están vacías y se rellenan a mano. Un PDF
generado con datos reales **tiene que decidir** entre encoger la letra, partir la
tabla o girar la página — y ninguna de las tres es «mover coordenadas».

**Riesgo 4 — Latin-1.** El renderizador sanea a Latin-1 y sustituye por `?` lo que
no cabe (líneas 28-32). Con nombres reales de la región —`ñ`, `á`, `ü`— **cabe**,
pero un carácter fuera de rango **se pierde en silencio**. En una planilla que se
firma, un `?` en un apellido es un problema legal, no cosmético.

**Riesgo 5 — cambiar el renderizador toca al `.xlsx`.** Los dos comparten
`EntradaPlanilla`. Rediseñar la salida del PDF **sin tocar el contrato** deja el
Excel intacto; tocar el contrato **rompe las dos**.

---

## 8. Decisión arquitectónica recomendada

**Renderer específico de la planilla oficial, enchufado al mismo contrato. No adaptar el actual.**

**Por qué, técnicamente:**

1. **El actual no está «casi» — está en otra forma.** Es un renderizador de flujo dirigido por catálogo; el oficial es un formulario de posición fija. **No hay coordenadas que ajustar porque no dibuja por coordenadas.** Adaptarlo significaría meterle un segundo modo de dibujo, y un archivo con dos modos es un archivo que hace dos cosas mal.
2. **La propiedad que hace valioso al actual se perdería.** Su cabecera presume —con razón— de que «si el CFS añade un campo, la planilla impresa lo trae sin tocar este archivo». **El formulario oficial no tiene esa propiedad**: sus casillas están fijas y un campo nuevo no tiene dónde ir. **Son dos requisitos incompatibles, y forzarlos en un archivo obliga a elegir cuál se rompe.**
3. **El contrato compartido ya existe.** `EntradaPlanilla` es el punto de enchufe: un `planilla-oficial-pdf.ts` que reciba lo mismo y dibuje distinto **no toca `planilla-valores.ts`, ni el `.xlsx`, ni las rutas, ni el frontend.**
4. **El catálogo sigue mandando en el formulario.** El oficial se pinta **desde los mismos datos**; lo que cambia es la disposición, no el origen.

**Lo que NO recomiendo:** plantilla PDF con campos rellenables (*AcroForm*).
Suena a atajo y no lo es: obliga a mantener un PDF binario en el repositorio, ata
el layout a una herramienta externa, y **cualquier campo nuevo del catálogo vuelve
a no tener dónde ir**. Además el original **no es un AcroForm** —es una imagen con
texto superpuesto, 2 imágenes embebidas—, así que habría que construirlo desde
cero igualmente.

---

## 9. Acceso administrativo — **confirmado por código**

```
Aspirante → datos persistidos → PDF generado bajo demanda
Admin     → MISMA fila      → MISMO generador → PDF generado bajo demanda
```

**Las dos rutas llaman a la misma función:**

```ts
admin.get('/api/v1/inscripcion/planilla/:usuarioId/pdf', …)
  → reposDe(request).planilla.generarPdf(usuarioId)
```

**Conclusión: NO existe duplicación, y no puede existir.** No hay archivo que
duplicar: **no se guarda ningún PDF**. Todos los administradores leen la misma
fila y generan el mismo documento. **El diseño ya resuelve el problema que
planteabas, y de la forma más fuerte posible: no hay dos copias que puedan
divergir porque no hay copias.**

Guardar una copia por administrador sería **introducir** el problema que hoy no
existe.

---

## 10. Plan de implementación por fases

**Ninguna fase se ejecuta hasta cerrar §11.**

| Fase | Contenido | Puerta de salida |
|---|---|---|
| **1 · Datos** | Consultar `inscripcion_campos` y comparar contra las 38 filas de §4. Marcar cada una: existe / falta / se llama distinto | **La matriz sin ningún NO VERIFICADO** |
| **2 · Modelo** | Capturar lo que falte —empezando por **N.º PREIMPRESO**— y decidir si algún campo se parte (1er/2do nombre) o se calcula (EDAD) | Los datos del original tienen dónde vivir |
| **3 · Transformación** | `planilla-oficial-valores.ts` si el oficial necesita agrupaciones distintas del genérico | Un `EntradaOficial` con todo lo del original |
| **4 · Renderer** | `planilla-oficial-pdf.ts` — **US Letter**, posición fija, casillas, 1 página, tablas de familiares y experiencias | PDF que se imprime en el papel oficial y cuadra |
| **5 · Ruta** | `GET /api/v1/inscripcion/planilla/:id/pdf-oficial` — **al lado** de la actual, no en su lugar | Las dos salidas conviven |
| **6 · Administración** | Segundo botón en el cPanel | El admin elige formato |
| **7 · Comparación visual** | Renderizar el original a PNG y el generado a PNG, **superponer** y medir el desvío | Desvío documentado y aceptado |

**Sobre la fase 7:** la comparación visual **es automatizable** y no se ha hecho
nunca. Con PyMuPDF —ya instalado y usado en esta auditoría— se renderizan las dos
páginas a PNG y se comparan. **Es la única forma de responder «¿se parece?» con un
número en vez de con una opinión.**

---

## 11. Estrategia de pruebas

| Caso | Qué prueba |
|---|---|
| Todos los campos completos | Que ningún campo oficial queda vacío |
| Opcionales vacíos | Que un campo vacío **no desplace** los siguientes (en posición fija, es el fallo clásico) |
| **Varios familiares** | Que la tabla de 9 columnas **no se sale** ni se solapa |
| **Varias misiones** | Que 20 casillas con «desde cuándo» caben y se leen |
| Textos largos | Dirección, especialidad, organizaciones |
| Educación + experiencia | Las dos tablas a la vez |
| Descarga del aspirante | Misma ficha, mismo resultado |
| Descarga desde el cPanel | **Byte a byte igual** que la del aspirante |
| Comparación visual | Desvío medido contra el original renderizado |

**La prueba que más vale:** *la descarga del admin y la del aspirante deben producir
el mismo documento*. Hoy es así por construcción —misma función, misma fila— y
**debe seguir siéndolo después del cambio.** Si un renderizador nuevo guardara
algo en algún sitio, esa igualdad se rompería y sería la primera señal.

---

## 12. RECONCILIACIÓN (2026-10-05) — corrige §2, §4, §5 y §7

### 12.1 Un error mío, con nombre y causa

Afirmé que **`numero_preimpreso` no tiene dónde vivir**. **Es falso.** Está en
`supabase/migrations/202609240001_mod4_catalogo_inscripcion.sql`, con su
descripción: *«Número impreso en la planilla física. Sirve para emparejar el papel
con el registro digital.»*

**La causa del error, y es la que hay que no repetir:** lo deduje de su **ausencia
en `planilla-pdf.ts`**. Pero la ausencia en el renderer significa **«no se está
renderizando aquí»**, no **«el sistema no posee el dato»**. Inferir lo segundo de
lo primero es exactamente el error que esta auditoría existía para evitar.

### 12.2 La reconciliación de los 44 campos — cuadra exacta

```
38 campos de la planilla física  +  6 campos del sistema  =  44   ✓
```

**Los 38** — leídos de los `codigo` de la migración:

`numero_preimpreso` · `primer_nombre` · `segundo_nombre` · `primer_apellido` ·
`segundo_apellido` · `cedula` · `nacionalidad` · `fecha_nac` · `sexo` ·
`estado_civil` · `pueblo_indigena` · `pueblo_indigena_cual` · `discapacidad` ·
`tipo_discapacidad` · `deporte` · `deporte_desde` · `actividad_cultural` ·
`actividad_cultural_desde` · `organizacion_social` · `organizacion_social_desde` ·
`estado` · `municipio` · `parroquia` · `comunidad` · `direccion` · `telefono` ·
`telefono_fijo` · `email` · `twitter` · `facebook` · `familiares` · `misiones` ·
`nivel_educativo` · `nivel_avance` · `ultimo_anio` · `especialidad` ·
`otras_formaciones` · `experiencias`

**Los 6 del sistema:** `numero_identidad_tutor` · `nombre_tutor` ·
`parentesco_tutor` · `telefono_tutor` · `correo_tutor` · `curso_seleccionado`

**La diferencia entre 38 y 44 queda explicada al 100 %**, y sin residuo: no hay
campos «perdidos» ni agrupados. **Mi matriz de 38 filas era correcta en el número**
y errada en la conclusión: los 38 existen en el catálogo.

### 12.3 La cabecera — derivable, no capturada

`FECHA`, `PROYECTO`, `ESPACIO INTEGRAL SOCIALISTA` y `HORARIO` **no están en los
`codigo` del catálogo**, y eso **confirma** lo que dice la migración: no los
introduce el aspirante, se derivan de sección, programa, lapso y horario.

**Clasificación correcta:** *«dato derivable definido arquitectónicamente»* — que
**no es lo mismo** que «campo faltante del formulario». El catálogo sí tiene la
tabla `programas`, así que la fuente de la derivación existe; **lo que falta por
verificar es la función que la hace** (§12.5).

### 12.4 Familiares y misiones

`familiares` y `misiones` son **campos del catálogo con tipo `tabla` y `rejilla`**.
Los 20 elementos de misiones y las columnas de familiares **viven en el JSON del
catálogo**, no en el PDF ni en el renderer — así que contarlos «desde el PDF»,
como hice en §7, medía el artefacto equivocado.

### 12.5 Lo que sigue sin verificar — y ahora es una lista corta

| Pregunta | Cómo se cierra |
|---|---|
| ¿Existe la función que deriva FECHA/PROYECTO/EIS/HORARIO? | Buscar en el código por sección, oferta, lapso y horario |
| ¿Cuántas columnas tiene `familiares` en el JSON? | Leer el JSON del catálogo en la migración |
| ¿Los 20 elementos de `misiones` coinciden con el PDF? | Comparar el JSON con el texto extraído del original |
| ¿`planilla-valores.ts` recupera `tabla` y `rejilla`? | Leer sus 187 líneas |

---

## 13. Veredicto

# APTO PARA DISEÑO DEL RENDERER

**Los datos están.** El catálogo de 44 campos cubre **los 38 de la planilla física
y los 6 del sistema**, con `numero_preimpreso` incluido. **El problema restante es
de representación, no de modelo.**

**Respuestas a las seis preguntas:**

| | Pregunta | Respuesta |
|---|---|---|
| **A** | ¿Tenemos los datos? | **SÍ** — 38/38 de la física, verificado contra los `codigo` de la migración |
| **B** | ¿Las derivaciones? | **PARCIAL** — definidas arquitectónicamente; la función que las calcula **NO VERIFICADA** |
| **C** | ¿Es sólo representación? | **SÍ**, salvo la derivación de la cabecera |
| **D** | ¿Hay que tocar el modelo? | **NO** — ningún campo oficial obliga a cambiar el esquema |
| **E** | ¿`numero_preimpreso` de extremo a extremo? | **PARCIAL** — capturado y persistido ✓; renderizado en PDF/XLSX ✓; **falta confirmar la captura en Flutter** |
| **F** | ¿Admin y aspirante, mismo documento? | **SÍ**, por construcción — misma función, misma fila, sin archivo guardado |

**Lo que cambió respecto del veredicto anterior:** el bloqueo **no eran los datos**,
era **mi método**. Dejé 36 filas sin verificar porque esperaba consultar Supabase,
cuando **el catálogo estaba en una migración del propio repositorio**. Una
auditoría de repositorio que sólo mira el renderer y la base viva se pierde
justamente la capa que define las cosas.

---

## 14. Veredicto anterior — conservado para trazabilidad

# NO APTO PARA IMPLEMENTACIÓN — FALTAN DATOS/EVIDENCIA

> **SUPERADO por §13.** Se conserva porque el error tiene valor: la conclusión era
> falsa y la causa fue inferir «el dato no existe» desde «no se renderiza aquí».

**No por el PDF actual, que se genera correctamente** — y precisamente por eso lo
digo: el criterio no es «genera», es **trazabilidad completa desde el formulario
oficial hasta los datos persistidos**.

**Lo que falta, exactamente:**

1. **Consultar `inscripcion_campos`.** Sin ella, **36 de las 38 filas de la matriz
   están sin verificar**. Es la incógnita que decide el tamaño del trabajo: si los
   campos están, es un renderizador; si no están, son datos **más** un renderizador.
2. **Decidir qué es `N.º PREIMPRESO`** y dónde se captura. No es un dato del
   aspirante y hoy no tiene dónde vivir.
3. **Confirmar el tamaño de papel objetivo.** El original es US Letter; el
   renderizador actual es A4. **¿Se imprime en papel oficial o en A4?** Cambia el
   diseño entero.

**Lo que sí queda establecido y no hace falta volver a medir:**

- Los dos PDFs de la carpeta son **idénticos** (mismo SHA-256 `eccb284a2bb0883a`).
- El original es **1 página, 612×792 pt, con texto extraíble y 2 imágenes**.
- Tiene **38 filas de campos** en la matriz, con **más de 40 casillas**.
- El renderizador actual es **genérico y dirigido por catálogo**, **A4**, y **no
  puede evolucionar por ajustes incrementales** hacia el formulario oficial.
- **No hay duplicación de documentos, ni puede haberla**: no se guarda ningún PDF.

**En cuanto se consulte el catálogo y se respondan las tres preguntas, esta
auditoría pasa a APTO y el plan de §10 arranca por la fase 2.**
