# INSTRUCCIÓN DE CONTINUIDAD PARA ANTIGRAVITY — MAIN DE GITHUB Y RUTA CANÓNICA

**Lee y ejecuta esta instrucción junto con el documento `ULTRA_MEGA_PROMPT_RETOMAR_ANTIGRAVITY_INCES_LMS_2026-10-10.md`.** Esta instrucción refuerza las reglas de ubicación y Git y tiene prioridad si alguna instrucción secundaria sugiere trabajar en otra copia.

## ORDEN INEQUÍVOCA

Debes continuar el proyecto existente INCES-LMS **exclusivamente desde esta carpeta canónica**:

`C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT`

Y debes trabajar sobre la **rama local `main` de ese repositorio, vinculada a la rama `main` del repositorio oficial en GitHub**.

No inventes otra carpeta, no clones una segunda copia, no crees un proyecto paralelo y no migres el trabajo a otra ruta local. No trabajes desde `Downloads`, `Desktop` con otro nombre, carpetas temporales, worktrees, directorios generados por Antigravity ni repositorios duplicados. Las carpetas temporales estrictamente necesarias para artefactos de prueba pueden usarse sólo como artefactos temporales; **el código fuente y todos los cambios del proyecto deben originarse y aplicarse en la ruta canónica indicada**. No conviertas un artefacto temporal en una segunda copia de desarrollo.

## PASO 1 — DEMUESTRA QUE ESTÁS EN EL REPOSITORIO CORRECTO

Antes de editar cualquier archivo, abre una terminal y ejecuta desde la ruta exacta:

```powershell
Set-Location 'C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT'
Get-Location
git rev-parse --show-toplevel
git branch --show-current
git status --short --branch
git rev-parse HEAD
git remote -v
git branch -vv
```

Comprueba que:
1. `Get-Location` y `git rev-parse --show-toplevel` identifican la carpeta canónica indicada.
2. La rama activa es `main`.
3. El remoto `origin` apunta al repositorio GitHub correcto de INCES-LMS, verificándolo con la configuración Git existente. No inventes ni sustituyas una URL de remoto.
4. Puedes identificar la relación entre `main` local y `origin/main`: si están sincronizadas, adelantadas, atrasadas o divergidas.
5. Comprendes todos los cambios sin confirmar y archivos sin seguimiento.

Si Antigravity abre automáticamente otra carpeta o una copia distinta, **no trabajes allí**. Cierra/cambia el workspace y abre la ruta canónica. No ejecutes `git init`, no añadas un remoto nuevo y no crees otro clon para “arreglarlo”.

## PASO 2 — REGLAS PARA LA RAMA MAIN

- La rama de trabajo es `main`. No crees ni cambies a ramas `feature/*`, `dev`, `antigravity/*` u otras ramas para desarrollar este encargo.
- No uses `git worktree add` para crear una copia paralela.
- No hagas `git clone` de este proyecto en otra carpeta.
- No ejecutes `git init` dentro de otra ruta.
- No hagas `reset --hard`, `clean -fd`, rebase destructivo, checkout que descarte cambios, borrados masivos ni restauraciones de carpetas completas.
- No sobrescribas el trabajo existente de ARIA/Work Buddy u otros agentes. Revisa primero `git status`, los diffs y el contenido actual de cada archivo.
- Puedes editar archivos, añadir pruebas y actualizar documentación directamente en la carpeta canónica sobre `main`, preservando el trabajo preexistente.
- **Trabajar sobre la rama `main` no significa que tengas permiso para publicar.** No hagas commit, push, merge ni despliegue sin autorización explícita del propietario.
- No hagas `git pull`, `fetch` con cambios automáticos ni sincronizaciones que alteren el estado sin inspeccionar antes las diferencias y confirmar que no se perderá trabajo local. Si necesitas consultar GitHub, inspecciona primero el estado local, los remotos y la divergencia; descarga referencias de manera no destructiva y explica cualquier conflicto antes de resolverlo.
- No sustituyas la rama local por la remota ni asumas que `origin/main` es más reciente y por eso debes descartar los cambios locales. Resuelve discrepancias preservando todos los cambios útiles y sin reescrituras destructivas.
- No marques el trabajo como publicado o sincronizado si sólo existe en el equipo local.

## PASO 3 — SI MAIN LOCAL Y ORIGIN/MAIN DIFIEREN

No improvises ni fuerces sincronización.

1. Registra HEAD local, HEAD de `origin/main` si puede consultarse de forma segura, estado del worktree y commits de diferencia.
2. Inspecciona los commits divergentes y los cambios locales.
3. No sobrescribas cambios locales sin seguimiento ni archivos no confirmados.
4. No hagas merge, rebase, reset, commit o push para resolverlo automáticamente.
5. Continúa las tareas locales seguras que no dependan de esa divergencia.
6. Documenta con precisión qué está desincronizado y qué autorización sería necesaria para una acción de publicación o integración.

## PASO 4 — CONTINÚA EL ULTRA-MEGA PROMPT, NO LO REEMPLACES

Una vez confirmada la ruta y la rama:
1. Lee el archivo `ULTRA_MEGA_PROMPT_RETOMAR_ANTIGRAVITY_INCES_LMS_2026-10-10.md` completo o por secciones.
2. Sigue los documentos de estado y handoff enumerados allí.
3. Verifica el estado real del proyecto y de las herramientas; no asumas que los resultados históricos siguen vigentes.
4. Empieza por la revisión de G3/performance, regresión, paginación y teardown E2E, de acuerdo con el mega prompt.
5. Continúa de forma autónoma por las fases siguientes cuando se cumplan sus dependencias.
6. Haz todos los cambios de código y documentación en la ruta canónica.
7. Mantén la memoria y el handoff actualizados sin borrar información de otros agentes.
8. No te detengas después de redactar un plan: ejecuta el siguiente paso seguro y verificable.

## PASO 5 — VALIDACIÓN DE UBICACIÓN ANTES Y DESPUÉS DE CADA BLOQUE

Antes de iniciar un bloque importante de trabajo y al terminarlo, comprueba:

```powershell
Set-Location 'C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT'
git rev-parse --show-toplevel
git branch --show-current
git status --short --branch
```

Si la terminal o el editor cambió de directorio, vuelve a la ruta canónica antes de seguir. Si una herramienta necesita generar un archivo temporal, deja claro que es un artefacto temporal y evita que se convierta en una copia alternativa del código fuente.

## INFORME OBLIGATORIO AL FINAL

Reporta:
- ruta de trabajo verificada;
- raíz Git verificada;
- rama activa verificada;
- remoto y relación local/remota, sin exponer credenciales;
- archivos modificados en la carpeta canónica;
- pruebas ejecutadas y sus códigos de salida reales;
- cualquier bloqueo;
- siguiente acción;
- confirmación explícita de que no creaste una segunda copia del proyecto y no hiciste commit/push/deploy.

## INSTRUCCIÓN FINAL

**Continúa el trabajo del ultra-mega prompt en el repositorio existente, en `main`, en la carpeta exacta `C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT`. No inventes rutas, no dupliques el proyecto y no cambies de rama. Primero demuestra con comandos que estás allí; después prosigue el trabajo técnico con evidencia.**
