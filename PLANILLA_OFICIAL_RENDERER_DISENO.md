# Diseño del renderer de la Planilla Oficial INCES

> **Fecha:** 2026-10-05 · **Fase:** DISEÑO TÉCNICO · **Implementación: NO INICIADA**
>
> Todo lo que aquí se afirma está medido. Lo que no, va marcado **NO VERIFICADO**.
> Este documento **no describe código escrito**: describe el código que hay que
> escribir.

---

## 1. Arquitectura definitiva

```
aspirants.datos_planilla  (jsonb)
        ↓
planilla-oficial-valores.ts        ← adaptador semántico
        ↓
PlanillaOficialData                ← contrato con nombre y posición
        ↓
planilla-oficial-pdf.ts            ← sólo dibuja
```

**`planilla-oficial-pdf.ts` NO conoce:** etiquetas del catálogo, códigos de campo,
la forma del JSONB, reglas de fallback ni lógica de negocio. **Recibe
`PlanillaOficialData` y dibuja.**

**Corrección de una contradicción del documento anterior:** §3 de
`AUDITORIA_PLANILLA.md` decía que el renderer podía enchufarse **directamente** a
`EntradaPlanilla`. **Es incorrecto** y §15.6 lo corrige. `EntradaPlanilla` es una
**lista plana** de `{campo, etiqueta, valor}`; un renderer de posición fija
necesita **pedir** `primerNombre`, no recorrer una lista. **El adaptador es
obligatorio**, y es además donde debe vivir toda decisión semántica.

---

## 2. `mision_ribaras` — resuelto

**Evidencia:** `lib/models/aspirante_model.dart`, línea 178:

> «**`mision_ribaras` ya no se envía**, y es a propósito. El catálogo pide la…»

```
misiones        = fuente efectiva del flujo nuevo
mision_ribaras  = campo legacy conservado por compatibilidad
```

Sigue existiendo en el modelo (líneas 115 y 159) para leer fichas antiguas, **pero
no se emite**. **El renderer oficial lee `misiones` y sólo `misiones`.**

---

## 3. `PlanillaOficialData` — contrato propuesto

```ts
/** Cabecera: NO sale de datos_planilla. Ver §6. */
export interface CabeceraOficial {
  fecha: string | null;
  numeroPreimpreso: string | null;
  proyecto: string | null;
  espacioIntegralSocialista: string | null;
  horario: string | null;
}

export interface UbicacionOficial {
  estado: string | null;
  municipio: string | null;
  parroquia: string | null;
  comunidad: string | null;
  direccion: string | null;
  telefonoCelular: string | null;
  telefonoFijo: string | null;
  email: string | null;
  twitter: string | null;
  facebook: string | null;
}

export interface FamiliarOficial {
  cedula: string | null;
  nombres: string | null;      // el papel pide 1er. y 2do. — ver §10
  apellidos: string | null;    // ídem
  fechaNac: string | null;
  genero: 'F' | 'M' | null;    // tipificado en el catálogo
  parentesco: string | null;
  diversidadFuncional: string | null;  // TEXTO LIBRE en el modelo
  estadoCivil: string | null;          // TEXTO LIBRE en el modelo
}

export interface MisionOficial {
  /** `valor` del catálogo: RIBAS, MERCAL, … */
  valor: string;
  etiqueta: string;
  marcada: boolean;
  desde: string | null;
}

export interface FormacionOficial {
  nivelEducativo: string | null;   // etiqueta ya traducida
  nivelAvance: string | null;
  ultimoAnio: string | null;
  especialidad: string | null;
}

export interface OtraFormacionOficial { descripcion: string | null; }
export interface ExperienciaOficial {
  area: string | null;
  meses: string | null;
  portafolio: boolean | null;
  enlace: string | null;
}

export interface PlanillaOficialData {
  cabecera: CabeceraOficial;
  identidad: {
    primerNombre: string | null;
    segundoNombre: string | null;
    primerApellido: string | null;
    segundoApellido: string | null;
    cedula: string | null;
    nacionalidad: string | null;
  };
  nacimiento: { fecha: string | null; edad: number | null };
  sexo: 'F' | 'M' | null;
  estadoCivil: string | null;
  puebloIndigena: { pertenece: boolean | null; cual: string | null };
  discapacidad: { marcadas: string[]; ninguna: boolean };
  practicas: {
    deporte: { valor: string | null; desde: string | null };
    cultural: { valor: string | null; desde: string | null };
    organizacion: { valor: string | null; desde: string | null };
  };
  ubicacion: UbicacionOficial;
  familiares: FamiliarOficial[];
  misiones: MisionOficial[];          // SIEMPRE los 20, con `marcada`
  formacion: FormacionOficial;
  otrasFormaciones: OtraFormacionOficial[];
  experiencias: ExperienciaOficial[];
}

/** Los 6 campos del sistema. NO van al formulario físico. */
export interface CamposDeSistema {
  numeroIdentidadTutor: string | null;
  nombreTutor: string | null;
  parentescoTutor: string | null;
  telefonoTutor: string | null;
  correoTutor: string | null;
  cursoSeleccionado: string | null;
}
```

