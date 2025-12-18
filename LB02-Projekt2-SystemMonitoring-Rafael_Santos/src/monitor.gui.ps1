
# monitor.gui.ps1 - WinForms GUI für System Monitoring (PowerShell 5.1)
# Features:
# - Live-Dashboard: CPU, RAM, DiskFree (ProgressBars + Labels)
# - Start / Stop im selben Prozess
# - Logging (logs/system.log), Heartbeat (logs/heartbeat.json)
# - Robuste Pfadermittlung & Config-Suche (dist/src/root)
# - Optional Dialog-Alerts (Cooldown)
# - Stop über Button oder stop.signal-Datei

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'

# -------------------------
# 0) Initialisierung (robust)
# -------------------------
function Get-SelfPath {
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) { return $PSCommandPath }
    if ($MyInvocation -and $MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) { return $MyInvocation.MyCommand.Path }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exe -and (Test-Path $exe)) { return $exe }
    } catch {}
    return (Join-Path (Get-Location) 'monitor.gui.ps1')
}
$SelfPath = Get-SelfPath
$SelfDir  = Split-Path -Parent $SelfPath
$ProjRoot = Split-Path -Parent $SelfDir

$LogsDir  = Join-Path $ProjRoot 'logs'
$LogPath  = Join-Path $LogsDir 'system.log'
$HeartbeatPath = Join-Path $LogsDir 'heartbeat.json'
$StopSignalPath = Join-Path $LogsDir 'stop.signal'

if (-not (Test-Path $LogsDir)) { New-Item -Path $LogsDir -ItemType Directory | Out-Null }

