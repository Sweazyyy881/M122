
Config Datei:
Setzt man die "cpu_threshold" auf "1" -> sofortige Warnung
Setzt man die "disk_threshold" auf "99" -> Warnung für Speicherplatz

Der Skript liest die config Datei beim Start undnutzt die Werte:
- CPU-Grenzwert (z. B. 80 %)
- RAM-Grenzwert (z. B. 80 %)
- Minimaler freier Speicherplatz (z. B. 10 %)
- Cooldown (wie oft Warnungen kommen dürfen)
- Benachrichtigungsmethode (z. B. dialog)
- Timeout für Popup (wie lange sichtbar)

