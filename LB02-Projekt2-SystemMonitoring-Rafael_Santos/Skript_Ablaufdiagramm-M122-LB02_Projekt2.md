```mermaid
flowchart TD
    A["Start: controller.ps1"]
    B["Monitor starten"]
    C["monitor.exe (dist)"]
    D["monitor.ps1 (src)"]
    E["Messloop: CPU/RAM/Disk"]
    F["Vergleich mit config.json"]
    G["Heartbeat schreiben (logs/heartbeat.json)"]
    H["Benachrichtigung via monitor.gui.ps1"]
    I["Log schreiben (logs/system.log)"]
    J["Stop-Signal vorhanden?"]
    K["Beenden: status=stopped, Log schreiben"]
    L["Ende"]

    A --> B
    B -->|EXE vorhanden| C
    B -->|Fallback| D
    C --> E
    D --> E
    E --> F
    F -->|OK| G
    F -->|Schwelle überschritten| H
    G --> I
    H --> I
    I --> J
    J -->|Nein| E
    J -->|Ja| K
    K --> L