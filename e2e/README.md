# Suite E2E

Dos cosas que **ninguna otra prueba del repositorio puede tocar**, porque las dos
ocurren sólo dentro de un navegador de verdad:

| # | Qué | Por qué no cabe en otro sitio |
| --- | --- | --- |
| 1 | La **descarga del CSV** hacia HACER (M4) | El ciclo `Blob` → URL de objeto → `<a download>` → clic vive en `selector_archivos_web.dart`, que usa `package:web` + `dart:js_interop` y **no compila en la VM de Dart** |
| 2 | El **Stepper de inscripción** (M4) | Los pasos no están escritos en Dart: se construyen desde el catálogo, y sólo un navegador dice qué acaba pintando la pantalla |

## 1. La descarga del CSV hacia HACER

### Por qué existe

`flutter test` **no puede** probar la descarga del archivo, y no por falta de
ganas: el código que la hace vive en `lib/services/selector_archivos_web.dart` y
usa `package:web` + `dart:js_interop`, que **no compilan en la VM de Dart**. La
suite de widget lo sustituye por un doble (`SelectorDeArchivos`) y comprueba la
secuencia, pero el `Blob`, la URL de objeto, el `<a download>` y el clic **nunca
se ejecutan**. Esta suite es la única que los ejecuta de verdad, en un navegador
de verdad.

Es la deuda que el propio repositorio venía declarando: *«el ciclo en navegador
sigue siendo deuda»*.

## Qué comprueba

| Comprobación | Cómo |
| --- | --- |
| La descarga llega y no falla | `page.on('download')` + `download.failure()` |
| El archivo no está vacío | `bytes.length > 0` |
| **BOM UTF-8** (`EF BB BF`) | Se miran los **3 primeros bytes del `Buffer`**, no una cadena |
| **CRLF** en todos los finales de línea | Se cuentan los `\n` sin su `\r` |
| Separador `;` | La cabecera partida por `;` da 62 trozos |
| Cabecera = esquema de 62 columnas | Comparación exacta contra `COLUMNAS_HACER` |
| `documento_identidad` | `^[A-Z]{1,2}\d{9}$` |
| Ninguna columna no textual transformada | uuid / jsonb / booleano / date / timestamptz siguen siendo válidos |

**Las aserciones son sobre bytes y no sobre texto, y eso es deliberado.**
`utf8.decode` se come el BOM y un editor normaliza el CRLF: desde una cadena ya
decodificada, las dos reglas que más importan son invisibles. Un test que
afirme `texto.includes('inscripcion_id')` pasa aunque falte el BOM.

## 2. El Stepper de inscripción se construye desde el catálogo

**Qué protege.** El formulario del aspirante no tiene los pasos escritos a mano:
`aspirante_form_screen.dart` los arma con `catalogo.grupos` y un `for`, así que
**un grupo del catálogo es un paso**, y un grupo que se queda sin campos
desaparece solo. Es una virtud —el CFS cambia el formulario desde el panel, sin
tocar Flutter— y también un riesgo: si el cableado se rompiera, la pantalla
mostraría pasos que el catálogo no tiene, y **ninguna prueba de widgets lo vería**,
porque todas usan catálogos falsos.

**La prueba es diferencial, no una lista fija.** No afirma «los pasos son estos
nueve». Lee el catálogo por `GET /api/v1/inscripcion/campos` —la misma respuesta
que consume la pantalla— y comprueba que el Stepper muestra **exactamente** esos
grupos, en ese orden, más el paso de cierre. Si mañana el CFS añade un grupo desde
el panel, la prueba sigue pasando; sólo falla si la pantalla se desincroniza del
catálogo, que es el fallo que importa.