$SrcDir = Join-Path $ProjRoot 'src'
$ConfigCandidates = @(
    (Join-Path $SelfDir  'config.json'),
    (Join-Path $SrcDir   'config.json'),
    (Join-Path $ProjRoot 'config.json')
)
$ConfigPath = $ConfigCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ConfigPath) { [System.Windows.Forms.MessageBox]::Show("config.json nicht gefunden in:`n$($ConfigCandidates -join "`n")","System Monitor"); exit 1 }

try { $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json }
catch { [System.Windows.Forms.MessageBox]::Show("config.json ungültig: $($_.Exception.Message)","System Monitor"); exit 1 }

# Pflicht/Optional
function Get-RequiredDouble($obj,$name){
    if ($obj.PSObject.Properties[$name] -and $obj.$name -ne $null -and $obj.$name -ne ''){
        return [double]$obj.$name
    } else { throw "Konfigwert fehlt: $name" }
}
$cpuLimit    = Get-RequiredDouble $config 'cpu_threshold'
$memoryLimit = Get-RequiredDouble $config 'memory_threshold'
$diskFreeMin = Get-RequiredDouble $config 'disk_threshold'
$cooldownMinutes = if ($config.PSObject.Properties['cooldown_minutes'] -and $config.cooldown_minutes -ne $null -and $config.cooldown_minutes -ne '') { [int]$config.cooldown_minutes } else { 15 }
$notifyMethod = if ($config.PSObject.Properties['notify_method'] -and $config.notify_method) { $config.notify_method.ToString().ToLower() } else { 'dialog' }
$notifyTimeoutSeconds = if ($config.PSObject.Properties['notify_timeout_seconds'] -and $config.notify_timeout_seconds -ne $null -and $config.notify_timeout_seconds -ne '') { [int]$config.notify_timeout_seconds } else { 5 }

# Intervall (Sekunden) – Standard 10, kann im UI geändert werden
$IntervalSeconds = 10

# -------------------------
# 1) Logging & Utilities
# -------------------------
function Write-Log([string]$message){
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value "$ts $message"
}
function Send-Notification([string]$title,[string]$message,[int]$seconds=5){
    if ($notifyMethod -ne 'dialog') { return }
    Start-Job -ScriptBlock {
        param($t,$m,$s)
        try {
            $ws = New-Object -ComObject WScript.Shell
            $null = $ws.Popup($m,$s,$t,48)
        } catch {
            try {
                Add-Type -AssemblyName System.Windows.Forms | Out-Null
                [System.Windows.Forms.MessageBox]::Show($m,$t,'OK','Warning') | Out-Null
            } catch {}
        }
    } -ArgumentList $title,$message,$seconds | Out-Null
    Write-Log "ALERT: $title - $message"
}
$cooldown = New-TimeSpan -Minutes $cooldownMinutes
$lastAlertTime = @{
  CPU    = Get-Date '2000-01-01'
  Memory = Get-Date '2000-01-01'
  Disk   = Get-Date '2000-01-01'
}
function ShouldAlert([string]$metric){ ((Get-Date) - $lastAlertTime[$metric]) -gt $cooldown }

function Get-SystemStats {
    $cpu      = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
    $memory   = (Get-Counter '\Memory\% Committed Bytes In Use').CounterSamples.CookedValue
    $diskFree = (Get-Counter '\LogicalDisk(_Total)\% Free Space').CounterSamples.CookedValue
    [pscustomobject]@{
        CPU      = [math]::Round($cpu,2)
        Memory   = [math]::Round($memory,2)
        DiskFree = [math]::Round($diskFree,2)
        Time     = Get-Date
    }
}
function Write-Heartbeat($stats,$status='running'){
    $hb = [pscustomobject]@{
        time      = $stats.Time.ToString('yyyy-MM-dd HH:mm:ss')
        cpu       = $stats.CPU
        memory    = $stats.Memory
        disk_free = $stats.DiskFree
        pid       = $PID
        status    = $status
    }
    ($hb | ConvertTo-Json -Depth 3) | Set-Content -Path $HeartbeatPath -Encoding UTF8
}

# -------------------------
# 2) UI bauen (WinForms)
# -------------------------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "System Monitor"
$form.StartPosition   = "CenterScreen"
$form.Size            = New-Object System.Drawing.Size(520, 330)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false

$lblCpu = New-Object System.Windows.Forms.Label
$lblCpu.Text = "CPU"
$lblCpu.Location = '20,25'
$lblCpu.AutoSize = $true

$barCpu = New-Object System.Windows.Forms.ProgressBar
$barCpu.Location = '100,20'
$barCpu.Size = '300,23'
$barCpu.Minimum = 0; $barCpu.Maximum = 100

$valCpu = New-Object System.Windows.Forms.Label
$valCpu.Location = '420,25'; $valCpu.AutoSize = $true; $valCpu.Text = "0%"

$lblMem = New-Object System.Windows.Forms.Label
$lblMem.Text = "RAM"
$lblMem.Location = '20,70'
$lblMem.AutoSize = $true

$barMem = New-Object System.Windows.Forms.ProgressBar
$barMem.Location = '100,65'
$barMem.Size = '300,23'
$barMem.Minimum = 0; $barMem.Maximum = 100

$valMem = New-Object System.Windows.Forms.Label
$valMem.Location = '420,70'; $valMem.AutoSize = $true; $valMem.Text = "0%"

$lblDisk = New-Object System.Windows.Forms.Label
$lblDisk.Text = "Disk frei"
$lblDisk.Location = '20,115'
$lblDisk.AutoSize = $true

$barDisk = New-Object System.Windows.Forms.ProgressBar
$barDisk.Location = '100,110'
$barDisk.Size = '300,23'
$barDisk.Minimum = 0; $barDisk.Maximum = 100

$valDisk = New-Object System.Windows.Forms.Label
$valDisk.Location = '420,115'; $valDisk.AutoSize = $true; $valDisk.Text = "0%"

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: stopped"
$lblStatus.Location = '20,160'
$lblStatus.Size = '460,20'

$lblTime = New-Object System.Windows.Forms.Label
$lblTime.Text = "Zeit: -"
$lblTime.Location = '20,185'
$lblTime.Size = '460,20'

$lblInterval = New-Object System.Windows.Forms.Label
$lblInterval.Text = "Intervall (s):"
$lblInterval.Location = '20,215'
$lblInterval.AutoSize = $true

$numInterval = New-Object System.Windows.Forms.NumericUpDown
$numInterval.Location = '100,210'
$numInterval.Width = 80
$numInterval.Minimum = 1
$numInterval.Maximum = 300
$numInterval.Value = $IntervalSeconds

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start"
$btnStart.Location = '200,205'
$btnStart.Width = 80

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Location = '290,205'
$btnStop.Width = 80
$btnStop.Enabled = $false

$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Text = "Logs öffnen"
$btnLog.Location = '380,205'
$btnLog.Width = 100

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Beenden"
$btnClose.Location = '380,245'
$btnClose.Width = 100

$form.Controls.AddRange(@(
    $lblCpu,$barCpu,$valCpu,
    $lblMem,$barMem,$valMem,
    $lblDisk,$barDisk,$valDisk,
    $lblStatus,$lblTime,$lblInterval,$numInterval,
    $btnStart,$btnStop,$btnLog,$btnClose
))

# -------------------------
# 3) Timer & Monitoring
# -------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $numInterval.Value * 1000

$script:Running = $false

function Update-UI($s){
    $barCpu.Value  = [math]::Min(100,[math]::Max(0,[int]$s.CPU))
    $valCpu.Text   = "$($s.CPU)%"
    $barMem.Value  = [math]::Min(100,[math]::Max(0,[int]$s.Memory))
    $valMem.Text   = "$($s.Memory)%"
    $barDisk.Value = [math]::Min(100,[math]::Max(0,[int]$s.DiskFree))
    $valDisk.Text  = "$($s.DiskFree)%"
    $lblTime.Text  = "Zeit: " + $s.Time.ToString('yyyy-MM-dd HH:mm:ss')
}

$timer.Add_Tick({
    try {
        if (Test-Path $StopSignalPath) {
            $timer.Stop()
            Remove-Item $StopSignalPath -ErrorAction SilentlyContinue
            $script:Running = $false
            $lblStatus.Text = "Status: stopped"
            Write-Heartbeat ([pscustomobject]@{Time=Get-Date;CPU=0;Memory=0;DiskFree=0}) 'stopped'
            Write-Log "STOP signal detected – exiting loop"
            $btnStart.Enabled = $true
            $btnStop.Enabled  = $false
            return
        }

        $s = Get-SystemStats
        Update-UI $s
        Write-Log ("STATS CPU={0}% RAM={1}% DISKFREE={2}%" -f $s.CPU,$s.Memory,$s.DiskFree)
        Write-Heartbeat $s 'running'
        $lblStatus.Text = "Status: running (PID=$PID)"

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
    } catch {
        Write-Log "ERROR loop: $($_.Exception.Message)"
    }
})

# -------------------------
# 4) Button-Events
# -------------------------
$btnStart.Add_Click({
    try {
        $IntervalSeconds     = [int]$numInterval.Value
        $timer.Interval      = $IntervalSeconds * 1000
        $script:Running      = $true
        $btnStart.Enabled    = $false
        $btnStop.Enabled     = $true
        Write-Log "START monitor (GUI, Interval=$IntervalSeconds s, CPU>$cpuLimit, RAM>$memoryLimit, DiskFree<$diskFreeMin)"
        # erste Messung sofort:
        $s = Get-SystemStats
        Update-UI $s
        Write-Heartbeat $s 'running'
        $lblStatus.Text = "Status: running (PID=$PID)"
        $timer.Start()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Start-Fehler: $($_.Exception.Message)","System Monitor")
        Write-Log "ERROR start: $($_.Exception.Message)"
    }
})

$btnStop.Add_Click({
    try {
        $timer.Stop()
        $script:Running   = $false
        $btnStart.Enabled = $true
        $btnStop.Enabled  = $false
        Write-Heartbeat ([pscustomobject]@{Time=Get-Date;CPU=0;Memory=0;DiskFree=0}) 'stopped'
        $lblStatus.Text = "Status: stopped"
        Write-Log "END monitor (GUI stop)"
    } catch {
        Write-Log "ERROR stop: $($_.Exception.Message)"
    }
})

$btnLog.Add_Click({
    if (Test-Path $LogPath) { Start-Process notepad.exe $LogPath } else { [System.Windows.Forms.MessageBox]::Show("Noch keine Logdatei vorhanden.","System Monitor") }
})
$btnClose.Add_Click({
    if ($script:Running) { $timer.Stop(); Write-Heartbeat ([pscustomobject]@{Time=Get-Date;CPU=0;Memory=0;DiskFree=0}) 'stopped'; Write-Log "END monitor (GUI close)" }
    $form.Close()
})

$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)
``
