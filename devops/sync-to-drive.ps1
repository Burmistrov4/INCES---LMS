#Requires -Version 5.1
<#
.SYNOPSIS
  Reconstruye contexto_proyecto.md y lo sube a Google Drive usando rclone.

.DESCRIPTION
  Es el motor compartido por las dos opciones de automatizacion:
    - Opcion A: hook post-commit  -> -Trigger git-hook
    - Opcion B: vigilante en fondo -> -Trigger watcher

.PARAMETER Trigger
  Origen de la ejecucion (git-hook | watcher | manual). Solo se usa para el log.

.PARAMETER NoUpload
  Genera el archivo local pero no sube nada a Drive (modo prueba).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File devops\sync-to-drive.ps1 -NoUpload
#>
[CmdletBinding()]
param(
    [string]$Trigger = 'manual',
    [switch]$NoUpload
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync.config.ps1')

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$logFile = Join-Path $OutDir 'sync.log'

function Write-SyncLog {
    param([string]$Level, [string]$Message)
    $line = "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Trigger, $Level, $Message
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}

try {
    $mdPath = Join-Path $OutDir $ContextFile

    & (Join-Path $PSScriptRoot 'build-context.ps1') -OutputPath $mdPath | Out-Null
    Write-SyncLog 'INFO' "Contexto generado: $mdPath"

    if ($NoUpload) {
        Write-SyncLog 'INFO' 'Modo -NoUpload: se omite la subida a Drive.'
        return
    }

    if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
        throw 'rclone no esta instalado o no esta en el PATH. Revisa devops/README.md (seccion 1).'
    }

    $remoteDir = '{0}:{1}' -f $RcloneRemote, $DriveFolder
    $remoteFile = "$remoteDir/$ContextFile"

    & rclone mkdir $remoteDir 2>&1 | Out-Null

    $output = & rclone copyto $mdPath $remoteFile --drive-use-trash=false 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("rclone fallo (codigo {0}): {1}" -f $LASTEXITCODE, ($output -join ' | '))
    }

    Write-SyncLog 'OK' "Subido a Drive: $remoteFile"
}
catch {
    Write-SyncLog 'ERROR' $_.Exception.Message
    exit 1
}