**Por qué el paso de cierre se espera aparte.** «Confirmación y Contraseña» es el
único paso que **no** viene del catálogo: la contraseña es la credencial de la
cuenta, no un dato de la planilla, así que está fijo en Dart
(`_construirConfirmacion`). La prueba lo añade al final de la lista esperada — y
afirma explícitamente que va **después** del último grupo, porque comparar sólo el
conjunto de títulos no detectaría que se hubiera reordenado.

### Cómo expone Flutter los títulos de paso (medido el 2026-09-29)

Dos formas distintas en la misma pantalla, y ninguna es la obvia:

| Paso | Nodo | Dónde está el texto |
| --- | --- | --- |
| El **activo** | `flt-semantics role="group"`, 734×631 | En el **`aria-label`**, como `"1\nDatos personales"` — número, salto de línea, título |
| Los **colapsados** | `flt-semantics role="button"`, 734×72 | Como **nodo de texto directo**, sin `<span>` y sin `aria-label` |

De ahí salen tres consecuencias, y las tres están en el código:

- Los títulos se **normalizan** (`\s+ → ' '`) antes de comparar: el del paso activo
  trae un salto de línea en medio.
- **No se puede filtrar por `role="button"`**: el paso 1 no lo es. La prueba
  selecciona por «el texto empieza por el número del paso».
- `FlutterApp.nodos()` **no veía** el texto de los colapsados: sólo miraba
  `children[0]` cuando era un `<span>`, y esos nodos **no tienen hijos de
  elemento**. Se le añadió el paso «su propio `textContent` cuando
  `children.length === 0`». Antes de eso, `volcarSemantica()` los mostraba como
  botones sin nombre — un diagnóstico que ocultaba justo el dato que se buscaba.

## Cómo se conduce una app Flutter Web (CanvasKit)

Flutter no pinta widgets: pinta píxeles. **No hay `<button>`, ni `getByText`, ni
`getByRole`.** Todo lo que hace `src/pages/FlutterApp.ts` está medido contra una
app Flutter Web real, y hay cuatro resultados que cambian el diseño:

| Lo que se midió | Consecuencia |
| --- | --- |
| `click()` sobre `flt-semantics-placeholder` **agota el tiempo**; `click({force:true})` falla con «outside of the viewport»; `dispatchEvent('click')` **funciona** (41 nodos) | Para encender la accesibilidad se usa `dispatchEvent` |
| `getByRole('button', {name})` → **0** coincidencias; `getByText` → **0**; `getByLabel` → **1**; `flt-semantics[aria-label="…"]` → **1** | El localizador por defecto es el atributo, no el rol |
| Pulsar un nodo semántico con `click()` **también agota el tiempo**; `dispatchEvent` y `force` funcionan | Un POM con `click()` a secas falla el 100 % de las pulsaciones |
| El árbol semántico **sobrevive** a un cambio de `location.hash` | Se enciende una vez por carga, no en cada paso |
| El texto de un nodo puede ser un **nodo de texto directo**, sin `<span>` hijo | `nodos()` cae a su propio `textContent` cuando el nodo **no tiene hijos de elemento** (los encabezados de paso colapsados del Stepper son así) |
| `<canvas>` está en el **shadow DOM** de `flt-glass-pane` | `document.querySelectorAll('canvas').length` da **0** con la app perfecta |

Y una trampa de la app, no del navegador: **el botón de exportar se llama igual
en todas las tarjetas** («Exportar Planilla HACER (.csv)», uno por sección) y el
árbol semántico de Flutter es **plano**. Desambiguar por jerarquía es imposible,
así que `botonDeTarjeta()` lo hace por **geometría**: reparte todos los botones
entre todos los títulos según distancia y se queda con el que le toca al título
pedido. La primera versión buscaba un nodo cuya caja englobara al botón y **no
servía**: Flutter crea un nodo semántico con la caja del **título**, no con la
tarjeta entera, así que ese contenedor puede no existir.

## Tiempos, y por qué no son redondos

