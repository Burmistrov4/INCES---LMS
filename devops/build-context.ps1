#Requires -Version 5.1
<#
.SYNOPSIS
  Genera contexto_proyecto.md: un unico archivo con el arbol del proyecto y el
  codigo esencial, listo para que un chat web lo lea como contexto completo.

.DESCRIPTION
  Recorre el proyecto podando carpetas pesadas (.git, build, node_modules,
  .dart_tool, etc.), incluye el contenido de los archivos de texto relevantes y
  omite binarios (solo los lista en el arbol con su tamano).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File devops\build-context.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File devops\build-context.ps1 -OutputPath C:\temp\ctx.md
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync.config.ps1')

if (-not $OutputPath) {
    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    $OutputPath = Join-Path $OutDir $ContextFile
}

$bt = [string][char]96
$fence = $bt + $bt + $bt

# ------------------------------ Helpers -------------------------------------

function Test-ExcludedDir {
    param([string]$Name)
    return ($ExcludeDirs -contains $Name)
}

function Test-OmitContentDir {
    param([string]$Name)
    return ($OmitContentDirs -contains $Name)
}

function Get-RelPath {
    param([string]$FullPath)
    $rel = $FullPath.Substring($ProjectRoot.Length)
    return ($rel -replace '\\', '/').TrimStart('/')
}

function Test-TextFile {
    param([string]$Name)
    # Cualquier `.env*` es configuración local y puede llevar credenciales. Sólo
    # se admite la plantilla `.env.example`.
    #
    # Se comprueba por NOMBRE y antes que por extensión: `.env.json` se colaba
    # porque su extensión es `.json`, que sí figura en $TextExtensions. El filtro
    # miraba la extensión y nunca el nombre, así que un archivo de credenciales
    # con extensión «de texto» viajaba a Drive sin que nadie lo notara.
    if ($Name -like '.env*' -and $Name -ne '.env.example') { return $false }

    $ext = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
    if ($BinaryExtensions -contains $ext) { return $false }
    if ($TextExtensions -contains $ext) { return $true }
    if ($Name -eq '.gitignore' -or $Name -eq '.env.example') { return $true }
    return $false
}

function Get-FenceLang {
    param([string]$Name)
    switch ([System.IO.Path]::GetExtension($Name).ToLowerInvariant()) {
        '.dart' { 'dart' }
        '.yaml' { 'yaml' }
        '.yml'  { 'yaml' }
        '.json' { 'json' }
        '.sql'  { 'sql' }
        '.md'   { 'markdown' }
        '.ts'   { 'typescript' }
        '.tsx'  { 'tsx' }
        '.js'   { 'javascript' }
        '.html' { 'html' }
        '.css'  { 'css' }
        '.scss' { 'scss' }
        '.sh'   { 'bash' }
        '.ps1'  { 'powershell' }
        '.psm1' { 'powershell' }
        '.py'   { 'python' }
        '.xml'  { 'xml' }
        '.swift'{ 'swift' }
        '.kt'   { 'kotlin' }
        '.java' { 'java' }
        '.cpp'  { 'cpp' }
        '.cc'   { 'cpp' }
        '.h'    { 'cpp' }
        '.cmake'{ 'cmake' }
        '.toml' { 'toml' }
        '.ini'  { 'ini' }
        '.svg'  { 'svg' }
        '.txt'  { 'text' }
        default { '' }
    }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1048576) { return ('{0:N1} MB' -f ($Bytes / 1048576)) }
    if ($Bytes -ge 1024)    { return ('{0:N1} KB' -f ($Bytes / 1024)) }
    return "$Bytes B"
}

# --------------------------- Recoleccion ------------------------------------

$sb = New-Object System.Text.StringBuilder

function Add-Tree {
    param([string]$Path, [string]$Prefix, [int]$Depth)
    if ($Depth -ge $MaxTreeDepth) { return }
    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $isLast = ($i -eq $items.Count - 1)
        $branch = if ($isLast) { '`-- ' } else { '|-- ' }
        if ($item.PSIsContainer) {
            if (Test-ExcludedDir $item.Name) {
                [void]$sb.AppendLine("$Prefix$branch$($item.Name)/  [omitido]")
                continue
            }
            [void]$sb.AppendLine("$Prefix$branch$($item.Name)/")
            $childPrefix = $Prefix + $(if ($isLast) { '    ' } else { '|   ' })
            Add-Tree -Path $item.FullName -Prefix $childPrefix -Depth ($Depth + 1)
        }
        else {
            [void]$sb.AppendLine("$Prefix$branch$($item.Name)  ($(Format-Size $item.Length))")
        }
    }
}

function Get-ContentCandidates {
    param([string]$Path, [int]$Depth = 0)
    if ($Depth -gt $MaxTreeDepth) { return }
    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            if (Test-ExcludedDir $item.Name) { continue }
            if (Test-OmitContentDir $item.Name) { continue }
            Get-ContentCandidates -Path $item.FullName -Depth ($Depth + 1)
        }
        else {
            if ($item.Length -gt ($MaxFileSizeKB * 1024)) { continue }
            if (-not (Test-TextFile $item.Name)) { continue }
            $item
        }
    }
}

