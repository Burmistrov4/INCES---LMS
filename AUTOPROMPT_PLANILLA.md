# Auto-prompt — Ciclo de vida de la Planilla de Inscripción INCES

> **Cómo usarlo:** pega el bloque de §0 al inicio de una sesión nueva. El resto es
> el contexto que la sesión necesita para no volver a investigar lo ya cerrado.
> **Última actualización:** 2026-10-05 · commit `f53a3ac`

---

## 0. PROMPT (copiar desde aquí)

```
Trabajas en el proyecto INCES-LMS-PROJECT
(C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT).

Es el Trabajo Especial de Grado de Lorenzo Roca (Análisis de Sistemas, IUTEPI,
4º semestre, SA26-2). Se defiende ante un jurado.

STACK REAL: Flutter Web (CanvasKit) · Fastify 5 + TypeScript + Zod · Supabase
(PostgreSQL + RLS) · Cloudflare R2 · Playwright.

OBJETIVO DE ESTA FASE:
Implementar el CICLO DE VIDA DIGITAL de la Planilla de Inscripción INCES, usando
los datos digitales como fuente de verdad y generando un PDF fiel al formato
oficial físico (612×792 pt, 1 página).

REGLA DE ORO — la planilla digital es el DATO MAESTRO; el PDF es una
REPRESENTACIÓN. Nunca al revés. NO se descarga un PDF para editarlo y volver a
subirlo.

ORDEN DE TRABAJO (no saltar pasos):
  1. Resolver las 4 decisiones de negocio abiertas (§6)
  2. Cerrar los rectángulos de inserción del PDF oficial (§5)
  3. Definir PlanillaOficialData
  4. Adaptador semántico
  5. Renderer PDF oficial
  6. Endpoint / descarga
  7. Dashboard del estudiante
  8. Workflow administrativo + versionado
  9. E2E completo: aspirante → admin → corrección → reenvío → aprobación

REGLAS DE INGENIERÍA (no negociables, cada una costó un fallo real):
  · MEDIR antes de afirmar. «No está» se mide, no se deduce.
  · La ausencia en un renderer significa «no se renderiza aquí», NO «el sistema
    no posee el dato». Esa confusión ya produjo una conclusión falsa.
  · Una condición de salida debe ser IMPOSIBLE de satisfacer sin que ocurra lo
    que dice medir.
  · No mezclar: duración del test ≠ duración del comando ≠ duración del teardown.
  · Salida cruda a archivo, sin tuberías: `| grep` retiene la salida.
  · Una corrida por caso cuando se diagnostica.
  · Un verificador que da verde mientras el CI da rojo es PEOR que no tenerlo.

RESTRICCIONES:
  · NO tocar PLAN_MAESTRO.md
  · NO tocar migraciones ni datos de Supabase
  · NO convertir el renderer genérico en un renderer de dos modos
  · NO hacer reset / checkout / clean / stash destructivos
  · Los archivos temporales de diagnóstico se identifican y se retiran

DOCUMENTOS DE REFERENCIA (leer antes de actuar):
  · AUDITORIA_PLANILLA.md               — trazabilidad y reconciliación
  · PLANILLA_OFICIAL_RENDERER_DISENO.md — contrato, geometría y medición
  · ESTADO_DEL_SISTEMA.md               — estado vivo del sistema (§13 = E2E)
  · LEVANTAR_EN_LOCAL.md                — arranque y las 5 trampas del entorno
```

---

## 1. El flujo objetivo

```
ASPIRANTE
   ↓ llena su registro
DATOS DIGITALES  ← FUENTE DE VERDAD
   ├─→ Editar desde el dashboard
   └─→ Generar PDF oficial (bajo demanda, nunca almacenado por defecto)
   ↓
ENVIAR A ADMINISTRACIÓN
   ↓
ADMIN REVISA
   ├─→ OBSERVADA  → el aspirante corrige → REENVIADA → vuelve a revisión
   └─→ APROBADA
```

**Lo que NO se hace:** `Formulario → PDF → editar PDF → subir PDF`. Sería un
retroceso y crearía dos fuentes de verdad.

**Lo que sí:** el aspirante corrige **en el formulario digital** y el PDF se
**regenera**. Un cambio de dirección no toca ningún PDF existente: el siguiente
sale ya corregido.

---

## 2. Máquina de estados

```
BORRADOR ──→ ENVIADA ──→ APROBADA
                │
                └──→ OBSERVADA ──→ REENVIADA ──→ (revisión)
```

| Estado | Puede editar | Notas |
|---|---|---|
| `BORRADOR` | ✅ libremente | |
| `ENVIADA` | 🔒 **bloqueado** | visualizar y descargar, no modificar |
| `OBSERVADA` | ✅ se desbloquea | con el motivo de la observación a la vista |
| `REENVIADA` | 🔒 bloqueado | vuelve a revisión |
| `APROBADA` | 🔒 | final |

**Por qué el bloqueo importa, y no es burocracia:** sin él, el administrador puede
estar revisando `Teléfono: 0412-1111111` mientras el aspirante lo cambia a
`0412-9999999`. **El admin ya no sabe qué estaba revisando.** El bloqueo no protege
al sistema: protege la **validez de la revisión**.

---

## 3. Versionado

**No se guarda un PDF por edición** — eso produce `planilla_juan_v1.pdf`,
`v2.pdf`, `v3.pdf`… sin necesidad.

Se guardan **versiones de los datos enviados**:

