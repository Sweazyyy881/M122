# Tests für das Laden und Validieren der config.json

Describe 'Config-Validierung' {
    $distDir     = Join-Path $PSScriptRoot '..\dist'
    $configPath  = Join-Path $distDir 'config.json'

    BeforeAll {
        if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }
        @"
{
  "cpu_threshold": 85,
  "memory_threshold": 80,
  "disk_threshold": 15,
  "notify_timeout_seconds": 5
}
"@ | Set-Content -Path $configPath -Encoding UTF8
    }
    AfterAll {
        if (Test-Path $configPath) { Remove-Item $configPath -Force }
    }

    function Load-Config {
        param([string]$Path)

        if (-not (Test-Path $Path)) {
            throw "Konfiguration nicht gefunden: $Path"
        }
        $cfg = Get-Content $Path -Raw | ConvertFrom-Json

        foreach ($k in 'cpu_threshold','memory_threshold','disk_threshold') {
            if (-not ($cfg.PSObject.Properties.Name -contains $k)) {
                throw "Fehlender Schlüssel: $k"
            }
            $v = $cfg.$k
            if (-not ($v -is [int])) { throw "Ungültiger Typ für $k: $($v.GetType().Name)" }
            if ($v -lt 1 -or $v -gt 99) { throw "$k außerhalb 1..99: $v" }
        }

        if (-not ($cfg.PSObject.Properties.Name -contains 'notify_timeout_seconds')) {
            $cfg | Add-Member -NotePropertyName 'notify_timeout_seconds' -NotePropertyValue 5
        } elseif (-not ($cfg.notify_timeout_seconds -is [int])) {
            $cfg.notify_timeout_seconds = 5
        }

        return $cfg
    }

    It 'lädt eine gültige Konfiguration' {
        $cfg = Load-Config -Path $configPath
        $cfg.cpu_threshold        | Should -Be 85
        $cfg.memory_threshold     | Should -Be 80
        $cfg.disk_threshold       | Should -Be 15
        $cfg.notify_timeout_seconds | Should -Be 5
    }

    It 'wirft Fehler bei fehlenden Keys' {
        $bad = Join-Path $distDir 'bad.json'
        @"
{ "cpu_threshold": 90, "memory_threshold": 80 }
"@ | Set-Content -Path $bad -Encoding UTF8

        { Load-Config -Path $bad } | Should -Throw "Fehlender Schlüssel: disk_threshold"

        Remove-Item $bad -Force
    }
}