La **primera** descarga de un proceso de navegador nuevo tarda entre **4,4 y
5,7 s**; las siguientes, entre **200 y 270 ms**. Se comprobó invirtiendo el orden
de los casos —el lento pasó a ser el otro—, así que es un coste de arranque del
gestor de descargas del navegador, **no** de la aplicación y **no** del
`revokeObjectURL`. Un `timeout` de 5 s, que es el que uno escribiría por defecto,
haría fallar la suite por el sitio equivocado.

## Suite por defecto y pruebas que mutan datos

La regresión predeterminada **excluye** los archivos `_*.spec.ts` (sondas temporales de diagnóstico) y `aula_virtual_ciclo.spec.ts`. Este último crea y publica una tarea, hace que un alumno la entregue y que el docente la califique y devuelva; no hay una ruta HTTP de borrado de tareas, así que deja datos persistentes. No debe ejecutarse contra la sección compartida de demostración ni en el cron sin aislamiento y limpieza verificable.

Sólo se permite incluir ese ciclo de forma explícita cuando `E2E_SECCION` y las cuentas pertenecen a un conjunto de prueba desechable y hay limpieza verificada:

```powershell
$env:E2E_PERMITIR_CICLO_MUTANTE = '1'
npx playwright test tests/aula_virtual_ciclo.spec.ts
```

**Limpieza verificada (añadida el 2026-10-09).** El spec crea una tarea y una entrega, y no hay ruta HTTP de borrado. `supabase/limpiar-ciclo-aula.mjs` borra **sólo** las tareas del ciclo creadas dentro de una ventana temporal (por defecto, la última hora) y comprueba que no quedan entregas huérfanas:

```bash
node supabase/limpiar-ciclo-aula.mjs                       # lista, no borra
node supabase/limpiar-ciclo-aula.mjs --confirmar           # borra la última hora
node supabase/limpiar-ciclo-aula.mjs --confirmar --desde "2026-10-09T12:45:00Z"
```

Medido el 2026-10-09 (última corrida): el ciclo pasa **7/7, 0 flaky**, exit 0, contra el bundle local fresco. C7 verifica el título real `Calificaciones`. La limpieza acotada devuelve los conteos a la línea base previa a esta corrida: tareas 77 → 76, entregas 228 → 225, 0 huérfanas. Este resultado supersede la medición histórica anterior de 6/7 + 1 flaky. **Advertencia:** esa corrida puntual utilizó la sección compartida `SA` porque se verificó el cleanup por ventana y la restauración exacta de conteos; no debe convertirse en ejecución habitual. Antes de repetir el ciclo, preferir una sección aislada y cuentas dedicadas.

No configures `E2E_PERMITIR_CICLO_MUTANTE` en el flujo nocturno normal. La opción habilita el test; el aislamiento y la limpieza son responsabilidad de quien lo lanza.

## Flujos de identidad — instrumentos fuera de esta suite

La invitación de docentes y la recuperación de contraseña se verifican **contra el motor real**
(PostgREST + RLS + Fastify + GoTrue), que es justo lo que los dobles en memoria no pueden probar.
Son dos scripts en `supabase/`, **fuera de CI a propósito** porque escriben en la base real:

```bash
node supabase/humo-invitaciones.mjs --confirmar   # 34 OK / 0 fallos
node supabase/humo-recuperacion.mjs --confirmar   # 27 OK / 0 fallos
```

Ambos crean cuentas desechables (`humo-*@ejemplo.invalid`), operan sólo sobre ellas y **purgan por
prefijo**; imprimen el residuo al final y salen con código distinto de cero si algo queda. No tocan
cuentas reales ni datos compartidos. Medido el 2026-10-09: residuo `0/0/0` en los dos.

## Ejecutar

### En local

**El entorno vive en `e2e/.env.e2e`**, que está en `.gitignore` y que
`playwright.config.ts` carga al arrancar. No hay que exportar nada a mano en cada
terminal.

