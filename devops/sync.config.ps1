# ============================================================================
#  INCES LMS - Configuracion central del pipeline de contexto (DevOps)
#  Este es el UNICO archivo que necesitas editar.
# ============================================================================

# --- Rutas -------------------------------------------------------------------
# Raiz del proyecto = carpeta padre de /devops (se calcula sola)
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Carpeta local donde se genera el contexto y los logs
$OutDir = Join-Path $PSScriptRoot 'out'

# Nombre del archivo consolidado (el que leera Gemini desde Drive)
$ContextFile = 'contexto_proyecto.md'

# --- Google Drive (rclone) ---------------------------------------------------
# Nombre del remoto tal como lo creaste con: rclone config
$RcloneRemote = 'gdrive'

# Carpeta destino dentro de tu Google Drive (se crea automaticamente)
$DriveFolder = 'INCES-LMS-Contexto'

# --- Filtros de contenido ----------------------------------------------------
# Carpetas que NUNCA se recorren ni se listan
$ExcludeDirs = @(
    '.git', '.dart_tool', 'build', 'node_modules', '.idea', '.vscode',
    'coverage', '.autoclaw', '.clinerules', '.continue', 'out', 'dist',
    'ephemeral', '.temp', '.gradle', '.fleet', '.vscode-test',
    # Memoria de trabajo del agente: NO es codigo del proyecto. Ademas de ruido,
    # contiene notas de sesiones antiguas que pueden contradecir decisiones ya
    # tomadas (p.ej. el pivote a MongoDB, cancelado en ADR-006). El bundle viaja a
    # Drive y lo lee un chat web: si entra material obsoleto, el chat lo toma como
    # vigente. La fuente de verdad es ESTADO_DEL_SISTEMA.md, no un log de sesion.
    '.workbuddy-ai'
)

# Carpetas que SI aparecen en el arbol pero cuyo contenido se omite
# (boilerplate de plataformas Flutter: no aportan contexto del LMS)
$OmitContentDirs = @('android', 'ios', 'macos', 'linux', 'windows')

# Archivos que se incluyen PRIMERO, antes que el resto.
#
# Sin esto, el orden es alfabetico por ruta completa y el presupuesto de
# caracteres puede agotarse antes de llegar a ellos. `ESTADO_DEL_SISTEMA.md` es
# el documento puente: es lo primero que debe leer cualquier chat, asi que su
# presencia no puede depender del orden alfabetico ni del tamano del proyecto.
$PriorityFiles = @(
    'ESTADO_DEL_SISTEMA.md',
    'docs/PLAN_MAESTRO_STACK_DEFINITIVO.md',
    'ROADMAP.md'
)

# Extensiones de texto cuyo contenido se incluye en el bundle
$TextExtensions = @(
    '.dart', '.yaml', '.yml', '.json', '.sql', '.md', '.txt', '.ts', '.tsx',
    '.js', '.jsx', '.mjs', '.cjs', '.html', '.css', '.scss', '.sh', '.ps1',
    '.psm1', '.py', '.xml', '.properties', '.gradle', '.kts', '.toml', '.ini',
    '.cfg', '.editorconfig', '.swift', '.kt', '.java', '.h', '.cc', '.cpp',
    '.cmake', '.svg', '.example', '.metadata'
)

# Extensiones que se listan en el arbol pero NO se incluyen (binarios/pesados)
$BinaryExtensions = @(
    '.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.docx', '.doc', '.xlsx',
    '.xls', '.pptx', '.zip', '.rar', '.7z', '.jar', '.dll', '.exe', '.so',
    '.dylib', '.bin', '.dill', '.frag', '.stamp', '.symbols', '.ttf', '.otf',
    '.woff', '.woff2', '.mp4', '.mp3', '.webp', '.bmp', '.lock'
)

# Tamano maximo por archivo para incluir su contenido (KB)
$MaxFileSizeKB = 250

# Limite total del documento generado (caracteres). Protege el contexto de Gemini.
$MaxTotalChars = 1600000

# Profundidad maxima del arbol de carpetas
$MaxTreeDepth = 8

# --- Brief permanente que se inyecta al inicio del contexto ------------------
# Esto viaja SIEMPRE a Drive, asi el chat web nunca pierde las reglas vigentes.
$ProjectBrief = @'
**Proyecto:** LMS INCES - CFS Nacional de Soldadura "Rafael Urdaneta" (La Isabelica)
**Institucion:** INCES / TEG IUTEPI - 4to Semestre - Periodo SA26-2
**Equipo:** Jose Tarazon, Lorenzo Roca, Sleither Vasquez, Adrian Cedeno - Tutor: Prof. Maglis Camacho

## Fuente de verdad
`ESTADO_DEL_SISTEMA.md` (raiz del proyecto) describe el estado real y desplegado.
`docs/PLAN_MAESTRO_STACK_DEFINITIVO.md` contiene los ADR y el plan por fases.
Si algo contradice a esos dos archivos, esos archivos mandan.

## Reglas de Oro (arquitectura vigente)
1. **Poder absoluto del Administrador Maestro:** todo modulo y funcion debe poder
   habilitarse, deshabilitarse y personalizarse dinamicamente desde el cPanel.
2. **Frontend:** Flutter + Dart, 100% responsive (mobile / tablet / desktop) y
   compilable a Web para publicarse en dominio propio.
3. **Base de datos:** PostgreSQL sobre Supabase (Auth + RLS + RPC). **Relacional.**
4. **Backend stateless:** API independiente (Node.js / TypeScript + Fastify),
   desplegable en contenedor (Docker) o en servidor Linux propio. Sin estado en
   disco: la sesion vive en el JWT.
5. **Storage pesado:** Cloudflare R2. La base solo guarda metadata; el backend
   emite Presigned URLs y el frontend sube/descarga directo contra R2.
6. **Modulo descartado:** Certificados / Egresos con QR (M9, fuera de alcance).

## Decisiones ya tomadas - NO reabrir
- **ADR-006: MongoDB fue DESCARTADO.** Se evaluo y se cancelo. No proponer NoSQL,
  ni migraciones a Mongo, ni "flexibilidad de esquemas". El stack es PostgreSQL.
- **ADR-007:** el alta de aspirantes es UNA transaccion en PostgreSQL (trigger
  `handle_new_user`), no dos llamadas desde el cliente.
- **ADR-008:** el auto-registro NUNCA otorga rol. Siempre entra como 'estudiante'.
- El backend no confia en el rol que venga del cliente, jamas.

## Convenciones de codigo
- Idioma del dominio y de los mensajes: **espanol**. Identificadores en espanol.
- Ningun fallo se convierte en `null` ni en lista vacia. O hay dato, o hay error
  tipado (`Result` + `AppException` en Dart; `ErrorApi` + codigo estable en la API).
- Las capas de datos dependen de interfaces (puertos), no de clientes concretos.
  Asi se pueden testear sin red ni credenciales.
- Los comentarios explican **por que**, no que. Nada de comentarios obvios.
'@
