# monitor.ps1 (PowerShell 5.1 kompatibel)
[CmdletBinding()]
param(
    [int]$IntervalSeconds = 10   # Messintervall in Sekunden
)

# 1) Pfade & Konfiguration

$Root       = $PSScriptRoot
$ConfigPath = Join-Path $Root 'config.json'
$LogDir     = Join-Path $Root 'logs'
$LogPath    = Join-Path $LogDir 'system.log'

if (-not (Test-Path $ConfigPath)) {
    Write-Error "config.json nicht gefunden: $ConfigPath"
    exit 1
}
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory | Out-Null
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Pflichtwerte
$cpuLimit    = [double]$config.cpu_threshold
$memoryLimit = [double]$config.memory_threshold
$diskFreeMin = [double]$config.disk_threshold   # Mindest-% freier Platz

# Optionalwerte OHNE '??' (5.1-kompatibel)
if ($config.PSObject.Properties['cooldown_minutes'] -and $config.cooldown_minutes -ne $null -and $config.cooldown_minutes -ne '') {
    $cooldownMinutes = [int]$config.cooldown_minutes
} else {
    $cooldownMinutes = 15
}

if ($config.PSObject.Properties['notify_method'] -and $config.notify_method) {
    $notifyMethod = $config.notify_method.ToString().ToLower()
} else {
    $notifyMethod = 'dialog'
}

if ($config.PSObject.Properties['notify_timeout_seconds'] -and $config.notify_timeout_seconds -ne $null -and $config.notify_timeout_seconds -ne '') {
    $notifyTimeoutSeconds = [int]$config.notify_timeout_seconds
} else {
    $notifyTimeoutSeconds = 5
}

# -------------------------
# 2) Logging
# -------------------------
function Write-Log([string]$message) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value "$ts $message"
}

# -------------------------
# 3) Benachrichtigung (Dialog)
#    Nicht-blockierend per Start-Job; Popup schließt nach Timeout
# -------------------------
function Send-Notification([string]$title, [string]$message, [int]$seconds = 5) {
    if ($notifyMethod -ne 'dialog') { return }

    Start-Job -ScriptBlock {
        param($t, $m, $s)
        try {
            $ws = New-Object -ComObject WScript.Shell
            # Popup(Text, TimeoutSek, Titel, TypFlags=48 Exclamation)
            $null = $ws.Popup($m, $s, $t, 48)
        } catch {
            try {
                Add-Type -AssemblyName System.Windows.Forms | Out-Null
                [System.Windows.Forms.MessageBox]::Show($m, $t, 'OK', 'Warning') | Out-Null
            } catch {}
        }
    } -ArgumentList $title, $message, $seconds | Out-Null

    Write-Log "ALERT: $title - $message"
}

# Cooldown je Metrik
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
# 4) Systemwerte abrufen
# -------------------------
function Get-SystemStats {
    try {
        $cpu      = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        $memory   = (Get-Counter '\Memory\% Committed Bytes In Use').CounterSamples.CookedValue
        $diskFree = (Get-Counter '\LogicalDisk(_Total)\% Free Space').CounterSamples.CookedValue

        [pscustomobject]@{
            CPU      = [math]::Round($cpu, 2)        # Auslastung in %
            Memory   = [math]::Round($memory, 2)     # Auslastung in %
            DiskFree = [math]::Round($diskFree, 2)   # Freier Platz in %
            Time     = Get-Date
        }
    }
    catch {
        Write-Log "ERROR counters: $($_.Exception.Message)"
        throw
    }
}

# -------------------------
# 5) Hauptschleife
# -------------------------
while ($true) {
    try {
        $s = Get-SystemStats

        $line = ("{0}  CPU: {1}% | RAM: {2}% | Disk frei: {3}%" -f ($s.Time.ToString('HH:mm:ss')), $s.CPU, $s.Memory, $s.DiskFree)
        Write-Host $line
        Write-Log  ("STATS CPU={0}% RAM={1}% DISKFREE={2}%" -f $s.CPU, $s.Memory, $s.DiskFree)

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
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Log "ERROR loop: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $IntervalSeconds
}