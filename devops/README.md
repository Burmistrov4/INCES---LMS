# DevOps - Pipeline de Contexto Continuo (INCES LMS)

Objetivo: que el chat web siempre tenga el contexto del proyecto al 100%, sin
subir miles de archivos. El pipeline consolida el arbol y el codigo esencial en
**un solo archivo** (`contexto_proyecto.md`) y lo sube a tu Google Drive.

```
Proyecto local  ->  build-context.ps1  ->  contexto_proyecto.md  ->  rclone  ->  Google Drive  ->  chat web
```

---

## 1. Instalar rclone en Windows 11

`rclone` es el estandar de facto para sincronizar con Google Drive por CLI.

**Opcion recomendada (winget, ya lo tienes instalado):**

```powershell
winget install --id Rclone.Rclone -e --accept-source-agreements --accept-package-agreements
```

**Alternativa:** descarga el zip desde https://rclone.org/downloads/, descomprimetelo
en `C:\Tools\rclone\` y agrega esa carpeta al `PATH`.

Verifica (abre una terminal nueva):

```powershell
rclone version
```

### 1.1 Autenticar con OAuth (una sola vez)

```powershell
rclone config
```

Responde asi:

| Pregunta | Respuesta |
|---|---|
| `n/s/q>` (New remote) | `n` |
| `name>` | `gdrive` |
| `Storage>` | elige el numero de **Google Drive** (suele ser `18`) |
| `client_id>` | Enter (vacio) |
| `client_secret>` | Enter (vacio) |
| `scope>` | `1` (acceso total) |
| `root_folder_id>` | Enter |
| `service_account_file>` | Enter |
| `Edit advanced config?` | `n` |
| `Use web browser to automatically authenticate?` | `y` |
| `Configure this as a team drive?` | `n` |
| `y/e/d>` (Keep this remote) | `y` |
| `q` (salir) | `q` |

Se abre el navegador: inicia sesion con **lorenzoroca333@gmail.com** y acepta los
permisos. El token queda guardado en
`C:\Users\Loro\AppData\Roaming\rclone\rclone.conf`.

Verifica la conexion:

```powershell
rclone lsd gdrive:
```

> **Nota:** el `client_id` vacio usa el cliente compartido de rclone y puede sufrir
> limites de velocidad. Si notas throttling, crea tu propio `client_id` en Google
> Cloud Console (Drive API, tipo "Desktop app") y vuelve a ejecutar `rclone config`.

> **Privacidad:** con `scope 1` rclone ve todo tu Drive. Si prefieres limitarlo a
> una sola carpeta, usa `scope 3` (drive.file) y comparte la carpeta destino con
> la app; el resto de los comandos de este README no cambian.

### 1.2 Ajustes de configuracion

Edita `devops/sync.config.ps1` si quieres cambiar:

- `$RcloneRemote` -> nombre del remoto (`gdrive` por defecto)
- `$DriveFolder` -> carpeta destino en Drive (`INCES-LMS-Contexto`)
- `$ExcludeDirs` / `$TextExtensions` -> que se incluye en el bundle

---

## 2. Probar el pipeline (sin subir nada)

```powershell
powershell -ExecutionPolicy Bypass -File devops\build-context.ps1
```

Genera `devops\out\contexto_proyecto.md`. Revisalo antes de subirlo.

Prueba la subida real:

```powershell
powershell -ExecutionPolicy Bypass -File devops\sync-to-drive.ps1
```

---

## 3. Opcion A - Git Hook (post-commit / post-merge)

Ideal si prefieres que el contexto se actualice **en cada commit**.

```powershell
powershell -ExecutionPolicy Bypass -File devops\install-git-hook.ps1
```

Que hace:

- Anade un bloque idempotente a `.git/hooks/post-commit` y `.git/hooks/post-merge`.
- Respalda cualquier hook previo como `<hook>.inces-bak`.
- Lanza la sincronizacion **en segundo plano**, para que el commit no se bloquee.

Desinstalar:

```powershell
powershell -ExecutionPolicy Bypass -File devops\install-git-hook.ps1 -Uninstall
```

Verificacion: haz un commit y abre `devops\out\sync.log`.

---

## 4. Opcion B - Vigilante en segundo plano (PowerShell Watcher)

Ideal si trabajas con agentes autonomos que guardan archivos sin hacer commit.

```powershell
powershell -ExecutionPolicy Bypass -File devops\watch-context.ps1
```

- Vigila toda la carpeta del proyecto con `FileSystemWatcher`.
- **Debounce de 120 s** (configurable con `-DebounceSeconds`): solo sube cuando el
  proyecto deja de cambiar, no en cada guardado.
- Ignora `.git`, `build`, `node_modules`, `.dart_tool`, `.idea`, `out`, etc.

Variantes utiles:

```powershell
# Debounce de 1 minuto
powershell -ExecutionPolicy Bypass -File devops\watch-context.ps1 -DebounceSeconds 60

# Modo prueba: regenera el archivo pero no sube a Drive
powershell -ExecutionPolicy Bypass -File devops\watch-context.ps1 -NoUpload
```

Detener: `Ctrl+C` en la ventana.

### 4.1 Arrancarlo automaticamente al iniciar sesion (opcional)

Crea una tarea programada que se ejecute al inicio de sesion:

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT\devops\watch-context.ps1"'
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'INCES-LMS-Context-Watcher' -Action $action -Trigger $trigger -RunLevel Limited -Force
```