```bash
# 1. Compilar el bundle (necesita .env.json; ver más abajo)
flutter build web --dart-define-from-file=.env.json

# 2. Instalar la suite una vez
cd e2e && npm ci && npm run navegador

# 3. Escribir .env.e2e una vez (plantilla: .env.e2e.example)
#    E2E_ADMIN_EMAIL, E2E_ADMIN_PASSWORD, E2E_SECCION, ...

# 4. Correr (levanta el servidor y el backend solo)
npm test
```

El cargador **no pisa lo que ya venga del entorno**. Eso tiene dos
consecuencias que se usaron para medirlo:

- **En CI el archivo no existe** y las variables llegan de los secretos, así que
  el mismo `playwright.config.ts` sirve en los dos sitios, sin una rama «modo
  local».
- **Una variable en la línea de órdenes gana sobre el archivo.** Verificado
  arrancando la suite con `E2E_SECCION="SA26-2"` teniendo otro valor en el
  archivo: ganó el de la línea de órdenes. Es lo que permite probar contra otra
  sección sin editar nada.

`playwright.config.ts` **levanta también el backend** (`npm --prefix ../backend
run start`, esperando a `/salud`), porque el panel pide la lista de secciones a
Fastify y sin él no hay tarjetas. Si ya lo tienes corriendo a mano:

```bash
E2E_ARRANCAR_BACKEND=0 npm test
```

En **Windows con sandbox**, según el entorno, el CLI de Flutter puede morir al
lanzar su primer proceso hijo (`ERROR_PIPE_BUSY`, `CreateFile failed 231`), en
cuyo caso `flutter build web` y `flutter run` no arrancan y hay que compilar en
CI y servir un bundle ya compilado en local:

```bash
node serve.mjs build/web 8090     # en una terminal
E2E_ARRANCAR_BACKEND=0 npm test   # en otra; reutiliza el servidor
```

> **Medido el 2026-10-09 (sesión 2): el `231` no apareció.** `flutter build web
> --release --dart-define-from-file=.env.json` terminó en `√ Built build\web` y
> `flutter test --no-pub` corrió **974 pruebas, todas verdes**. Es una limitación
> **del sandbox de la sesión**, no del proyecto: si el comando funciona, úsalo.
> Si vuelve el `231`, mide antes de citarlo.

**Nunca certifiques código nuevo con un bundle viejo.** Si el bundle se compiló
con `dart-define.example.json` (la plantilla), `playwright.config.ts` **falla de
inmediato con la causa escrita**: el artefacto apuntaría a
`https://<project-ref>.supabase.co` y el login fallaría antes de emitir ninguna
petición.

Para usar el Chrome del sistema en vez del Chromium de Playwright:
`E2E_CANAL=chrome npm test`.

### En CI/CD

```bash
npm ci
npx playwright install --with-deps chromium
npx playwright test --reporter=list,html
```

El flujo completo está en `.github/workflows/e2e.yml`.

## Secretos que hacen falta

Son **seis**, y el sexto no es evidente.

| Secreto | Para qué |
| --- | --- |
| `SUPABASE_URL` | Viaja al bundle por `--dart-define-from-file` y lo usa el backend |
| `SUPABASE_ANON_KEY` | Íd. — es la clave pública; la RLS es la que protege |
| `SUPABASE_SERVICE_ROLE_KEY` | **La exige el backend para arrancar.** Ver abajo |
| `E2E_ADMIN_EMAIL` | Una cuenta **de administración y de prueba** |
| `E2E_ADMIN_PASSWORD` | Íd. |
| `E2E_SECCION` | El **título de la tarjeta** de una sección con matriculados |

### Por qué el sexto

