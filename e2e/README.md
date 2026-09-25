# Suite E2E — la descarga del CSV hacia HACER

## Por qué existe

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

## Ejecutar

### En local

```bash
# 1. Compilar el bundle (necesita .env.json; ver más abajo)
flutter build web --dart-define-from-file=.env.json

# 2. Instalar la suite una vez
cd e2e && npm ci && npm run navegador

# 3. Pasarle las credenciales y la sección
export E2E_ADMIN_EMAIL="..."; export E2E_ADMIN_PASSWORD="..."; export E2E_SECCION="SA26-2"

# 4. Correr (levanta el servidor solo)
npm test
```

En **Windows con sandbox**, el paso 1 no funciona: el CLI de Flutter muere al
lanzar su primer proceso hijo (`ERROR_PIPE_BUSY`, `CreateFile failed 231`), así
que `flutter build web` y `flutter run` no arrancan. Ahí la compilación va en CI
y en local sólo se sirve un bundle ya compilado:

```bash
node serve.mjs build/web 8090     # en una terminal
npm test                          # en otra; reutiliza el servidor
```

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

| Secreto | Para qué |
| --- | --- |
| `SUPABASE_URL` | Viaja al bundle por `--dart-define-from-file` |
| `SUPABASE_ANON_KEY` | Íd. — es la clave pública; la RLS es la que protege |
| `E2E_ADMIN_EMAIL` | Una cuenta **de administración y de prueba** |
| `E2E_ADMIN_PASSWORD` | Íd. |
| `E2E_SECCION` | Una sección **con matriculados** (si no, la app avisa que no hay nómina) |

**Recomendación:** no uses la cuenta del administrador real. La suite inicia
sesión de verdad contra el Supabase real, así que cada corrida crea una sesión
en `auth.users` y deja trazas en la auditoría de accesos.

Estos cinco secretos son parte de **D9**, que sigue pendiente. El flujo
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