**Decisión de diseño:** los 6 campos de sistema **no están dentro** de
`PlanillaOficialData`. Van aparte porque **no tienen casilla en el papel**; meterlos
obligaría al renderer a decidir cuáles ignorar, que es exactamente la decisión
semántica que no debe tomar.

---

## 4. El adaptador

```ts
construirPlanillaOficial(
  entrada: EntradaPlanilla,
  contexto: ContextoPlanillaOficial,
): PlanillaOficialData
```

| Origen del valor | Campos |
|---|---|
| **Directo de `datos_planilla`** | identidad, nacimiento, ubicación, formación, otras formaciones, experiencias |
| **De `identidad` (compuesto)** | `cedula` + `nacionalidad` — hoy vienen juntos en un campo |
| **Requiere traducir opciones** | `nivel_educativo`, `nivel_avance` (valor → etiqueta del catálogo), `genero` F/M |
| **Requiere componer** | `edad` (de `fecha_nac`), `discapacidad.ninguna` (si el array está vacío), `puebloIndigena` (booleano + `_cual`) |
| **Derivados** | los 4 de la cabecera (§6) — **vienen del `contexto`, no de `datos_planilla`** |
| **Puede quedar vacío** | todo lo no obligatorio del catálogo |
| **Error si falta** | `cedula`, `primer_nombre`, `primer_apellido` — sin ellos **no hay planilla que imprimir** |

**`ContextoPlanillaOficial`** lleva lo que no está en `datos_planilla`:

```ts
export interface ContextoPlanillaOficial {
  cabecera: CabeceraOficial;   // ya resuelta por §6
  catalogo: CampoInscripcion[]; // para traducir valores a etiquetas
}
```

**El adaptador es puro:** entra `EntradaPlanilla` + contexto, sale
`PlanillaOficialData`. **Sin HTTP, sin Supabase, sin RLS.** Se prueba sin generar
un PDF — y eso es lo que vuelve verificable todo lo demás.

---

## 5. Familiares — cómo se imprime

**El catálogo tiene 8 columnas y el papel tiene 8 columnas físicas — medido, no
estimado** (§14.4). **Aquí se dijo «9 casillas» y era falso.** No hay separación
que inventar:

| Casilla del papel | Qué se imprime |
|---|---|
| 1er. y 2do. NOMBRES | **el contenido completo de `nombres`** en una sola casilla |
| 1er. y 2do. APELLIDOS | **el contenido completo de `apellidos`** |
| DIVERSIDAD FUNCIONAL | **el texto libre tal cual** — el papel tiene 6 casillas tipificadas, el modelo no |
| ESTADO CIVIL | **el texto libre tal cual** — el papel tiene 5 casillas, el modelo no |

**Declaración explícita:** `diversidad_funcional` y `estado_civil` **son texto libre
en el modelo aunque el papel tenga casillas**. El renderer **imprime el texto**;
**no marca casillas**, porque el dato no dice cuál. **El modelo no se cambia en
esta fase.**

---

## 6. Cabecera — derivación

**No se guardan en `datos_planilla`.** Se derivan:

```
usuario → inscripción → sección → programa → lapso → horario → espacio
```

| Campo | Fuente propuesta |
|---|---|
| FECHA | fecha de la inscripción, o del lapso activo |
| PROYECTO | programa de la sección |
| ESPACIO INTEGRAL SOCIALISTA | espacio/ambiente de la sección |
| HORARIO | horario de la sección |

