# controller.ps1 ? Steuert die EXE oder das PS1
# Usage:
#   .\controller.ps1 start
#   .\controller.ps1 stop
#   .\controller.ps1 status
#   .\controller.ps1 tail

[CmdletBinding()]
param(
    [ValidateSet('start','stop','status','tail')]
    [string]$Action = 'status',
    [int]$IntervalSeconds = 10
)

$ErrorActionPreference = 'Stop'

# Pfade ermitteln
$Root          = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\src
$ProjRoot      = Split-Path -Parent $Root                          # Projekt-Root
$DistDir       = Join-Path $ProjRoot 'dist'
$LogsDir       = Join-Path $ProjRoot 'logs'
$ExePath       = Join-Path $DistDir 'monitor.exe'
$PsPath        = Join-Path $Root  'monitor.ps1'
$HeartbeatPath = Join-Path $LogsDir 'heartbeat.json'
$StopSignal    = Join-Path $LogsDir 'stop.signal'
$LogPath       = Join-Path $LogsDir 'system.log'

# Sicherstellen, dass logs existieren
if (-not (Test-Path $LogsDir)) {
    New-Item -Path $LogsDir -ItemType Directory | Out-Null
}

function Read-Heartbeat {
    if (-not (Test-Path $HeartbeatPath)) { return $null }
    try { return (Get-Content $HeartbeatPath -Raw | ConvertFrom-Json) } catch { return $null }
}

switch ($Action) {

    'start' {
        # altes Stop-Signal entfernen
        if (Test-Path $StopSignal) { Remove-Item $StopSignal -ErrorAction SilentlyContinue }

        # L?uft bereits?
        $hb = Read-Heartbeat
        if ($hb -and $hb.status -eq 'running') {
            Write-Host ("Schon gestartet. PID={0}  CPU={1}%  RAM={2}%  DiskFree={3}%  Zeit={4}" -f $hb.pid, $hb.cpu, $hb.memory, $hb.disk_free, $hb.time)
            break
        }

        if (Test-Path $ExePath) {
            Write-Host "Starte EXE: $ExePath (Interval=$IntervalSeconds s)"
            Start-Process -FilePath $ExePath -ArgumentList ("-IntervalSeconds {0}" -f $IntervalSeconds) -WindowStyle Hidden | Out-Null
        }
        else {
            Write-Host "EXE nicht gefunden, starte PS1: $PsPath"
            Start-Process -FilePath "powershell.exe" -ArgumentList ("-ExecutionPolicy Bypass -File `"{0}`" -IntervalSeconds {1}" -f $PsPath, $IntervalSeconds) -WindowStyle Hidden | Out-Null
        }

        Start-Sleep -Seconds 2
        $hb = Read-Heartbeat
        if ($hb) {
            Write-Host "Gestartet. PID=$($hb.pid)"
        } else {
            Write-Warning "Kein Heartbeat gefunden ? pr?fe Logs: $LogPath"
        }
    }

    'stop' {
        Write-Host "Stoppe Dienst..."
        Set-Content -Path $StopSignal -Value 'stop' -Encoding ASCII
        Start-Sleep -Seconds 2
        $hb = Read-Heartbeat
        if ($hb -and $hb.status -eq 'stopped') {
            Write-Host "Gestoppt (PID=$($hb.pid))."
        } else {
            Write-Host "Stop-Signal gesendet. Falls Prozess h?ngt, manuell beenden:"
            Write-Host " taskkill /F /IM monitor.exe"
        }
    }

    'status' {
        $hb = Read-Heartbeat
        if ($hb) {
            Write-Host ("Status: {0}  PID={1}  CPU={2}%  RAM={3}%  DiskFree={4}%  Zeit={5}" -f $hb.status, $hb.pid, $hb.cpu, $hb.memory, $hb.disk_free, $hb.time)
        } else {
            Write-Host "Kein Heartbeat gefunden. L?uft eventuell nicht. Pr?fe Logs: $LogPath"
        }
    }

    'tail' {
        if (Test-Path $LogPath) {
            Write-Host "Logs verfolgen (Strg+C zum Abbrechen): $LogPath"
            Get-Content -Path $LogPath -Wait -Tail 20
        } else {
            Write-Host "Noch keine Logdatei vorhanden."
        }
    }
} # Ende switch
