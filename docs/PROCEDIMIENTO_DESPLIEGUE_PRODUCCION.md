# Procedimiento oficial de despliegue a producción — INCES LMS

> Guía operativa para que otro agente compile, publique y verifique INCES LMS en GitHub, GitHub Actions, Cloudflare Pages, Render y Supabase. Un push no equivale a un despliegue exitoso.

## 1. Inventario de producción

| Componente | Configuración |
|---|---|
| Repositorio | https://github.com/Burmistrov4/inces-lms |
| Rama de producción | main |
| Frontend Flutter Web | Cloudflare Pages, proyecto inces-lms |
| Frontend público | https://inces-lms.pages.dev |
| Backend | Render, servicio inces-lms-api |
| Backend público | https://inces-lms-api.onrender.com |
| Health check | https://inces-lms-api.onrender.com/salud |
| Base de datos | Supabase PostgreSQL |
| Configuración Render | render.yaml en la raíz |
| CI | .github/workflows/backend_ci.yml, flutter_ci.yml, e2e.yml, supabase_ci.yml y limpiar-pendientes.yml |

El frontend debe usar la API https://inces-lms-api.onrender.com. No publiques un bundle que use localhost, una IP LAN o un servidor de desarrollo.

## 2. Reglas no negociables

1. Confirma que estás en el repositorio correcto y en la rama esperada.
2. Ejecuta git status --short --branch antes de editar, compilar, limpiar o publicar.
3. No ejecutes git reset --hard, git clean -fd ni borrados masivos. No sobrescribas cambios ajenos.
4. No incluyas .env, claves, tokens, logs, capturas ni pruebas temporales en commits.
5. Nunca imprimas secretos ni los copies a esta documentación. Usa variables de entorno o el gestor de secretos autorizado.
6. No asumas que Cloudflare, Render o Supabase se actualizaron porque el push terminó.
7. No apliques migraciones de producción sin autorización explícita, revisión del SQL y plan de recuperación.
8. No cambies secretos, CORS, dominios, infraestructura o planes sin registrar el motivo y confirmar el impacto.
9. Si hay archivos locales ajenos a la tarea, déjalos intactos y repórtalos.

## 3. Preparación y GitHub

Ejecuta en PowerShell:

    $root = 'C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT'
    Set-Location $root
    git rev-parse --show-toplevel
    git branch --show-current
    git status --short --branch
    git fetch origin
    git log -1 --oneline
    git rev-parse HEAD
    git rev-parse origin/main

Confirma que la raíz corresponde a INCES LMS. Revisa diferencias locales y remotas antes de actualizar o publicar. Si hay cambios sin subir, inspecciona archivo por archivo y ejecuta las pruebas de la sección 4.

Cuando los cambios estén revisados y autorizados, agrega únicamente los archivos pertinentes:

    git add <archivos-revisados>
    git diff --cached --check
    git diff --cached --stat
    git diff --cached
    git commit -m "descripción breve del cambio"
    git push origin main
    git fetch origin
    git status --short --branch
    git rev-parse HEAD
    git rev-parse origin/main

No uses git add -A sin revisar el estado: podría incorporar archivos temporales. HEAD y origin/main deben coincidir para confirmar que el commit está en remoto.

## 4. Pruebas antes de publicar

### 4.1 Backend

    Set-Location "$root\backend"
    npm ci
    npm run verify
    npm run build

npm run verify ejecuta typecheck, lint y tests. Si algo falla, investiga y corrige antes de desplegar.

### 4.2 Flutter

Desde la raíz:

    Set-Location $root
    flutter --version
    flutter pub get
    flutter test

Si se usa --no-pub, confirma que las dependencias ya están instaladas y actualizadas. Antes de terminar procesos Flutter/Dart, comprueba qué tarea ejecutan y evita builds simultáneos.

### 4.3 GitHub Actions

En https://github.com/Burmistrov4/inces-lms/actions confirma los workflows del SHA exacto que vas a publicar. Espera a que terminen: in_progress no es PASS. Inspecciona los logs de cualquier fallo. CI no es lo mismo que un workflow de despliegue.

Con GitHub CLI autenticado, opcionalmente:

    gh auth status
    gh run list --repo Burmistrov4/inces-lms --limit 15
    gh run view <RUN_ID> --repo Burmistrov4/inces-lms

## 5. Build Flutter Web para producción

Desde la raíz del proyecto:

    Set-Location $root
    $env:PROGRAMFILES_X86 = 'C:\Program Files (x86)'
    flutter build web --release --no-pub --no-wasm-dry-run --dart-define-from-file=.env.json --dart-define=API_BASE_URL=https://inces-lms-api.onrender.com
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Web build falló con código $LASTEXITCODE"
    }

El override de API de producción debe prevalecer sobre cualquier valor local de .env.json. No cambies ese archivo local solo para compilar. Si cambian las opciones de Flutter o la configuración de entorno, inspecciona lib/core/config/app_config.dart y flutter build web --help antes de alterar el comando.