**Función propuesta (no implementada):**

```ts
resolverCabeceraOficial(usuarioId: string): Promise<CabeceraOficial>
```

**Estado: BLOQUEO PARCIAL.** Las tablas existen —`seccion_id` está en el dominio
(`dominio/tipos.ts`, `http/esquemas.ts`, `rutas/aula.ts`)— **pero no he verificado
que exista la composición hasta los cuatro valores.** Sin ella el renderer
recibiría el encabezado en blanco, y **un formulario con el encabezado vacío no es
la planilla oficial.**

---

## 7. `numero_preimpreso`

**Medido:** `grep -rn "numero_preimpreso" lib/` devuelve **una sola aparición**, y es
en `lib/models/exportacion_hacer.dart:73` como **nombre de columna de HACER**
(`planilla_numero_preimpreso`). **No hay widget, ni campo de formulario, ni nada en
la UI que lo capture.**

```
CAPTURA DE N.º PREIMPRESO: NO VERIFICADA
```

**Y no la invento.** Lo que sí dice la evidencia: el catálogo lo pone en el grupo
**`Cabecera`**, no en `Datos personales`; y el papel lo sitúa en la **zona
preimpresa**, junto a FECHA y PROYECTO. **Eso apunta a «introducido al imprimir» o
«asociado después al ejemplar físico»**, y **no** a «lo teclea el aspirante» —
pero es **inferencia desde la agrupación, no una regla documentada.**

**Consecuencia para el diseño:** el contrato lo admite como **`string | null`** y el
renderer **debe saber dibujar la casilla vacía**. Es el caso normal hasta que se
decida quién lo captura.

---

## 8. Mapa físico — especificación

```
Página:  612 × 792 pt   ·   portrait   ·   1 página
```

**Regla de oro:** si el contenido no cabe en **una** página, **no se añade una
segunda** — se degrada el contenido (recorte con elipsis o reducción de fuente en
la zona afectada). **Una planilla oficial de dos hojas no es la planilla oficial.**

### Zonas (fracciones del alto útil, no medidas absolutas)

| Zona | Banda vertical | Contenido |
|---|---|---|
| Encabezado | 0–8 % | FECHA · N.º PREIMPRESO · PROYECTO · EIS · HORARIO |
| Datos personales | 8–30 % | 4 nombres, CI/pasaporte, nacionalidad, nacimiento, edad, género, estado civil, pueblo indígena, diversidad funcional, prácticas |
| Ubicación y contacto | 30–44 % | estado → facebook |
| Familiares | 44–58 % | tabla de 8 columnas |
| Misiones | 58–74 % | 20 casillas en 5 columnas × 4 filas + «desde» |
| Formación | 74–86 % | nivel, avance, último año, especialidad, otras formaciones |
| Experiencias | 86–100 % | tabla de 4 columnas |

**Cada campo se especifica con:**

```ts
interface ZonaCampo {
  x: number; y: number; width: number; height: number;
  fontSize: number; maxLines: number;
  alignment: 'left' | 'center' | 'right';
  overflowRule: 'elipsis' | 'encoger' | 'recortar';
}
interface ZonaCasilla { x: number; y: number; size: number; }
```

**NO VERIFICADO:** las coordenadas exactas de cada campo. **Requieren medir el PDF
original** — y eso es automatizable: PyMuPDF puede dar la posición de cada bloque de
texto del original (`page.get_text("dict")` devuelve `bbox` por línea). **Ese es el
paso previo a escribir el renderer, y es una corrida, no una estimación.**

---

## 9. Fuentes y Unicode

**El renderizador actual sanea a Latin-1** y sustituye por `?` lo que no cabe
(`planilla-pdf.ts`, líneas 28-32), porque usa Helvetica estándar con WinAnsi.

**Para el renderer oficial NO se copia esa limitación sin justificarla.** En una
planilla que se firma, **un `?` en un apellido es un problema legal, no cosmético**.

**Decisión:** **fuente Unicode embebida** (`pdf-lib` acepta `fontkit` +
`registerFontkit`). Cuesta unos KB en el PDF y **elimina la clase entera de fallo**.
El alfabeto español —`ñ á é í ó ú ü ¿ ¡`— **cabe en Latin-1**, así que el riesgo real
es un nombre con un carácter fuera de rango, poco frecuente y **silencioso**.

