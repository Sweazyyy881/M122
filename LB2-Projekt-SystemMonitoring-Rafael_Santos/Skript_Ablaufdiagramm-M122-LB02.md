```mermaid
flowchart TD
    Start["Start"]
    TaskScheduler["Task Scheduler startet den Skript"]
    KonfigDatei["Lade config.json"]
    Systemwerte["Hole Systemwerte"]
    PrüfeGrenzwerte["Prüfe Grenzwerte"]
    Warnung["Zeige Warnung + Log"]
    WInterval["Warte Interval"]

    Start --> TaskScheduler
    TaskScheduler --> KonfigDatei
    KonfigDatei --> Systemwerte
    Systemwerte --> PrüfeGrenzwerte
    Systemwerte --> WInterval
    PrüfeGrenzwerte --> Warnung
    Warnung --> WInterval