```
Planilla #154
  current_version = 2
  v1 · ENVIADA    · 05/10/2026
  v2 · REENVIADA  · 06/10/2026 · «corrección de dirección»
```

**El PDF se genera bajo demanda para la versión que se pida.** Sólo se conserva un
PDF físicamente **cuando exista una razón administrativa o legal** — y esa razón,
hoy, **no está demostrada**.

---

## 4. Arquitectura

```
datos_planilla  (fuente de verdad)
      │
      ├─→ Adaptador semántico ─→ PlanillaOficialData ─→ Renderer PDF oficial
      │
      └─→ Versionado / estados ─→ Workflow
```

**El renderer NO conoce:** catálogos, códigos de migración, JSON crudo, reglas de
negocio, Supabase, Flutter, HTTP ni la base de datos. **Recibe `PlanillaOficialData`
y dibuja.**

**Separación de capas, ya decidida:**

| Capa | Archivo | Responsabilidad |
|---|---|---|
| Fuente | `aspirantes.datos_planilla` | el dato |
| Interpretación | `planilla-oficial-valores.ts` | traducir a semántica |
| Representación genérica | `planilla-pdf.ts` · `planilla-xlsx.ts` | **existentes, no se tocan** |
| Representación oficial | `planilla-oficial-pdf.ts` | **por crear** |

---

## 5. Lo que está cerrado y no hay que volver a investigar

**Medido, con evidencia:**

| Hecho | Valor |
|---|---|
| Geometría del PDF oficial | **612 × 792 pt · 1 página · rotación 0** |
| Las dos copias del PDF | **idénticas** — SHA-256 `eccb284a2bb0883a` |
| Imágenes embebidas | `(8,17)-(108,57)` emblema · `(119,20)-(586,57)` banda |
| Etiquetas | **121 líneas** con `bbox` real |
| Líneas de escritura | **2155** horizontales |
| **Casillas `□`** | **glifos de texto, NO rectángulos** — 0 rectángulos pequeños entre 433 drawings |
| Catálogo | **44 campos = 38 física + 6 sistema** |
| Familiares | **8 columnas físicas = 8 del catálogo** |
| Misiones | **20/20**, mismo orden que el papel, todas con «desde» |
| `mision_ribaras` | **legacy** — `aspirante_model.dart:178` dice que ya no se envía |
| `numero_preimpreso` | catálogo ✓ · **captura en Flutter NO VERIFICADA** |

**Lo único pendiente de medición:** los **rectángulos de inserción**. Los `bbox`
extraídos son de las **etiquetas**, no de las cajas de valores — poner el dato ahí
lo imprimiría **encima del rótulo**. Hay que **emparejar cada etiqueta con su línea
de escritura**. Las 2155 líneas ya están extraídas: es una corrida.

---

## 6. Las 4 decisiones de negocio abiertas

**Ninguna es técnica, y ninguna la puede tomar quien implementa:**

| # | Decisión | Situación |
|---|---|---|
| 1 | **`sexo` con 3 opciones en el catálogo, 2 casillas en el papel** | El contrato es `'F' \| 'M' \| null`. Si un aspirante elige la tercera, **el papel no tiene dónde representarla**. Opciones: quitarla del catálogo · añadir casilla al papel · aceptar que no se represente |
| 2 | **Qué fecha es `FECHA`** | Tres candidatas: fecha de inscripción · de generación del PDF · del lapso. **El documento no decide** |
| 3 | **Quién captura el N.º PREIMPRESO** | El catálogo lo pone en `Cabecera` y el papel en la zona preimpresa → apunta a *al imprimir* o *asociado al ejemplar*, **no al aspirante**. Pero es inferencia |
| 4 | **Qué pasa con una misión 21** | El papel tiene sitio para **20 y no más** |

---

## 7. Trampas del entorno (ya medidas — no volver a perder tiempo aquí)

1. **`NO_PROXY="127.0.0.1,localhost"` siempre.** Sin él, el proxy se come el health-check, Playwright da el backend por «ya corriendo», **no lo arranca**, y el navegador da `ERR_CONNECTION_REFUSED` con el mismo texto que un 500.
2. **`--output=/c/tmp/pw-out-$(date +%s)`** — el *safe-delete shim* bloquea la limpieza de `test-results/` y el fallo se disfraza de error de Playwright.
3. **`tasklist /FI` da falso negativo desde Git Bash.** Para procesos y puertos, `netstat -ano`.
4. **El teardown puede no volver** — pone siempre un `timeout` externo.
5. **`flutter build web` no arranca en este equipo** (`ERROR_PIPE_BUSY` 231). Los tipos se verifican con `node devops/analizar-dart.mjs .`; el bundle viene del artefacto `web-bundle` del CI.

---

## 8. Criterio de terminación

**No es «el PDF se genera».** Es:

> Poder demostrar **trazabilidad completa** desde el formulario oficial hasta los
> datos persistidos y hasta una representación PDF **fiel**, con el ciclo de vida
> completo recorrido por un E2E.

**Y no declarar nada terminado sin evidencia.** En esta fase ya se concluyeron
cosas falsas por inferir desde donde no se debía: «el dato no existe» (existía),
«son 9 columnas» (son 8), «es una errata» (era legacy documentado). **La regla que
salió de ahí: la evidencia debe recorrer `modelo → captura → persistencia →
transformación → renderer → PDF`, y no se afirma nada hasta cerrar esa cadena.**