**Estrategia:** embeber una fuente Unicode y **no sanear**. Si el tamaño del PDF
importa algún día, se mide — pero **no se degrada la integridad de un dato personal
para ahorrar KB**.

---

## 10. Misiones — mapeo

**Se usa el catálogo, no una lista duplicada en el renderer.** El adaptador lee
`items` del JSON del catálogo (**20**, verificado) y produce **siempre 20
`MisionOficial`**, con `marcada: false` para las no seleccionadas.

**El renderer dibuja las 20 casillas y marca las que tienen `marcada: true`.** Si
mañana el INCES añade una misión, **se añade al catálogo y el renderer la dibuja sin
tocarse** — que es la única forma de que esto no envejezca.

**Cada casilla lleva su «desde cuándo»** (`etiqueta_desde: "Desde"`), que se imprime
**sólo si `marcada`** — una fecha en una misión no marcada no significa nada.

---

## 11. Reglas especiales

| Caso | Regla |
|---|---|
| Nombres/apellidos largos | `overflowRule: 'encoger'` con suelo de 6 pt; por debajo, elipsis |
| Fechas | formato fijo `dd/mm/aaaa`, en las tres subcasillas DÍA/MES/AÑO |
| Sexo | marcar **F** o **M** — el catálogo los tipifica |
| Estado civil | **texto libre**; las 5 casillas del papel **no se marcan** (§5) |
| Pueblo indígena | casilla SI/NO + `cual` en la línea contigua |
| Diversidad funcional | **texto libre**; las 6 casillas **no se marcan** (§5) |
| Familiares | tabla; **máximo de filas = alto de la banda ÷ alto de fila**; si sobran, **se corta con aviso, no se añade página** |
| Misiones | 20 casillas fijas, 5×4; «desde» sólo si marcada |
| Otras formaciones / experiencias | ídem familiares |
| Enlaces | si exceden el ancho, **elipsis al final** — nunca partir una URL a mitad |
| Valores vacíos | **la casilla se dibuja vacía**, nunca se omite la etiqueta |

---

## 12. Contrato de pruebas

El adaptador se prueba **sin PDF**:

| Caso | Qué prueba |
|---|---|
| Todos los campos | que ningún `PlanillaOficialData` sale `null` donde hay dato |
| Opcionales vacíos | que **no desplazan** los siguientes |
| Varios familiares | que la lista sale completa y ordenada |
| Varias misiones | que salen **las 20** con las marcadas correctas |
| Textos largos | que el adaptador **no trunca** — truncar es del renderer |
| `mision_ribaras` presente | que **se ignora** y manda `misiones` |

---

## 13. Estado del diseño

```
CONTRATO DE DATOS:        definido
ADAPTADOR:                definido conceptualmente
CABECERA:                 BLOQUEO PARCIAL — falta verificar la composición sección→programa→lapso→horario
N.º PREIMPRESO:           BLOQUEO EXPLÍCITO — sin UI de captura (medido)
LAYOUT:                   especificado en bandas — coordenadas exactas NO VERIFICADAS
FUENTES:                  especificadas — Unicode embebida, sin saneo Latin-1
CASILLAS:                 especificadas
FAMILIARES:               especificados — 8 columnas, 2 en texto libre declarado
MISIONES:                 especificadas — desde el catálogo, 20 fijas
UNICODE:                  especificado
IMPLEMENTACIÓN:           NO INICIADA
```

## 14. MEDICIÓN FÍSICA REAL (2026-10-05) — cierra el bloqueo 1

Medido con PyMuPDF sobre el PDF oficial. **Coordenadas reales, no porcentajes.**

### 14.1 Geometría — confirmada por medición

```
width  = 612.0 pt
height = 792.0 pt
pages  = 1
rotation = 0
mediabox = cropbox = (0, 0, 612, 792)   → sin recorte ni sangrado
```

### 14.2 Sistema de coordenadas

```
origen = esquina SUPERIOR izquierda   (el de PyMuPDF)
x = izquierda → derecha
y = arriba → abajo
unidad = puntos PDF
```