Eliminar la tarea:

```powershell
Unregister-ScheduledTask -TaskName 'INCES-LMS-Context-Watcher' -Confirm:$false
```

---

### 4.2 Barrido de subidas abandonadas de M5 (opcional, y **borra de verdad**)

> **Leelo antes de registrarla.** Esta tarea borra objetos de R2 y eso **no se
> puede deshacer**. Sin la bandera `--confirmar` el script no escribe nada —modo
> simulacion, que es su comportamiento por defecto—, asi que una tarea sin esa
> bandera no barre: solo deja constancia en el registro. La bandera es lo que la
> convierte en algo que borra.

Por que es codigo y no configuracion: el ciclo de vida de R2 filtra por prefijo y
no sabe nada del estado de la fila, asi que una regla `--expire-days` sobre
`m5_archivos/` borraria tambien los archivos **confirmados**. Ver
`docs/CONFIGURACION_R2.md` §3.6 y §3.7.

**Primero en simulacion, y leer lo que dice:**

```powershell
cd "C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT"
npx tsx backend/scripts/limpiar-pendientes.mts
```

Una vez al dia, ya con la bandera:

```powershell
$raiz    = 'C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT'
$action  = New-ScheduledTaskAction -Execute 'cmd.exe' `
  -Argument '/c cd /d "C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT" && npx tsx backend\scripts\limpiar-pendientes.mts --confirmar' `
  -WorkingDirectory $raiz
$trigger = New-ScheduledTaskTrigger -Daily -At 03:00
Register-ScheduledTask -TaskName 'INCES-LMS-Limpiar-Pendientes' -Action $action -Trigger $trigger -RunLevel Limited -Force
```

Eliminar la tarea:

```powershell
Unregister-ScheduledTask -TaskName 'INCES-LMS-Limpiar-Pendientes' -Confirm:$false
```

**Tres cosas que hay que saber antes de darla por buena:**

- **Si `npx` no aparece**, el Programador de tareas no hereda el `PATH` de la
  sesion. Sustituye `npx tsx` por la ruta absoluta del ejecutable:
  `"C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT\backend\node_modules\.bin\tsx.cmd"`.
  Se comprueba ejecutando la tarea a mano (`Start-ScheduledTask`) y mirando el
  resultado, no esperando a las 03:00.
- **La maquina no siempre esta encendida.** Una tarea a las 03:00 **no se ejecuta**
  si el equipo estaba apagado; para eso hay que marcar `-StartWhenAvailable` en el
  *settings* de la tarea, o elegir `-AtLogOn`. Y el proyecto tiene cortes
  electricos, asi que una pasada perdida es normal y no un fallo: el barrido es
  **idempotente** y la siguiente recupera lo que falte. Perder una pasada no deja
  nada a medias.
- **La tarea va contra el script, no contra la ruta de la API, y es a proposito.**
  `POST /api/v1/admin/archivos/limpiar` exige un JWT de administrador, y un JWT de
  Supabase caduca en una hora: la tarea tendria que guardar la contrasena de una
  persona para pedir uno nuevo en cada ejecucion, y esa contrasena no se puede
  rotar sin romper la tarea. El `.env` de la maquina ya tiene la clave de
  servicio, que es **mas** poderosa que cualquier JWT de administrador; guardar
  ademas una contrasena de persona seria empeorar la seguridad sin ganar nada. La
  ruta queda para el cPanel y para el despliegue en la nube, donde nadie tiene la
  maquina.

---

## 5. Uso del contexto desde el chat web

1. Abre la carpeta `INCES-LMS-Contexto` en Google Drive.
2. Comparte `contexto_proyecto.md` con "Cualquier persona con el enlace" (solo lectura).
3. Pega ese enlace en el chat web y pide que lo lea antes de responder.

Como el archivo se sobreescribe en cada sincronizacion, el enlace **nunca cambia**
y el chat siempre lee la ultima version.

---

## 6. Archivos del pipeline

| Archivo | Rol |
|---|---|
| `sync.config.ps1` | Configuracion central (unico archivo a editar) |
| `build-context.ps1` | Consolida arbol + codigo en `contexto_proyecto.md` |
| `sync-to-drive.ps1` | Motor: construye y sube a Drive con rclone |
| `watch-context.ps1` | Opcion B: vigilante con debounce |
| `install-git-hook.ps1` | Opcion A: instala/desinstala los hooks |
| `hooks/post-commit` | Copia de referencia del hook |
| `out/` | Salida: contexto generado + `sync.log` + `watcher.log` |

## 7. Solucion de problemas

| Sintoma | Causa / Solucion |
|---|---|
| `rclone no esta instalado o no esta en el PATH` | Abre una terminal nueva tras instalar, o reinicia la sesion |
| `rclone fallo (codigo 4)` | El remoto o la carpeta no existe; ejecuta `rclone config` de nuevo |
| El hook no se ejecuta | `git config --get core.hooksPath` no debe devolver nada |
| `sync.log` no aparece | El hook no se instalo; revisa que exista `.git/hooks/post-commit` |
| Subidas muy frecuentes | Sube `-DebounceSeconds` en la Opcion B |
| Archivo de contexto enorme | Reduce `$TextExtensions` o baja `$MaxFileSizeKB` |
