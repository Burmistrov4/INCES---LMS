#Requires -Version 5.1
<#
.SYNOPSIS
  Opcion A - Instala (o desinstala) el hook de Git que sincroniza el contexto.

.DESCRIPTION
  Anade un bloque idempotente a .git/hooks/post-commit y .git/hooks/post-merge.
  El bloque lanza devops\sync-to-drive.ps1 en segundo plano, de modo que el
  commit NO se bloquea esperando la subida a Drive.
  Si ya existe un hook previo, se respalda como <hook>.inces-bak y se conserva.

.PARAMETER Uninstall
  Elimina el bloque instalado (y el hook si queda vacio).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File devops\install-git-hook.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File devops\install-git-hook.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync.config.ps1')

$gitDir = Join-Path $ProjectRoot '.git'
if (-not (Test-Path $gitDir)) {
    throw "No se encontro '.git' en $ProjectRoot. Ejecuta 'git init' primero."
}

$hooksDir = Join-Path $gitDir 'hooks'
if (-not (Test-Path $hooksDir)) {
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
}

$customHooksPath = $null
try { $customHooksPath = (& git -C $ProjectRoot config --get core.hooksPath 2>$null) } catch { }
if ($customHooksPath) {
    Write-Warning "core.hooksPath apunta a '$customHooksPath'. Git ignorara .git/hooks. Quitalo con: git config --unset core.hooksPath"
}

$hookNames = @('post-commit', 'post-merge')
$marker    = '# >>> INCES-LMS context sync >>>'
$endMarker = '# <<< INCES-LMS context sync <<<'

$hookBody = @'
# >>> INCES-LMS context sync >>>
# Sincroniza contexto_proyecto.md con Google Drive tras cada commit / merge.
# Generado por devops/install-git-hook.ps1 - no editar a mano.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && exit 0
SYNC="$ROOT/devops/sync-to-drive.ps1"
[ -f "$SYNC" ] || exit 0
# Se lanza en segundo plano para no bloquear el commit.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SYNC" -Trigger "git-hook" >/dev/null 2>&1 &
exit 0
# <<< INCES-LMS context sync <<<
'@

$lf = "`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$hookBodyLf = ($hookBody -replace "`r`n", $lf).Trim()

foreach ($name in $hookNames) {
    $hookPath = Join-Path $hooksDir $name

    if ($Uninstall) {
        if (-not (Test-Path $hookPath)) { Write-Host "[SKIP] No existe: $hookPath"; continue }
        $content = [System.IO.File]::ReadAllText($hookPath)
        if ($content -notlike "*$marker*") { Write-Host "[SKIP] Sin bloque de sincronizacion: $hookPath"; continue }

        $pattern = [regex]::Escape($marker) + '[\s\S]*?' + [regex]::Escape($endMarker) + "(\r?\n)?"
        $cleaned = [regex]::Replace($content, $pattern, '')

        $backup = "$hookPath.inces-bak"
        if ((Test-Path $backup) -and ($cleaned.Trim() -le '#!/bin/sh')) {
            Copy-Item -LiteralPath $backup -Destination $hookPath -Force
            Write-Host "[OK] Hook restaurado desde backup: $hookPath"
        }
        elseif ($cleaned.Trim() -eq '#!/bin/sh' -or $cleaned.Trim() -eq '') {
            Remove-Item -LiteralPath $hookPath -Force
            Write-Host "[OK] Hook eliminado: $hookPath"
        }
        else {
            [System.IO.File]::WriteAllText($hookPath, $cleaned, $utf8NoBom)
            Write-Host "[OK] Bloque removido, se conservo el resto: $hookPath"
        }
        continue
    }

    if (Test-Path $hookPath) {
        $existing = [System.IO.File]::ReadAllText($hookPath)
        if ($existing -like "*$marker*") {
            Write-Host "[SKIP] Ya estaba instalado: $hookPath"
            continue
        }
        $backup = "$hookPath.inces-bak"
        if (-not (Test-Path $backup)) {
            Copy-Item -LiteralPath $hookPath -Destination $backup -Force
            Write-Host "[INFO] Backup creado: $backup"
        }
        $newContent = $existing.TrimEnd() + $lf + $lf + $hookBodyLf + $lf
    }
    else {
        $newContent = '#!/bin/sh' + $lf + $lf + $hookBodyLf + $lf
    }

    [System.IO.File]::WriteAllText($hookPath, $newContent, $utf8NoBom)
    Write-Host "[OK] Hook instalado: $hookPath"
}

if (-not $Uninstall) {
    Write-Host ''
    Write-Host 'Listo. Haz un commit y revisa devops\out\sync.log para confirmar la subida.'
}