**`pdf-lib` usa origen INFERIOR izquierdo.** Conversión obligatoria, y **no se
mezclan los dos sistemas en el mismo archivo**:

```text
y_pdf_lib = 792 − y_top − height
```

### 14.3 Mapa físico — coordenadas medidas

**121 líneas de texto** extraídas con `get_text("dict")`. Las cajas que el renderer
tendrá que llenar:

| Zona | Campo | x | y (top) | Ancho aprox. | Tipo |
|---|---|---|---|---|---|
| Cabecera | FECHA: | 221,4 | 75,8 | ~160 | texto |
| Cabecera | N° PREIMPRESO: | 331,2 | 75,8 | ~250 | texto |
| Cabecera | PROYECTO: | 221,4 | 102,1 | ~360 | texto |
| Cabecera | ESPACIO INTEGRAL SOCIALISTA: | 31,2 | 126,7 | ~290 | texto |
| Cabecera | HORARIO: | 331,2 | 126,7 | ~250 | texto |
| Identidad | 1er. NOMBRE: | 31,2 | 179,6 | ~100 | texto |
| Identidad | 2DO. NOMBRE: | 140,8 | 179,6 | ~100 | texto |
| Identidad | 1ER. APELLIDO: | 250,3 | 179,6 | ~100 | texto |
| Identidad | 2DO. APELLIDO: | 359,9 | 179,6 | ~100 | texto |
| Identidad | N° de CI / PASAPORTE: | 469,4 | 179,6 | ~110 | texto |
| Personal | NACIONALIDAD | 74,7 | 215,1 | ~95 | texto |
| Personal | F. DE NACIMIENTO (DIA/MES/AÑO) | 176,0 | 228,0 | 3 subcajas | 3 casillas |
| Personal | EDAD (AÑOS) | 277,1 | 234,5 | ~40 | número |
| Personal | GENERO | 303,3 | 233,2 | ~40 | 2 casillas |
| Personal | ESTADO CIVIL | 351,2 | 227,8 | ~130 | 5 casillas |
| Personal | PUEBLO INDIGENA | 507,3 | 227,8 | ~55 | 2 casillas + «INDIQUE CUAL» |
| Personal | DIVERSIDAD FUNCIONAL | 31,2 | 280,5 | 2 bloques | 6 casillas |
| Personal | DEPORTES | 166,7 | 256,8 | ~120 | texto + DESDE |
| Personal | CULTURALES | 304,0 | 256,8 | ~130 | texto + DESDE |
| Personal | ORGANIZACIONES | 445,3 | 256,8 | ~135 | texto + DESDE |
| Ubicación | ESTADO / MUNICIPIO / PARROQUIA / COMUNIDAD | 31,2 / 142,3 / 278,3 / 447,6 | 357,1 | ~100 c/u | 4 cajas |
| Contacto | DIRECCION DE HABITACION | 31,2 | 382,6 | ~390 | texto |
| Contacto | TELEFONO CELULAR / FIJO | 429,2 / 506,7 | 382,6 | ~70 c/u | texto |
| Contacto | CORREO ELECTRONICO | 31,2 | 407,1 | ~250 | texto |
| Contacto | Twiter / Facebook | 286,2 / 420,2 | 407,1 | ~120 c/u | texto |
| Formación | NIVEL EDUCATIVO | 31,2 | 643,1 | ~125 | texto |
| Formación | ESTADO DEL AVANCE | 160,2 | 643,1 | ~135 | 3 casillas |
| Formación | ULTIMO AÑO / ESPECIALIDAD | 312,2 / 447,6 | 643,1 | ~70 c/u | texto |
| Experiencias | AREA / TIEMPO / PORTAFOLIO / ENLACE | 31,2 / 170,0 / 308,8 / 447,6 | 729,8 | tabla | tabla |

**Dos imágenes embebidas**, medidas: `(8, 17)-(108, 57)` —el emblema— y
`(119, 20)-(586, 57)` —la banda del encabezado—. **Se conservan, no se redibujan.**

### 14.4 Familiares — **8 columnas físicas, 8 en el catálogo**

Medido en la cabecera de la tabla (y=449,5):

