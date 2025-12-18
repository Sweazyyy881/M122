# monitor.ps1 – PowerShell 5.1 kompatibel
# Features:
# - CPU/RAM/Disk Monitoring per Performance Counter
# - Logging + Heartbeat-Datei (JSON) für externes Monitoring
# - Dialog-Alerts (nicht-blockierend) mit Cooldown
# - Sauberes Stoppen via "stop.signal" Datei
# - Robust: Exception-Handling, Konfigvalidierung

[CmdletBinding()]
param(
    [int]$IntervalSeconds = 10
)

# -------------------------
# 0) Initialisierung (robust für EXE & PS1)
# -------------------------
$ErrorActionPreference = 'Stop'

# 0.1: eigenen Pfad robust ermitteln
function Get-SelfPath {
    # Reihenfolge: PS-Variablen -> MyInvocation -> EXE-Datei -> WorkingDir
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) { return $PSCommandPath }
    if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) { return $MyInvocation.MyCommand.Path }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exe -and (Test-Path $exe)) { return $exe }
    } catch { }
    return (Join-Path (Get-Location) 'monitor.ps1')   # Fallback
}

$SelfPath = Get-SelfPath
$SelfDir  = Split-Path -Parent $SelfPath

# 0.2: Projekt-Root ableiten (bei EXE in /dist -> Parent ist Projekt-Root, bei PS1 in /src -> Parent ist Projekt-Root)
$ProjRoot = Split-Path -Parent $SelfDir

# 0.3: Standard-Verzeichnisse
$LogDir   = Join-Path $ProjRoot 'logs'
$LogPath  = Join-Path $LogDir   'system.log'
$HeartbeatPath  = Join-Path $LogDir 'heartbeat.json'
$StopSignalPath = Join-Path $LogDir 'stop.signal'

# 0.4: Logs-Verzeichnis sicherstellen
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory | Out-Null
}

# 0.5: Config robuster suchen (1: neben EXE/PS1, 2: /src, 3: Projekt-Root)
$SrcDir = Join-Path $ProjRoot 'src'
$ConfigCandidates = @(
    (Join-Path $SelfDir  'config.json'),
    (Join-Path $SrcDir   'config.json'),
    (Join-Path $ProjRoot 'config.json')
)
$ConfigPath = $ConfigCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $ConfigPath) {
    Write-Error "config.json nicht gefunden in: $($ConfigCandidates -join ', ')"
    exit 1
}

# 0.6: Konfiguration laden und validieren
try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "config.json ungültig: $($_.Exception.Message)"
    exit 1
}

# Pflichtwerte
function Get-RequiredDouble($obj, $name) {
    if ($obj.PSObject.Properties[$name] -and $obj.$name -ne $null -and $obj.$name -ne '') {
        return [double]$obj.$name
    } else {
        throw "Konfigwert fehlt: $name"
    }
}
$cpuLimit    = Get-RequiredDouble $config 'cpu_threshold'
$memoryLimit = Get-RequiredDouble $config 'memory_threshold'
$diskFreeMin = Get-RequiredDouble $config 'disk_threshold'

# Optionalwerte
$cooldownMinutes = if ($config.PSObject.Properties['cooldown_minutes'] -and $config.cooldown_minutes -ne $null -and $config.cooldown_minutes -ne '') { [int]$config.cooldown_minutes } else { 15 }
$notifyMethod    = if ($config.PSObject.Properties['notify_method'] -and $config.notify_method) { $config.notify_method.ToString().ToLower() } else { 'dialog' }
$notifyTimeoutSeconds = if ($config.PSObject.Properties['notify_timeout_seconds'] -and $config.notify_timeout_seconds -ne $null -and $config.notify_timeout_seconds -ne '') { [int]$config.notify_timeout_seconds } else { 5 }

# Protokollstart (Log-Funktion folgt im Abschnitt #1)

# -------------------------
# 1) Logging
# -------------------------
function Write-Log([string]$message) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value "$ts $message"
}

Write-Log "START monitor (Interval=$IntervalSeconds s, CPU>$cpuLimit, RAM>$memoryLimit, DiskFree<$diskFreeMin)"