# ------------------------------ Cabecera ------------------------------------

$gitBranch = ''
$gitCommit = ''
try {
    $gitBranch = (& git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null)
    $gitCommit = (& git -C $ProjectRoot rev-parse --short HEAD 2>$null)
} catch { }

[void]$sb.AppendLine('# Contexto del Proyecto - INCES LMS')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("> **Generado:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("> **Raiz local:** $bt$ProjectRoot$bt")
if ($gitCommit) { [void]$sb.AppendLine("> **Git:** rama $bt$gitBranch$bt - commit $bt$gitCommit$bt") }
[void]$sb.AppendLine('> *Archivo autogenerado por el pipeline DevOps. No editar a mano.*')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 0. Brief y Reglas de Oro')
[void]$sb.AppendLine('')
[void]$sb.AppendLine($ProjectBrief.Trim())
[void]$sb.AppendLine('')
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 1. Arbol del proyecto')
[void]$sb.AppendLine('')
[void]$sb.AppendLine($fence + 'text')
[void]$sb.AppendLine((Split-Path $ProjectRoot -Leaf) + '/')
Add-Tree -Path $ProjectRoot -Prefix '' -Depth 0
[void]$sb.AppendLine($fence)
[void]$sb.AppendLine('')

# ------------------------- Contenido de archivos ----------------------------

[void]$sb.AppendLine('## 2. Contenido de archivos esenciales')
[void]$sb.AppendLine('')

$allFiles = @(Get-ContentCandidates -Path $ProjectRoot | Sort-Object FullName)

# --- Archivos prioritarios ---------------------------------------------------
# Se colocan los primeros, antes del orden alfabetico. Si dependieran del orden
# alfabetico, el presupuesto de caracteres podria agotarse antes de llegar a
# ellos y el chat recibiria el codigo sin el documento que lo explica.
$prioritarios = @()
$prioritariosAusentes = @()

foreach ($rel in $PriorityFiles) {
    $ruta = Join-Path $ProjectRoot ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $ruta -PathType Leaf) {
        $item = Get-Item -LiteralPath $ruta
        if ($item.Length -le ($MaxFileSizeKB * 1024)) {
            $prioritarios += $item
        }
        else {
            $prioritariosAusentes += "$rel (supera $MaxFileSizeKB KB)"
        }
    }
    else {
        $prioritariosAusentes += "$rel (no existe)"
    }
}

$nombresPrioritarios = @($prioritarios | ForEach-Object { $_.FullName })
$resto = @($allFiles | Where-Object { $nombresPrioritarios -notcontains $_.FullName })
$ordenados = @($prioritarios) + @($resto)

if ($prioritariosAusentes.Count -gt 0) {
    Write-Warning ("Archivos prioritarios no incluidos: " + ($prioritariosAusentes -join '; '))
}

$included = 0
$truncated = $false

foreach ($file in $ordenados) {
    $rel = Get-RelPath $file.FullName
    $lang = Get-FenceLang $file.Name
    $raw = [System.IO.File]::ReadAllText($file.FullName)
    $raw = $raw -replace "`r`n", "`n"
    $entry = '### ' + $bt + $rel + $bt + "`n`n" + $fence + $lang + "`n" + $raw + "`n" + $fence + "`n`n"
    if (($sb.Length + $entry.Length) -gt $MaxTotalChars) {
        $truncated = $true
        break
    }
    [void]$sb.Append($entry)
    $included++
}

# ------------------------------ Estadisticas --------------------------------

[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 3. Estadisticas del bundle')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Metrica | Valor |')
[void]$sb.AppendLine('|---|---|')
[void]$sb.AppendLine("| Archivos con contenido incluido | $included |")
[void]$sb.AppendLine("| Archivos candidatos detectados | $($allFiles.Count) |")
[void]$sb.AppendLine("| Archivos prioritarios incluidos | $($prioritarios.Count) de $($PriorityFiles.Count) |")
if ($prioritariosAusentes.Count -gt 0) {
    [void]$sb.AppendLine("| Prioritarios ausentes | $($prioritariosAusentes -join '; ') |")
}
[void]$sb.AppendLine("| Tamano del documento | $(Format-Size ([System.Text.Encoding]::UTF8.GetByteCount($sb.ToString()))) |")
[void]$sb.AppendLine("| Truncado por limite de seguridad | $truncated |")
[void]$sb.AppendLine('')

# -------------------------------- Escritura ---------------------------------

$outDirFinal = Split-Path -Parent $OutputPath
if ($outDirFinal -and -not (Test-Path $outDirFinal)) {
    New-Item -ItemType Directory -Path $outDirFinal -Force | Out-Null
}

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), $enc)

Write-Host "[OK] Contexto generado: $OutputPath ($(Format-Size ([System.Text.Encoding]::UTF8.GetByteCount($sb.ToString()))), $included archivos)"
Write-Output $OutputPath