```
CEDULA DE IDENTIDAD N°  ·  1er. Y 2do. NOMBRES  ·  1er. Y 2do. APELLIDOS  ·
FECHA DE NACIMIENTO  ·  GENERO  ·  PARENTESCO  ·  DIVERSIDAD FUNCIONAL  ·  ESTADO CIVIL
```

**columnas físicas = 8** — **coincide exactamente** con las 8 del catálogo.

**Mi afirmación anterior de «9 columnas» era falsa**, y ahora está refutada por
medición, no por razonamiento.

**La diferencia real no es el número, es el contenido:** el papel rotula
`1er. Y 2do. NOMBRES` (una casilla que espera los dos) y el catálogo guarda
`nombres` (un solo campo). **Coinciden en la práctica**: el papel pide ambos en una
casilla y el modelo los guarda juntos. **No hay que partir nada.**

### 14.5 Misiones — 20 casillas en 5 columnas × 4 filas

Posiciones medidas de las casillas (x del `□`):

| Columna | x casilla | x «desde» | Filas (y) |
|---|---|---|---|
| 1 | 31,2 | 95,2 | 567,7 · 581,7 · 595,6 · 609,6 |
| 2 | 142,3 | 202,1 | 567,7 · 581,7 · 595,6 · 609,6 |
| 3 | 253,3 | 321,7 | 567,7 · 581,7 · 595,6 · 609,6 |
| 4 | 364,4 | 432,7 | 567,7 · 581,7 · 595,6 · 609,6 |
| 5 | 475,4 | 541,2 | 567,7 · 581,7 · 595,6 · 609,6 |

**Mapeo catálogo → posición física** (el orden del papel coincide con el del catálogo,
verificado uno a uno):

```
col1: RIBAS · MERCAL · MADRES DEL BARRIO · HABITAT
col2: PIAR · NEGRA HIPOLITA · BARRIO A DENTRO · MIRANDA
col3: IDENTIDAD · CASA DE ALIMENTACION · GUAICAIPURO · ROBINSON I Y II
col4: HIJOS DE VZLA. · SUCRE · VUELVAN CARAS · VUELVAN CARAS JOVENES
col5: G. M. VIVIENDA VZLA. · G.M. AGROVENEZUELA · G.M.SABER Y TRABAJO · NINGUNA
```

**20/20, en el mismo orden que el catálogo.** El «desde» es una línea de guiones
bajos a la derecha de cada columna, **no una casilla** — el renderer imprime el
valor sobre esa línea.

```
CHECKBOX_MARK_STYLE = TBD
```

**El original usa `□` vacías** y no hay ningún ejemplar relleno en el PDF, así que
**no se puede determinar del documento si se marca con X, con check o rellenando**.
**No se decide por intuición.**

### 14.6 Familiares y misiones — el mapeo sale del catálogo

**El renderer NO hardcodea las 20 misiones ni las 8 columnas.** Las recibe en
`PlanillaOficialData` —el adaptador las construye desde el JSON del catálogo— y **las
posiciones son constantes medidas en §14.4 y §14.5.** Si el INCES añade una misión
21, **hay que decidir dónde va**: el papel tiene sitio para 20 y no más.

---

## 15. BLOQUE 2 — Derivación de la cabecera: **fuentes conocidas, composición pendiente**

Buscado en el código real. **Las fuentes existen:**

| Campo | Fuente | Evidencia | Estado |
|---|---|---|---|
| **FECHA** | lapso / inscripción | `dominio/tipos.ts` (lapso), rutas de secciones | **fuente identificada — composición NO implementada** |
| **PROYECTO** | programa de la sección | `http/rutas/secciones.ts` | **fuente identificada — composición NO implementada** |
| **ESPACIO INTEGRAL SOCIALISTA** | espacio del centro | `dominio/tipos.ts:274` — *«Un espacio del centro: aula, taller o zona»*; `tipos.ts:251` — *«las tres formas que puede tener un espacio, **derivadas** de dos columnas»* | **fuente identificada — composición NO implementada** |
| **HORARIO** | cuadrante de la sección | `dominio/reglas-cuadrante.ts`; `tipos.ts:411` — *«El horario del llamante»* | **fuente identificada — composición NO implementada** |

