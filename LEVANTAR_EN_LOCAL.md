# Levantar el proyecto en local

> Todo lo que sigue está **medido** en este equipo (Windows, Git Bash). Donde algo
> no se pudo verificar, se dice. Si algo falla, la causa más probable suele estar
> en **§5 — las cinco trampas del entorno**, no en tu código.

---

## 1. Requisitos

| Herramienta | Versión / ruta en este equipo |
|---|---|
| Node | `C:\Users\Loro\.workbuddy-ai\binaries\node\versions\22.22.2-3\node.exe` |
| Flutter SDK | `C:/Users/Loro/develop/flutter` |
| Supabase | **en la nube** — no hay instancia local |
| Credenciales | `backend/.env` y `e2e/.env.e2e` (los dos ignorados por git) |

**Los dos `.env` no están en el repositorio y no se pueden recuperar de él.** Si no
los tienes, pídelos: sin ellos no arranca ni el backend ni el E2E.

---

## 2. Backend (Fastify, puerto 3001)

```bash
cd backend
npm install
npm run build          # compila TypeScript a dist/
npm run start          # node --env-file-if-exists=.env dist/server.js
```

**Comprobación:**

```bash
curl -s http://127.0.0.1:3001/salud
```

Debe responder `200`. Arranca escuchando en `0.0.0.0:3001` y lo dice en el log:

```
INCES LMS API v0.1.0 escuchando en 0.0.0.0:3001 (entorno: development)
```

**Verificación de tipos y pruebas:**

```bash
npm run verify
```

---

## 3. Frontend (Flutter Web, puerto 8090)

### 3.1 Si tienes el bundle compilado

El frontend se sirve estático. El arnés del E2E usa `e2e/serve.mjs`:

```bash
cd e2e
node serve.mjs "../build/web" 8090
```

Y queda en `http://127.0.0.1:8090`.

### 3.2 Si necesitas compilarlo — **y aquí está el problema**

```bash
flutter build web --dart-define-from-file=.env.json
```

> **En este equipo `flutter build web` NO arranca.** El VM de Dart muere en su
> primer intento de crear un proceso hijo con `ERROR_PIPE_BUSY` (231). No es un
> error de configuración: es una limitación del entorno, y afecta por igual a
> `flutter test`, `flutter analyze` y `dart test`.

**Lo que sí funciona aquí:**

```bash
# Verificación de TIPOS de los 207 archivos Dart, sin dart.exe de por medio:
node devops/analizar-dart.mjs .

# Resolver dependencias (esto sí corre):
C:/Users/Loro/develop/flutter/bin/cache/dart-sdk/bin/dart.exe pub get --offline
```

**Y para obtener un bundle fresco**, el único camino fiable es descargar el
artefacto que publica el CI:

```bash
gh run list --workflow "E2E (Playwright)" --limit 5
gh run download <run-id> -n web-bundle -D /c/tmp/web-bundle
cp -r /c/tmp/web-bundle/* build/web/
```

---

## 4. Base de datos (Supabase en la nube)

**No hay Postgres local.** El proyecto apunta a un proyecto de Supabase.

```bash
# Estado del libro mayor de migraciones
export SUPABASE_ACCESS_TOKEN=$(grep '^SUPABASE_ACCESS_TOKEN=' backend/.env | cut -d= -f2-)
node supabase/apply-migrations.mjs --check

# Aplicar las pendientes
node supabase/apply-migrations.mjs --confirmar

# Inspeccionar el catálogo real (funciones, políticas, tablas)
node supabase/verificar-esquema.mjs
```

**Sembrar los datos de demostración:**

```bash
node supabase/sembrar-datos.mjs
```

> **Aviso, medido:** `--limpiar` **no es incondicional**. Se detiene con `23503`
> si una ficha **real** referencia un programa del sembrado —los programas nacen
> activos y cualquiera puede inscribirse en ellos—. **Y una limpieza que se
> detiene no deja el sistema como estaba**: borra hacia arriba hasta donde llega.
> Tras cualquier limpieza fallida hay que **volver a sembrar**, no dar por hecho
> que no cambió nada.

---

## 5. Las cinco trampas del entorno (las cinco medidas)

Estas cinco producen mensajes que **señalan al sitio equivocado**. Están aquí
porque cada una costó horas.

### 5.1 El proxy se come el `127.0.0.1`

Si `HTTP_PROXY` está definido, el chequeo de salud del backend **va por el proxy**,
el proxy responde, Playwright da el backend por «ya corriendo» y **no lo arranca**.
El navegador recibe `ERR_CONNECTION_REFUSED` y la app muestra «No pudimos conectar
con el servidor» — el mismo texto que daría un 500.

**Siempre:**

```bash
NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost" <comando>
```

### 5.2 El *safe-delete shim* bloquea la limpieza de `test-results/`

Y el fallo aparece como error de Playwright. **Usa un directorio de salida nuevo
en cada corrida:**

```bash
--output=/c/tmp/pw-out-$(date +%s)
```

### 5.3 Backend arrancado a mano usa otra `CORS_ORIGINS`

El arnés inyecta `127.0.0.1:8090`; `backend/.env` trae `localhost:8090`.
**Para el navegador son dos orígenes distintos.** Si estás depurando el spec, deja
que el backend lo levante el arnés.

### 5.4 El teardown de Playwright puede colgarse

Medido: el comando **no vuelve**, y lo único que lo termina es un `timeout`
externo. **Ponle siempre uno** (`timeout 400 …`), y **no confundas reloj con
duración de prueba** — ver §6.

### 5.5 `tasklist` no es fiable desde Git Bash

