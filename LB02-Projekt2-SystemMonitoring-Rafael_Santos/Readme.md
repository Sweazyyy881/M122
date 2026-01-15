
# System Monitor (CPU/RAM/Disk) – Rafael Santos

Ein leichtgewichtiges Monitoring für Windows: überwacht CPU, RAM und freien Plattenplatz, schreibt Logs, erzeugt Heartbeat und zeigt Benachrichtigungen. Start/Stop/Status via Controller-Skript, optional als EXE gepackt.

## Features
- Echtzeit-Überwachung (Intervall konfigurierbar)
- Benachrichtigungen (Dialog-Popups, Cooldown)
- Logging (`logs/system.log`)
- Heartbeat (`logs/heartbeat.json` – Status, PID, letzte Werte)
- Sauberes Stoppen via `logs/stop.signal`
- Build als EXE via `ps2exe`
- Controller: `start`, `status`, `tail`, `stop`

## Voraussetzung
- Windows PowerShell **5.1**
- Modul **ps2exe** (für EXE)
- Optional: **Pester** (für Tests)

## Installation
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber

## Sicherheit
Dieses Projekt führt Monitoring und Benachrichtigungen lokal auf Windows aus. Für einen sicheren Betrieb beachte bitte:
### Ausführungsrichtlinien & Signierung
- Set-ExecutionPolicy **RemoteSigned** (Scope **CurrentUser**) für Entwicklung/Tests:
  ```powershell
  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force