**Conclusión: `fuente conocida + composición pendiente`** — que **no es
`fuente desconocida`**. Eso significa que **no bloquea el renderer**: es **una pieza
previa**, y el renderer puede construirse contra el contrato mientras la función no
exista, recibiendo `null` y dibujando la casilla vacía.

**Función propuesta (NO implementada):**

```ts
resolverCabeceraOficial(usuarioId: string): Promise<CabeceraOficial>
```

**Entradas:** `usuarioId` → inscripción → sección → programa, espacio, lapso,
horario. **Salida:** `CabeceraOficial`. **Criterio de `FECHA`, sin decidir por
intuición:** hay tres candidatas —fecha de inscripción, fecha de generación del PDF,
fecha del lapso— y **el documento no lo determina**. **Queda como pregunta para el
autor**, y el contrato lo admite como `string | null`.

---

## 16. N.º PREIMPRESO — estado documentado, sin inventar

```
modelo/catálogo  → EXISTE  (migración 202609240001, línea 475, grupo `Cabecera`)
Flutter          → NO SE ENCONTRÓ CAPTURA  (`grep -rn "numero_preimpreso" lib/`
                   devuelve 1 sola aparición: `exportacion_hacer.dart:73`, como
                   nombre de columna de HACER)
fuente de asignación → PENDIENTE DE DEFINICIÓN
```

```
CAPTURA DE N.º PREIMPRESO: NO VERIFICADA
```

**No se crea UI, no se añade columna, no se cambia migración, no se asume que lo
introduce el administrador, y no se asume que el renderer deba generarlo.**
El contrato lo admite como `string | null` y **el renderer dibuja la casilla vacía**,
que es el caso normal hasta que se decida.

---

## 17. Criterio de salida — actualizado

```
GEOMETRÍA:        CERRADA    — 612×792 pt, 1 página, medido
LAYOUT:           MEDIDO     — 121 líneas con bbox real
FAMILIARES:       MEDIDOS    — 8 físicas = 8 catálogo
MISIONES:         MEDIDAS    — 20 en 5×4, posiciones reales
CABECERA:         TRAZADA    — fuente conocida, composición pendiente
N.º PREIMPRESO:   DOCUMENTADO — captura no verificada, sin inventar
UNICODE:          ESPECIFICADO — fuente embebida, sin saneo Latin-1
IMPLEMENTACIÓN:   NO INICIADA
```

# APTO PARA IMPLEMENTACIÓN DEL ADAPTADOR Y RENDERER

**El bloqueo 1 queda cerrado por medición.** El bloqueo 2 **no era un bloqueo**:
la fuente existe y lo que falta es una pieza de composición, que **puede construirse
después del renderer sin bloquearlo** — el contrato ya la admite como `null`.

**Lo que sí queda como decisión abierta, y no es técnica:**

1. **`CHECKBOX_MARK_STYLE`** — el original usa `□` vacías y no hay ejemplar relleno; **el símbolo no se puede determinar del documento**.
2. **Qué fecha es `FECHA`** — tres candidatas, el documento no decide.
3. **Quién captura el N.º PREIMPRESO** — la evidencia apunta a la zona preimpresa, no al aspirante, pero **es inferencia**.
4. **Qué pasa si una misión 21 aparece** — el papel tiene sitio para 20 y no más.

---

## 19. CORRECCIONES (2026-10-05) — antes de implementar

### 19.1 Familiares: **8 = 8**, sin residuo

**Corregido en todo el documento.** El catálogo tiene **8 columnas** y el papel tiene
**8 columnas físicas**, medido en §14.4. **La afirmación de «9 casillas» era falsa y
queda eliminada como estado vigente.** Donde aparece, aparece **marcada como
refutada**, no como hecho.

### 19.2 `correoTutor`

Corregido: era `correo Tutor` (con espacio) en el contrato. **Un identificador con
espacio no compila** — era un error de transcripción, no de diseño.

### 19.3 `sexo` — incompatibilidad declarada, **sin conversión silenciosa**

**El catálogo admite `Otro`; el papel sólo tiene dos casillas: `□ F` y `□ M`.**

```ts
sexo: 'F' | 'M' | null;
```

**Comportamiento ante `OTRO`: DECISIÓN PENDIENTE.** El renderer **no convierte**,
no elige la casilla más parecida y no omite el dato. **Con `OTRO`, ninguna casilla
se marca** y el valor se imprime **junto a las casillas**, en el espacio libre a la
derecha de `□ F □ M` — de forma que **el dato no se pierde y no se falsea**.