### 5.1 Validación obligatoria del artefacto

    $index = Join-Path $root 'build\web\index.html'
    $jsPath = Join-Path $root 'build\web\main.dart.js'
    $headers = Join-Path $root 'build\web\_headers'
    if (!(Test-Path $index))  { throw 'Falta build/web/index.html' }
    if (!(Test-Path $jsPath)) { throw 'Falta build/web/main.dart.js' }
    if (!(Test-Path $headers)) { throw 'Falta build/web/_headers' }
    $js = Get-Content $jsPath -Raw
    if (!$js.Contains('https://inces-lms-api.onrender.com')) {
        throw 'El bundle no contiene la API de producción'
    }
    if ($js.Contains('http://localhost:3001') -or $js.Contains('localhost:3001')) {
        throw 'El bundle contiene una API local; se cancela el despliegue'
    }
    Get-Item $index, $jsPath, $headers | Select-Object FullName, Length, LastWriteTime
    Get-Content $headers

Si una comprobación falla, no publiques. Diagnostica, vuelve a compilar y repite. Comprueba también que web/_headers sea el archivo fuente esperado y que las cabeceras de seguridad/cache estén presentes.

## 6. Publicación en Cloudflare Pages

### 6.1 Autenticación y proyecto

Usa una sesión autenticada de Wrangler o credenciales de despliegue aprobadas. Nunca guardes tokens en el repositorio ni en esta guía.

    Set-Location $root
    npx --yes wrangler whoami
    npx --yes wrangler pages project list

Si Wrangler no está autenticado, detente y completa el inicio de sesión autorizado. Confirma que el proyecto destino se llama exactamente inces-lms.

### 6.2 Publicar producción

Solo después de validar el artefacto de la sección 5:

    npx --yes wrangler pages deploy '.\build\web' --project-name=inces-lms --branch=main
    if ($LASTEXITCODE -ne 0) {
        throw "Cloudflare Pages deploy falló con código $LASTEXITCODE"
    }

Guarda el URL, identificador, rama, entorno y resultado que devuelve Wrangler. Luego consulta el historial:

    npx --yes wrangler pages deployment list --project-name=inces-lms

Confirma que la nueva publicación figura como Production en main. Un URL de preview no demuestra que el dominio principal esté actualizado.

## 7. Render: backend

render.yaml declara un servicio con raíz backend, Dockerfile ./Dockerfile y health check /salud. Si Render tiene auto-deploy habilitado, el push a la rama configurada puede iniciarlo; confírmalo en el Dashboard. render.yaml por sí solo no demuestra que el despliegue haya terminado.

1. Abre el Dashboard de Render y selecciona inces-lms-api.
2. Comprueba el despliegue asociado al SHA/commit esperado.
3. Espera el estado Live/Deploy succeeded y revisa logs si hay errores.
4. Comprueba que las variables secretas requeridas están configuradas, sin imprimir valores.
5. No inicies un segundo deploy si ya hay uno en curso. Antes de un redeploy, verifica commit, rama y estado.

Prueba el endpoint:

    $health = Invoke-WebRequest -Uri 'https://inces-lms-api.onrender.com/salud' -UseBasicParsing -TimeoutSec 30
    if ([int]$health.StatusCode -ne 200) {
        throw 'Health check de Render no devolvió HTTP 200'
    }
    $health.StatusCode
    $health.Content

Prueba CORS desde el origen real del frontend:

    $cors = Invoke-WebRequest -Uri 'https://inces-lms-api.onrender.com/api/v1/admin/invitaciones' -Method Options -Headers @{
        Origin = 'https://inces-lms.pages.dev'
        'Access-Control-Request-Method' = 'GET'
        'Access-Control-Request-Headers' = 'authorization,content-type'
    } -UseBasicParsing -TimeoutSec 30
    $cors.StatusCode
    $cors.Headers['Access-Control-Allow-Origin']

El preflight debe responder con un código 2xx esperado (se ha verificado HTTP 204) y autorizar el origen exacto de producción. Health 200 no sustituye pruebas funcionales.

## 8. Supabase: verificación sin migrar automáticamente

La validación de migraciones en CI no las aplica automáticamente a producción.

1. Revisa el SQL nuevo, el orden, compatibilidad hacia atrás, impacto y estrategia de recuperación.
2. Confirma el proyecto Supabase correcto y el respaldo/plan de recuperación.
3. Ejecuta primero el modo de solo comprobación:

    Set-Location $root
    node .\supabase\apply-migrations.mjs --check

El script puede necesitar SUPABASE_ACCESS_TOKEN en el entorno. Cárgalo de forma segura desde el gestor de secretos o entorno autorizado. No imprimas el valor, no lo pegues en el chat ni lo añadas a una línea de comandos registrada.

Revisa proyecto/ref, migraciones detectadas, pendientes y drift. Si la autenticación falla, detente: no concluyas que no hay pendientes.

No ejecutes node .\supabase\apply-migrations.mjs sin --check en producción salvo autorización explícita para aplicar las migraciones revisadas. No marques migraciones manualmente como aplicadas para ocultar discrepancias. Tras una migración autorizada, repite --check y las pruebas de regresión.