`backend/src/config/env.ts` declara `SUPABASE_SERVICE_ROLE_KEY` con `min(20)` y
**sin valor por defecto**: es la única variable de Supabase que no es opcional.
Un backend sin ella no levanta. Y el panel de inscripciones **pasa por el
backend** —`AdminInscripcionesRepository` construye un `BackendInscripcionGateway`,
no un gateway de Supabase—, así que sin backend no hay tarjetas, y sin tarjetas
no hay botón que pulsar. La suite fallaría buscando el botón y el mensaje
señalaría al botón, no al backend apagado.

Salta la RLS: **es la credencial más delicada de las seis.** En un repositorio
público, un secreto de Actions no se puede leer una vez guardado, y eso es lo
único que lo protege.

### `E2E_SECCION` es el título de la tarjeta, no el código de período

**Medido el 2026-09-25 contra la base real:** la sección sembrada tiene
`name = 'SA'` y `period_code = 'SA26-2'`. El título que pinta el panel es
`materiaNombre ?? nombre` (`cpanel_inscripciones_panel.dart`), o sea
**`Programación I [SEMILLA]`**. El `period_code` sólo aparece en el **subtítulo**
(`'$programaNombre · $periodo'`).

Poner `SA26-2` funcionaría **por accidente** —el localizador busca el texto en
cualquier nodo semántico, incluido el subtítulo—, pero estaría fijando el test a
un dato que no es el que la pantalla muestra. Si algún día el subtítulo cambia,
el test se rompe por una razón que no tiene nada que ver con la exportación.

**Recomendación:** no uses la cuenta del administrador real. La suite inicia
sesión de verdad contra el Supabase real, así que cada corrida crea una sesión
en `auth.users` y deja trazas en la auditoría de accesos. El flujo corre además
**cada noche a las 06:00 UTC**, así que esas trazas se acumulan solas.

Estos seis secretos son parte de **D9**, que sigue pendiente. El flujo
`e2e.yml` **falla a propósito** mientras falten, con una anotación que dice
cuáles: un verde con las pruebas saltadas sería peor que un rojo, porque nadie
lo miraría.

## Lo que esta suite NO verifica

- **Escribir en un campo de texto de Flutter.** Es el paso menos verificado de
  todo el POM: todo lo demás se midió contra una app real, esto no, porque no
  encontré una app Flutter Web pública con un campo accesible por semántica. Si
  algo va a fallar, falla en `escribirEn()`, y por eso comprueba el resultado y
  lo dice en vez de continuar con un formulario vacío.
- **El reintento tras un fallo de red.** El servicio distingue `ConsultaFallida`
  de `DescargaFallida`, pero forzar una caída de red a mitad de la exportación no
  está cubierto.
- **La revocación de la URL de objeto.** `revokeObjectURL()` se llama en el acto
  tras el clic; se midió que el archivo **sí llega** (3273 bytes, sin fallo) en
  las tres variantes —revoke inmediato, diferido y ausente—, pero no hay una
  aserción que detecte una fuga de memoria si algún día se dejara de revocar.
- **La otra mitad de D17.** Que las columnas sean las que HACER espera sigue sin
  saberse. Esta suite comprueba que el archivo cumple el **formato**; no puede
  comprobar que el **contenido** sea el que el INCES necesita.

## Puente de hardware del escáner de QR

`e2e/hardware/` **no forma parte de esta suite** y CI no la ejecuta: tiene su
propio `playwright.hardware.config.ts`, y `e2e.yml` corre `npx playwright test`,
que usa `playwright.config.ts` (`testDir: './tests'`). Se invoca a mano.

Existe porque el escáner de QR (M7 · D21) tenía una mitad sin verificar por
nadie: **la lectura**. En `flutter test` no hay cámara y no hay JDK ≥ 17 para
compilar el APK, así que la cadena «fotograma → decodificador → texto → API» sólo
estaba afirmada por sus comentarios.

Se resuelve sustituyendo la cámara por un vídeo con un QR conocido:

