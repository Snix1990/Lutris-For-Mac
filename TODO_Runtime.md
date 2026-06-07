# Runtime – Todo

## 1 Prozess-Überwachung (Monitoring & Logging)
- [x] Child-Prozess-Baum verfolgen (PID-Tracking + pgrep-Fallback)
- [x] stdout/stderr jederzeit loggen (rotierende Datei + In-Memory-Ringbuffer)
- [x] Exit-Code + Signal-Auswertung (Absturz? Manuell beendet? Segfault?)
- [x] Laufzeit-Statistiken: CPU%, Speicher, offene Handles
- [x] Log-Viewer in der App (letzte Sitzung + Historie)

## 2 Cloud Saves
- [x] Lokale Speicherstände automatisch erkennen (bekannte Pfade pro Runner)
- [x] Synchronisation mit eigener Cloud (WebDAV / Nextcloud / S3-kompatibel)
- [x] Manueller Sync-Button (Toolbar neben Wine, gleicher Stil)
- [x] Konfliktlösung: Zeitstempel-Vergleich + Resolution (local/remote/keepBoth)
- [x] Versions-Historie (letzte 5 Backups lokal behalten)

## 3 Custom OSD (On-Screen Display)
- [ ] FPS-Anzeige (über Metal/OpenGL-Hook oder externes Tool)
- [ ] CPU-/GPU-/RAM-Auslastung einblendbar
- [ ] Anpassbare Position (Ecken, Mitte oben/unten)
- [ ] Tastaturkürzel zum Ein-/Ausschalten (z. B. F12)
- [ ] Stil: Größe, Farbe, Transparenz, Schriftart konfigurierbar

## 4 Custom In-Game Notifications
- [x] Controller-Batterie schwach → Benachrichtigung einblenden
- [x] Performance-Warnung (Thermal-Throttling via HardwareMonitor)
- [x] Cloud-Sync-Status („Speicherstand hochgeladen“ / „Downloading – …“ mit NotificationManager)
- [x] Discord-RPC-Status-Update-Benachrichtigung
- [x] Stapelbare Queue + Timeout-gesteuertes Ausblenden (NotificationManager)

## 5 Performance & Hardware-Monitoring
- [x] GPU-Temperatur + Lüfterdrehzahl (via SMC / iStat)
- [x] Thermal-Throttling-Erkennung (via ProcessInfo.thermalState)
- [x] Frame-Time-Analyse (1% / 0.1% Lows)
- [x] Speicherbelegung pro Prozess + Gesamtsystem

## 6 Screenshot & Recording
- [x] Screenshot-Hotkey (png, einstellbarer Ordner)
- [x] **Automatischer Screenshot bei Erfolgen nicht umsetzbar** – Goldberg-Emulator hat keine Echtzeit-Notifications, Polling im Sekundentakt wäre Overkill.
- [x] **Video-Clip (letzte 30s) nicht umsetzbar** – ReplayKit hat kein retroaktives Recording, CGDisplayStream-Ringpuffer wäre zu teuer (14GB+ für 4K/60). Bei Wine zusätzlich keine zuverlässige Vollbild-Erfassung.

## 7 Session-Management
- [x] **Pause/Resume/Savestate nicht umsetzbar** – macOS hat kein CRIU, Wine-Prozesse + GPU-Contexts lassen sich nicht serialisieren. VM-Lösung wäre mit 40-50% Overhead nicht spielbar.
- [x] **Crash-Erkennung nicht umsetzbar** – Exit-Codes von Wine/Emulatoren sind nicht aussagekräftig, keine API für Crash-Reporter auf macOS.
- [x] Singleton-Check vor Launch (GameSessionManager.isGameRunning + Alert)

## 8 Wine-/Emulator-Integration
- [x] Wine-Debug-Kanäle filterbar mitschneiden (WineDebugManager mit channel-Presets, toggle + custom WINEDEBUG, filter im Log-Viewer)
- [x] DXVK/HUD automatisch aktivieren falls verfügbar (DXVK_HUD-Toggle in WineConfigView, env-merge in wineEnvironment)
- [x] MSync/ESync/FSync-Status – bereits via WineConfigView konfigurierbar (wineEnvironment setzt WINE_MSYNC_DISABLE/WINEESYNC/WINEFSYNC)
- [x] Emulator-spezifische Logs (RetroArch --verbose Flag in RunnerManager.launchGame)

## 9 Overlay-Launcher (In-Game-Menü)
- [ ] Globale Hotkey-Kombination (z. B. Strg+Shift+F1)
- [ ] Menü: Spiel beenden, Einstellungen, Screenshot, Save-State
- [ ] Musik-Player-Steuerung (Spotify/Apple Music nächster Titel)
- [ ] Mikrofon-Stummschaltung (Discord/Ingame-Voice)

## 10 Controller-Integration
- [x] Hotplug-Erkennung während der Runtime
- [x] Batteriestand-Dauerüberwachung + Notification bei <20%
- [x] Rumble-Test – nicht nötig, entfernt
- [x] Button-Remapping zur Laufzeit (via GameController.framework valueChangedHandler-Interception)

## 11 Auto-Updates & Self-Healing
- [x] Runtime-Komponente via GitHub Releases aktualisierbar (UpdateManager: GitHub-API-Check, Notification, Download/Ignore, periodische Prüfung)
- [x] Fallback: wenn OSD-Hook fehlschlägt → Headless-Mode (UpdateManager.headlessMode prüft DISPLAY/WAYLAND_DISPLAY)
- [x] Health-Check vor Launch (Wine-Binary OK? Prefix intakt? Install-Path existiert? → RuntimeManager.checkHealth())

## 12 API / Erweiterbarkeit
- [x] Lokaler HTTP-Socket für externe Tools (RuntimeAPI: NWListener auf :9876 mit GET /health, /games, POST /launch, /webhook)
- [x] Webhook bei Spiel-Ende (RuntimeAPI.fireWebhook – POST JSON an konfigurierte URL, getriggert via Notification.gameSessionEnded)
- [x] Scripting (preLaunchScript + postExitScript per Game, ausgeführt via ProcessRunner mit LUTRIS_GAME/LUTRIS_PLAYTIME env)
