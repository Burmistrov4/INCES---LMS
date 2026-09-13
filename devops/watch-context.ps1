#Requires -Version 5.1
<#
.SYNOPSIS
  Opcion B - Vigilante de contexto en segundo plano (Windows 11).

.DESCRIPTION
  Vigila la carpeta del proyecto con FileSystemWatcher. Cada vez que un archivo
  cambia, reinicia un temporizador de "calma" (debounce). Cuando el proyecto deja
  de cambiar durante N segundos, regenera contexto_proyecto.md y lo sube a Drive.
  Asi no se dispara una subida por cada tecla guardada.

.PARAMETER DebounceSeconds
  Segundos de calma antes de sincronizar. Por defecto 120 (2 minutos).

.PARAMETER NoUpload
  Genera el archivo local sin subirlo (util para probar).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File devops\watch-context.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File devops\watch-context.ps1 -DebounceSeconds 60
#>
[CmdletBinding()]
param(
    [int]$DebounceSeconds = 120,
    [switch]$NoUpload
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sync.config.ps1')

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$logFile = Join-Path $OutDir 'watcher.log'

function Write-WatchLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}

$excludeRegex = '\\(\.git|\.dart_tool|build|node_modules|\.idea|\.vscode|coverage|\.autoclaw|\.clinerules|\.continue|out|\.gradle|ephemeral|\.temp)(\\|$)'

$syncScript = Join-Path $PSScriptRoot 'sync-to-drive.ps1'

$state = [hashtable]::Synchronized(@{
    Timer         = $null
    SyncScript    = $syncScript
    ExcludeRegex  = $excludeRegex
    NoUpload      = [bool]$NoUpload
    Root          = $ProjectRoot
})

$timer = New-Object System.Timers.Timer
$timer.Interval = [double]($DebounceSeconds * 1000)
$timer.AutoReset = $false
$state.Timer = $timer

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $ProjectRoot
$watcher.IncludeSubdirectories = $true
$watcher.InternalBufferSize = 32768
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor `
                        [System.IO.NotifyFilters]::LastWrite -bor `
                        [System.IO.NotifyFilters]::DirectoryName -bor `
                        [System.IO.NotifyFilters]::Size
$watcher.EnableRaisingEvents = $false

# --- Al detectar un cambio: reiniciar el temporizador (debounce) -------------
$onChange = {
    $st = $Event.MessageData
    $full = $Event.SourceEventArgs.FullPath
    if ($full -match $st.ExcludeRegex) { return }
    $st.Timer.Stop()
    $st.Timer.Start()
}

# --- Al expirar la calma: sincronizar ---------------------------------------
$onElapsed = {
    $st = $Event.MessageData
    Write-Host ("[{0}] Proyecto estable. Sincronizando contexto..." -f (Get-Date -Format 'HH:mm:ss'))
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $st.SyncScript, '-Trigger', 'watcher')
    if ($st.NoUpload) { $psArgs += '-NoUpload' }
    try {
        & powershell.exe @psArgs
    }
    catch {
        Write-Host "[watcher] Error al sincronizar: $($_.Exception.Message)"
    }
}

$subscriptions = @()
$subscriptions += Register-ObjectEvent -InputObject $watcher -EventName 'Changed' -SourceIdentifier 'Ctx.Watcher.Changed'  -MessageData $state -Action $onChange
$subscriptions += Register-ObjectEvent -InputObject $watcher -EventName 'Created' -SourceIdentifier 'Ctx.Watcher.Created'  -MessageData $state -Action $onChange
$subscriptions += Register-ObjectEvent -InputObject $watcher -EventName 'Deleted' -SourceIdentifier 'Ctx.Watcher.Deleted'  -MessageData $state -Action $onChange
$subscriptions += Register-ObjectEvent -InputObject $watcher -EventName 'Renamed' -SourceIdentifier 'Ctx.Watcher.Renamed'  -MessageData $state -Action $onChange
$subscriptions += Register-ObjectEvent -InputObject $timer   -EventName 'Elapsed' -SourceIdentifier 'Ctx.Watcher.Debounce' -MessageData $state -Action $onElapsed

$watcher.EnableRaisingEvents = $true
$timer.Start()

Write-WatchLog "Vigilando: $ProjectRoot"
if ($NoUpload) {
    Write-WatchLog "Debounce: $DebounceSeconds s | Subida: DESACTIVADA (modo prueba)"
} else {
    Write-WatchLog "Debounce: $DebounceSeconds s | Destino: ${RcloneRemote}:${DriveFolder}"
}
Write-WatchLog 'Pulsa Ctrl+C para detener el vigilante.'

try {
    while ($true) { Start-Sleep -Seconds 5 }
}
finally {
    $timer.Stop()
    $watcher.EnableRaisingEvents = $false
    Get-EventSubscriber -ErrorAction SilentlyContinue |
        Where-Object { $_.SourceIdentifier -like 'Ctx.Watcher.*' } |
        Unregister-Event -ErrorAction SilentlyContinue
    Get-Job -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Ctx.Watcher.*' } |
        Remove-Job -Force -ErrorAction SilentlyContinue
    $watcher.Dispose()
    $timer.Dispose()
    Write-WatchLog 'Vigilante detenido.'
}