`tasklist /FI "PID eq N"` devuelve **falso negativo** —dijo «muerto» de seis PIDs
que estaban vivos—. **Para procesos y puertos, usa `netstat -ano`**, que es la
única fuente que dio datos correctos.

---

## 6. E2E (Playwright)

### 6.1 Correr la suite

```bash
cd e2e
CI=true \
NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost" \
timeout 400 npx playwright test --reporter=list --output=/c/tmp/pw-out-$(date +%s)
```

`CI=true` hace dos cosas: pone `retries: 1` y `reuseExistingServer: false`. El
arnés levanta por su cuenta los **dos** `webServer` —el estático en 8090 y el
backend en 3001— y los cierra al terminar.

**Suites actuales:** `export_csv` (10) · `stepper_inscripcion` (1) ·
`aula_virtual` (3). Total **14 en verde**.

### 6.2 Las tres métricas — **no las mezcles**

| Métrica | Qué es |
|---|---|
| **duración del test** | lo que Playwright reporta: `ok 1 … (2.7s)` |
| **duración del teardown** | entre la última marca y la vuelta del proceso |
| **duración del comando** | el reloj del wrapper, con arranque y cierre incluidos |

En una corrida **sana**, `comando − test ≈ 4 s`. Si esa diferencia son cientos de
segundos, **el problema está en el teardown, no en el caso** — y describirlo como
«el test tardó 900 s» es un error de lectura que ya se cometió aquí.

### 6.3 Escribir un spec nuevo: las tres reglas

Las tres salieron de errores reales de esta sesión.

1. **Una corrida por caso cuando estás diagnosticando.** El archivo completo
   mezcla condiciones y el fallo se mueve de un caso a otro: no es la unidad de
   medida correcta.
2. **La condición de salida tiene que ser imposible de satisfacer sin que ocurra
   lo que dice medir.** `buttons > 2` se satisface con la pantalla anterior;
   `firmaDelArbol() !== antes` se satisface con un repintado. Usa un **nodo
   exclusivo de la vista destino**.
3. **Salida cruda a archivo, sin tuberías.** `comando | grep …` **retiene la
   salida** y la pierdes justo cuando la necesitas.

### 6.4 Dos hechos de CanvasKit que gobiernan la interacción

* **`dispatchEvent('click')` no siempre dispara el gesto de Flutter.** Medido en
  el `TabBar`: **0** etiquetas nuevas con el evento despachado, **3** con un
  `mouse.click` real. Por eso existe `FlutterApp.pulsarPestana`, que pulsa por
  coordenadas.
* **La geometría del nodo semántico no es la del DOM.**
  `locator.boundingBox()` sobre `flt-semantics` da **0**; el centro que publica
  `nodos()` da **3**. Sólo la segunda sirve.

### 6.5 Y un hallazgo sin cerrar, que conviene conocer

**El modal de creación no monta si se pulsa con el árbol a medio montar.**
Medido: con **56 nodos** monta —con los dos gestos—; con **39**, no monta con
ninguno. **La espera por rótulo exclusivo no basta**, porque el rótulo aparece
antes de que la pantalla termine de montar. La corrección pendiente es esperar a
que el árbol **deje de crecer**, no a que aparezca un nodo.

---

## 7. Orden de arranque recomendado

```bash
# 1 · Verificar el esquema (contra la nube)
export SUPABASE_ACCESS_TOKEN=$(grep '^SUPABASE_ACCESS_TOKEN=' backend/.env | cut -d= -f2-)
node supabase/apply-migrations.mjs --check

# 2 · Backend
cd backend && npm install && npm run build && npm run start &

# 3 · Frontend estático
cd e2e && node serve.mjs "../build/web" 8090 &

# 4 · Comprobar los dos
curl -s http://127.0.0.1:3001/salud
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8090/

# 5 · Abrir en el navegador
#    http://127.0.0.1:8090
```

**Credenciales sembradas** (si el sembrado se ejecutó): `admin@semilla.invalid` ·
`docente@semilla.invalid` · `estudiante1@semilla.invalid`. La contraseña está en
`e2e/.env.e2e`, no aquí.

---

## 8. Solución de problemas — síntoma → causa

| Síntoma | Causa más probable |
|---|---|
| «No pudimos conectar con el servidor» | §5.1 — falta `NO_PROXY` |
| Playwright no arranca el backend | §5.1 |
| Error raro al limpiar `test-results/` | §5.2 — usa `--output` nuevo |
| La app carga pero no llama a la API | §5.3 — `CORS_ORIGINS` |
| El comando no vuelve nunca | §5.4 — pon `timeout` |
| `tasklist` dice que un proceso murió y sigue vivo | §5.5 — usa `netstat -ano` |
| `flutter build web` muere con `231` | §3.2 — usa el artefacto del CI |
| `dart format` da verde y CI rojo | `dart format` comprueba **sintaxis**, no tipos |
| El modal no abre «a veces» | §6.5 — se pulsa con el árbol a medio montar |

---

## 9. Verificación completa antes de empujar

```bash
# Tipos de Dart (207 archivos) — el listón del CI
node devops/analizar-dart.mjs .

# Backend
npm --prefix backend run verify

# E2E con paridad de CI
cd e2e && CI=true NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost" \
  timeout 400 npx playwright test --reporter=list --output=/c/tmp/pw-out-$(date +%s)
```

> **El listón del verificador es el del CI, y son los TRES niveles.** Hubo aquí un
> verificador que filtraba las `info` y daba «sin errores ni avisos» con el CI en
> rojo. **Un verificador que da verde mientras el CI da rojo es peor que no
> tenerlo**, porque su verde se cita como prueba para decidir que ya se puede
> empujar.