## 9. Verificación posterior

### 9.1 Frontend público y bundle

    $base = 'https://inces-lms.pages.dev'
    $index = Invoke-WebRequest -Uri "$base/?verify=$([guid]::NewGuid().ToString('N'))" -UseBasicParsing -TimeoutSec 30
    if ([int]$index.StatusCode -ne 200) { throw 'Frontend no devuelve HTTP 200' }
    $bundle = Invoke-WebRequest -Uri "$base/main.dart.js?verify=$([guid]::NewGuid().ToString('N'))" -UseBasicParsing -TimeoutSec 60
    $js = $bundle.Content
    if (!$js.Contains('https://inces-lms-api.onrender.com')) {
        throw 'Bundle público no contiene la API esperada'
    }
    if ($js.Contains('localhost:3001')) {
        throw 'Bundle público contiene localhost'
    }
    Write-Output "Frontend HTTP: $([int]$index.StatusCode)"
    Write-Output "Bundle bytes: $($js.Length)"

Si Flutter cambia a salida WASM u otro formato, no asumas que main.dart.js sigue siendo el bundle principal. Inspecciona index.html y flutter_bootstrap.js, descarga el archivo realmente referenciado y aplica las mismas comprobaciones.

### 9.2 Validación funcional mínima en navegador real

- La página carga sin errores fatales en consola.
- Login y cierre de sesión con una cuenta de prueba autorizada.
- Las llamadas de red usan el backend de producción, nunca localhost.
- Un flujo representativo de lectura y escritura con datos de prueba autorizados.
- Una cuenta sin privilegios no puede acceder a operaciones administrativas.
- Los módulos críticos cargan; revisar 4xx/5xx, CORS y fallos de red.
- Revisar invitaciones/recuperación si forman parte del cambio.
- No uses credenciales personales reales ni borres datos reales como prueba.

E2E en CI es evidencia valiosa, pero no sustituye verificar la versión desplegada.

### 9.3 Registrar evidencia

Guarda el SHA de GitHub, enlaces/estados CI, deployment ID/URL y rama de Cloudflare, deployment ID/commit/estado de Render, respuestas HTTP, resultado de Supabase --check y pruebas funcionales. Anota claramente lo que no se pudo verificar.

## 10. Diagnóstico y recuperación

- **Build Flutter lento:** inspecciona logs, CPU/RAM y procesos Flutter/Dart; no ejecutes builds simultáneos. Detén solo un proceso obsoleto identificado y vuelve a compilar una vez.
- **Wrangler sin autenticación:** no publiques; autentica por el procedimiento autorizado y confirma cuenta/proyecto.
- **Bundle apunta a localhost:** cancela publicación, corrige configuración, recompila y vuelve a validar.
- **Render no actualiza:** revisa rama, commit, auto-deploy y logs. No cambies secretos para ocultar el error.
- **CI falla:** inspecciona el job del SHA exacto y repite CI tras corregirlo.
- **Supabase muestra drift o pendientes:** detente y presenta diagnóstico; no migres ni reviertas sin autorización.
- **Frontend y backend desincronizados:** revisa compatibilidad API y orden; prioriza cambios compatibles hacia atrás y verifica ambos servicios.
- **Deploy fallido:** conserva logs, deployment ID y SHA. Rollback solo a una versión conocida como buena y tras revisar implicaciones.

## 11. Formato obligatorio del informe final

- **GitHub:** rama, SHA y coincidencia de HEAD con origin/main.
- **CI:** estado y enlaces de Backend, Flutter, E2E y Supabase.
- **Flutter:** comando, código de salida y verificaciones del artefacto.
- **Cloudflare:** deployment ID/URL, entorno Production y bundle público validado.
- **Render:** deployment ID/commit, estado y health check.
- **Supabase:** resultado de --check; declarar explícitamente si se aplicaron migraciones (por defecto, no).
- **Pruebas funcionales:** qué se comprobó y qué no.
- **Cambios locales excluidos:** enumerarlos sin borrarlos.
- **Riesgos/bloqueadores:** declararlos sin minimizar.

Nunca digas “todo está en producción” si solo se hizo push, si hay deployments en progreso o si no se comprobó el bundle público.

## 12. Referencias oficiales

- Repositorio: https://github.com/Burmistrov4/inces-lms
- GitHub Actions: https://github.com/Burmistrov4/inces-lms/actions
- Cloudflare Pages: https://developers.cloudflare.com/pages/
- Wrangler Pages deploy: https://developers.cloudflare.com/pages/get-started/direct-upload/
- Render deploys: https://render.com/docs/deploys
- Supabase database migrations: https://supabase.com/docs/guides/deployment/database-migrations

---

Última revisión documental: 2026-10-10. Antes de cada despliegue, verifica los nombres de servicios, dominios, workflows, comandos y estado actual de cada plataforma. Actualiza esta guía si la infraestructura cambia.