**Esto no es una solución: es la ausencia de una decisión.** Las salidas reales
—añadir una tercera casilla al papel, prohibir `Otro` en el formulario, o aceptar
que la planilla impresa no lo represente— **son decisiones de negocio**, y ninguna
se toma aquí. **Lo que el diseño garantiza es que `OTRO` no se convierta en `F` ni
en `M` por descuido.**

### 19.4 **Geometría de página ≠ rectángulos de inserción** — la corrección de fondo

**Este es el error más grave que tenía el documento, y estaba en §14.3.**

Los `bbox` de §14.3 son **los rectángulos de las ETIQUETAS** —el texto «1er.
NOMBRE:»—, **no las cajas donde va el valor**. Poner el valor en el bbox de la
etiqueta **imprimiría el nombre encima del rótulo**.

```
GEOMETRÍA DE PÁGINA:        CERRADA  — 612×792, 1 página  ✅
RECTÁNGULOS DE INSERCIÓN:   PENDIENTES DE MEDIR  ⚠️
```

**Y hay un hallazgo que cambia el diseño del renderer:**

```
rectangulos totales en el PDF:            7
rectangulos pequeños (<=14 pt, casillas): 0     ← NINGUNO
lineas horizontales:                      2155
```

**Las casillas `□` NO son rectángulos dibujados: son GLIFOS DE TEXTO** (U+25A1)
dentro del flujo. Por eso `get_drawings()` no devuelve ni un rectángulo pequeño.

**Consecuencias directas:**

1. **El renderer no «dibuja casillas»: imprime el glifo `□`** en la posición que le
   da el texto, **o dibuja su propia casilla encima**. Son dos estrategias distintas
   y **hay que elegir una** — con la primera, el aspecto depende de la fuente.
2. **Las 2155 líneas horizontales SÍ son las de escritura.** Ejemplo medido en la
   zona de misiones: `x 28,4 → 583,5 en y=563,9` es el borde superior del bloque, y
   las líneas del «desde» van de `x 92,4 → 139,7` en `y=564,4`.
3. **Los rectángulos de inserción hay que derivarlos de esas líneas**, no de los
   bbox de las etiquetas.

**Lo que falta, exactamente:** una segunda pasada de medición que empareje **cada
etiqueta con la línea de escritura que tiene a su derecha o debajo**, y produzca el
rectángulo real de cada campo. **Es una corrida con PyMuPDF** —las 2155 líneas ya
están extraídas— y **es el paso inmediato antes de escribir el renderer.**

**Mientras eso no esté, §14.3 se lee como «dónde está la etiqueta», no como «dónde
va el valor».** El documento queda corregido en ese sentido.

### 19.5 Lo que se mantiene sin cambios

- **`numero_preimpreso`: CAPTURA NO VERIFICADA** (§16) — sin UI, sin columna, sin migración, sin asumir quién lo introduce.
- **`mision_ribaras`: fuera del renderer** (§2) — `misiones` es la fuente efectiva; legacy por compatibilidad.
- **Código productivo, migraciones y `PLAN_MAESTRO.md`: sin tocar.** Sin commit.

---

## 18. Veredicto anterior — conservado

# NO APTO — BLOQUEO IDENTIFICADO

**Dos bloqueos, y ninguno es de datos:**

1. **Coordenadas del layout sin medir.** El mapa de §8 está en **bandas
   porcentuales**, no en puntos. Especificar `x`/`y`/`width`/`height` reales
   **exige medir el PDF original** — y es una corrida con PyMuPDF, que ya está
   instalado y ya se usó para extraer el texto. **No es un bloqueo de fondo: es un
   paso pendiente y barato.**
2. **La derivación de la cabecera sin verificar.** Si no existe, **el renderer
   oficial no puede completar el encabezado** y hace falta construirla.

**El bloqueo 1 se cierra midiendo. El bloqueo 2 se cierra buscando en el código.**
Ninguno de los dos justifica tocar el modelo — y por eso el veredicto **no es
«faltan datos»**: es **«faltan dos mediciones antes de escribir código»**.