```bash
# 1. El bundle. `build/web` local está congelado (aquí `flutter build web` no
#    arranca), así que se usa el artefacto `web-bundle` que publica el flujo E2E:
#    se descarga a C:/tmp/web-bundle.
# 2. El vídeo. Escribe además un «sidecar» .json con el contenido.
node devops/generar-qr-y4m.mjs "3f2a1b4c-5d6e-7f80-9a1b-2c3d4e5f6071:471212" "C:/tmp/qr_dummy.y4m"

# 3. La prueba.
cd e2e
npx playwright test -c playwright.hardware.config.ts
```

Qué hace cada prueba:

| # | Prueba | Necesita | Qué mide |
|---|---|---|---|
| 1 | el puente | nada | Que la cámara falsa entrega fotogramas y que un lector recupera el texto exacto del QR. Comprueba además que el bundle servido **contiene el escáner**, para no medir un build viejo. |
| 2 | el recorrido | `E2E_ESTUDIANTE_EMAIL` / `E2E_ESTUDIANTE_PASSWORD` | Entra como alumno, abre «Asistencia», pulsa el botón del escáner y afirma que la app manda el marcaje con el par `<uuid>:<6 dígitos>` leído. Sin credenciales **se salta con un motivo legible**, no falla. |

**Medido el 2026-09-29**, contra el bundle del CI (`main.dart.js`, 3.704.537 B):

```
[puente] leído por zxing-wasm · fotogramas 640×480 · BarcodeDetector ausente · 1 dispositivo(s) de vídeo
  ok 1 … 1 · el puente (5.8s)
  -  2 … 2 · el recorrido
  1 skipped
  1 passed (36.1s)
```

Dos datos que conviene retener:

- **`BarcodeDetector` está ausente en el Chromium de escritorio.** El paquete
  (`mobile_scanner_web.dart:464-485`) usa la API nativa «cuando está disponible
  (Chrome/Edge/Safari 17+)» y **cae a `zxing-wasm`» en el resto — y el resto
  incluye Windows y Linux. Así que lo que se ejerce de verdad en esta máquina es
  el **respaldo**, que es además el camino más frágil: depende de una CDN. Se
  midió que `cdn.jsdelivr.net` responde con `cross-origin-resource-policy:
  cross-origin` y `access-control-allow-origin: *`, así que el `COEP:
  require-corp` que pone `serve.mjs` **no** lo bloquea.
- **La grabación de vídeo/traza cuelga el runner.** Con `video` o `trace`
  encendidos la prueba pasa pero el proceso **no termina** — hay que matarlo a
  mano y el código de salida se pierde. Por eso van apagados por defecto y se
  encienden con `E2E_VIDEO=1` / `E2E_TRACE=1` sólo al depurar.

**Lo que este puente NO verifica**, y se dice en voz alta: no ejercita la cámara
física, ni el driver, ni el diálogo de permiso del sistema operativo
(`--use-fake-ui-for-media-stream` lo concede solo). Un verde aquí significa «la
lógica de lectura y marcaje está bien», **no** «el permiso del móvil está bien».

### Modo seguro: deshacer la marca de prueba

La prueba 2 **escribe de verdad** en `attendance_marks`. Para deshacerlo:

```bash
node e2e/hardware/limpiar-marca.mjs --sesion <uuid> --codigo <6 dígitos>            # lista
node e2e/hardware/limpiar-marca.mjs --sesion <uuid> --codigo <6 dígitos> --confirmar # borra
```

Sin `--confirmar` no borra nada. Toca **una sola tabla** —`attendance_marks`— y
**no abre `attendance_sessions`**: hay 7 sesiones en estado `OPEN` de una tanda
del 2026-09-26 que son un residuo previo, y alterarlas falsearía lo que la prueba
mide. Va con la clave de servicio porque **medido**: `attendance_marks` tiene
políticas de `SELECT` (docente) e `INSERT` (estudiante) y **ninguna de `DELETE`**
—es una tabla de sólo-añadir por diseño—, así que ningún usuario puede borrar una
marca, ni la suya.