# -------------------------
# 2) Notification (Dialog)
# -------------------------
function Send-Notification([string]$title, [string]$message, [int]$seconds = 5) {
    try {
        if ($notifyMethod -ne 'dialog') { return }
        Start-Job -ScriptBlock {
            param($t, $m, $s)
            try {
                $ws = New-Object -ComObject WScript.Shell
                $null = $ws.Popup($m, $s, $t, 48) # Exclamation icon, auto-close
            } catch {
                try {
                    Add-Type -AssemblyName System.Windows.Forms | Out-Null
                    [System.Windows.Forms.MessageBox]::Show($m, $t, 'OK', 'Warning') | Out-Null
                } catch {}
            }
        } -ArgumentList $title, $message, $seconds | Out-Null
        Write-Log "ALERT: $title - $message"
    } catch {
        Write-Log "ERROR notify: $($_.Exception.Message)"
    }
}

# -------------------------
# 3) Cooldown Tracking
# -------------------------
$cooldown      = New-TimeSpan -Minutes $cooldownMinutes
$lastAlertTime = @{
    CPU    = Get-Date '2000-01-01'
    Memory = Get-Date '2000-01-01'
    Disk   = Get-Date '2000-01-01'
}
function ShouldAlert([string]$metric) {
    ((Get-Date) - $lastAlertTime[$metric]) -gt $cooldown
}

# -------------------------
# 4) Werte abrufen
# -------------------------
function Get-SystemStats {
    try {
        $cpu      = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        $memory   = (Get-Counter '\Memory\% Committed Bytes In Use').CounterSamples.CookedValue
        $diskFree = (Get-Counter '\LogicalDisk(_Total)\% Free Space').CounterSamples.CookedValue

        [pscustomobject]@{
            CPU      = [math]::Round($cpu, 2)
            Memory   = [math]::Round($memory, 2)
            DiskFree = [math]::Round($diskFree, 2)
            Time     = Get-Date
        }
    }
    catch {
        Write-Log "ERROR counters: $($_.Exception.Message)"
        throw
    }
}

# -------------------------
# 5) Heartbeat schreiben
# -------------------------
function Write-Heartbeat($stats) {
    try {
        $hb = [pscustomobject]@{
            time      = $stats.Time.ToString('yyyy-MM-dd HH:mm:ss')
            cpu       = $stats.CPU
            memory    = $stats.Memory
            disk_free = $stats.DiskFree
            pid       = $PID
            exe       = $PSCommandPath
            status    = 'running'
        }
        ($hb | ConvertTo-Json -Depth 3) | Set-Content -Path $HeartbeatPath -Encoding UTF8
    } catch {
        Write-Log "ERROR heartbeat: $($_.Exception.Message)"
    }
}

# -------------------------
# 6) Graceful Stop prüfen
# -------------------------
function ShouldStop() {
    Test-Path $StopSignalPath
}

# -------------------------
# 7) Hauptschleife
# -------------------------
try {
    while ($true) {
        if (ShouldStop) {
            Write-Log "STOP signal detected – exiting."
            Remove-Item -Path $StopSignalPath -ErrorAction SilentlyContinue
            break
        }

        $s = Get-SystemStats
        $line = ("{0} CPU: {1}% | RAM: {2}% | Disk frei: {3}%" -f ($s.Time.ToString('HH:mm:ss')), $s.CPU, $s.Memory, $s.DiskFree)
        Write-Host $line
        Write-Log  ("STATS CPU={0}% RAM={1}% DISKFREE={2}%" -f $s.CPU, $s.Memory, $s.DiskFree)

        Write-Heartbeat $s

        if ($s.CPU -gt $cpuLimit -and (ShouldAlert 'CPU')) {
            Send-Notification "Hohe CPU-Auslastung" "CPU: $($s.CPU)% > Grenzwert $cpuLimit%" $notifyTimeoutSeconds
            $lastAlertTime['CPU'] = Get-Date
        }

        if ($s.Memory -gt $memoryLimit -and (ShouldAlert 'Memory')) {
            Send-Notification "Hoher RAM-Verbrauch" "RAM: $($s.Memory)% > Grenzwert $memoryLimit%" $notifyTimeoutSeconds
            $lastAlertTime['Memory'] = Get-Date
        }

        if ($s.DiskFree -lt $diskFreeMin -and (ShouldAlert 'Disk')) {
            Send-Notification "Wenig Speicher frei" "Nur $($s.DiskFree)% frei < Mindestwert $diskFreeMin%" $notifyTimeoutSeconds
            $lastAlertTime['Disk'] = Get-Date
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
}
catch {
    Write-Warning $_.Exception.Message
    Write-Log "ERROR loop: $($_.Exception.Message)"
}
finally {
    try {
        $hb = [pscustomobject]@{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); status = 'stopped'; pid = $PID }
        ($hb | ConvertTo-Json) | Set-Content -Path $HeartbeatPath -Encoding UTF8
    } catch {}
    Write-Log "END monitor"
}
