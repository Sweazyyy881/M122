# Tests für Heartbeat-Datei (Status & Werte)

Describe 'Heartbeat-Datei' {
    $logsDir = Join-Path $PSScriptRoot '..\logs'
    $hbPath  = Join-Path $logsDir 'heartbeat.json'

    BeforeAll {
        if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir | Out-Null }
    }
    AfterAll {
        if (Test-Path $hbPath) { Remove-Item $hbPath -Force }
    }

    function Write-Heartbeat {
        param(
            [string]$Status,
            [double]$CPU,
            [double]$RAM,
            [double]$Disk,
            [string]$Path
        )
        $obj = [pscustomobject]@{
            timestamp = (Get-Date).ToString('o')
            status    = $Status
            cpu       = [math]::Round($CPU, 2)
            ram       = [math]::Round($RAM, 2)
            disk      = [math]::Round($Disk, 2)
            pid       = $PID
        }
        $json = $obj | ConvertTo-Json -Depth 3
        $json | Set-Content -Path $Path -Encoding UTF8
    }

    It 'legt heartbeat.json an und enthält gültige Felder' {
        Write-Heartbeat -Status 'running' -CPU 23.1 -RAM 41.4 -Disk 77.9 -Path $hbPath
        (Test-Path $hbPath) | Should -BeTrue

        $hb = Get-Content $hbPath -Raw | ConvertFrom-Json
        $hb.status | Should -Be 'running'
        $hb.pid    | Should -Be $PID
        [double]$hb.cpu  | Should -BeGreaterThanOrEqual 0
        [double]$hb.ram  | Should -BeGreaterThanOrEqual 0
        [double]$hb.disk | Should -BeGreaterThanOrEqual 0
        $hb.timestamp | Should -Not -BeNullOrEmpty
    }
}