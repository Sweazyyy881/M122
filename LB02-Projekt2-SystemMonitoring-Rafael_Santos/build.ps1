# build.ps1 – kompiliert src/monitor.ps1 zu dist/monitor.exe
# Voraussetzung: PowerShell 5.1, Modul ps2exe installiert

$ProjRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src      = Join-Path $ProjRoot 'src' 'monitor.ps1'
$DistDir  = Join-Path $ProjRoot 'dist'
$OutExe   = Join-Path $DistDir 'monitor.exe'

if (-not (Test-Path $DistDir)) { New-Item -Path $DistDir -ItemType Directory | Out-Null }

# Modul installieren (falls nicht vorhanden)
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installiere Modul ps2exe..."
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe -ErrorAction Stop

$iconPath = $null # Optional: eigener Icon-Pfad (.ico)
Write-Host "Baue EXE..."
$pp = @{
    inputFile   = $Src
    outputFile  = $OutExe
    iconFile    = $iconPath
    noConsole   = $true        # versteckte Fenster
    Title       = 'System Monitor'
    Version     = '1.0.0'
    Company     = 'Rafael Santos'
    Description = 'CPU/RAM/Disk Monitor mit Alerts, Logging und Heartbeat'
}

# ps2exe verfügt typischerweise über Invoke-ps2exe oder ps2exe.ps1 – hier generisch:
Invoke-ps2exe @pp

Write-Host "Fertig: $OutExe"
