# Runtime & Diagnose – Ideensammlung

> **Status:** Konzeptphase – noch nichts implementiert.
> Ziel: Ideen festhalten, erweitern, und später umsetzen sobald das Basisprogramm solide ist.

## 1. Diagnose-Sammlung (Pro Session)

Während einer Game-Session automatisch mitschneiden:

| Datenpunkt | Quelle |
|------------|--------|
| Runner + Version | WineManager / RunnerManager |
| Session-Dauer | Launch bis Prozess-Ende (pgrep) |
| Frametimes / FPS | Via DXVK_HUD, Metal HUD, oder Injektion |
| GPU-Auslastung + VRAM | `MTLDevice` + `IOKit` |
| CPU-Temperatur + Throttling | `powermetrics` / `sysctl` |
| Thread-Verteilung (P/E-Cores) | `thread_affinity_policy` / `task_threads()` |
| Shader-Compile-Stutter | DXVK-State-Cache-Monitoring |
| Wine-Logs (`fixme:`, `err:`) | `WINEDEBUG=+all` mitschneiden + parsen |
| System-Zustand | macOS-Version, RAM, freier Speicher, Prozesse |
| Exit-Code + Crash-Reports | `~Library/Logs/DiagnosticReports/` |

## 2. Log-Parser für bekannte Fehler

Laufzeit-Analyse der Wine-Logs auf bekannte Muster:

| Log-Muster | Automatischer Fix |
|------------|------------------|
| `fixme:ntdll:NtQueryInformationProcess` | `ntdll` DLL-Override auf `native` |
| `err:d3d:wined3d_check_feature` | D3DMetal deaktivieren / DXVK erzwingen |
| `fixme:win:EnumDisplayDevicesW` | Virtual Desktop aktivieren |
| `err:ole:CoGetClassObject class not registered` | `winetricks vcrun2022` vorschlagen |
| `fixme:mscoree:LoadLibraryShim` | `winetricks dotnet48` vorschlagen |
| `fixme:heap:GetProcessHeap zurückgegeben` | `WINEDEBUG=-heap` (Spam unterdrücken) |
| `err:module:import_dll` (fehlende DLL) | DLL-Override auf `native,builtin` vorschlagen |
| `fixme:dsound:DSOUND_Mix` (Audio-Stottern) | Audio-Treiber auf `coreaudio` erzwingen |
| `fixme:imm:ImmGetContext` (IME-Probleme) | `WINEDLLOVERRIDES="imm32=n"` |

**Speicherung:** `~Library/Application Support/LutrisForMac/known_fixes.json`
– Key: `gameID + runnerVersion` → Wert: `[empfohlene Fixes]`

## 3. Crowdsourced Fix-Datenbank (Optional)

Anonymisierte Diagnosen an einen zentralen Index senden (Opt-In):

```
Session: Cyberpunk 2077
├── Runner: CrossOver 25.0
├── GPU: M3 Pro 18GB
├── macOS: 15.5
├── FPS: 45 avg / 30 P1
├── Erkannte Fehler: 2x NtQueryInformationProcess
└── Angewandte Fixes: ntdll=native
```

**Nutzen:**
- "100 Nutzer haben Cyberpunk gespielt, 80% CrossOver 25.0, ⌀ 45 FPS"
- "Problem X tritt nur auf M1 auf → Workaround: Wine 8.0 Downgrade"
- Community kann Fixes beisteuern → Runtime zieht sie beim nächsten Start

**Datenschutz:**
- Keine Spiel-Pfade, keine Benutzernamen, keine Steam-Login-Daten
- Nur Hash der gameID + Runner + arch + macOS-Version
- Explizites Opt-In pro Spiel oder global

## 4. Automatische Per-Game-Patches

Aus Diagnose + bekannter Fix-Datenbank wird automatisch ein **Game-Config-Profil** erstellt:

```json
{
  "gameID": "uuid-1234",
  "runner": "CrossOver",
  "known_issues": [
    {"pattern": "NtQueryInformationProcess", "fix": {"type": "dll_override", "dll": "ntdll", "mode": "native"}},
    {"pattern": "d3d_undefined_shader", "fix": {"type": "env", "key": "DXVK_SHADER_CACHE", "value": "1"}}
  ],
  "session_diagnostics": [
    {"date": "2026-05-31", "duration": 4983, "avg_fps": 45, "stutters": 3},
    {"date": "2026-06-01", "duration": 1204, "avg_fps": 47, "stutters": 1}
  ]
}
```

Diese Patches werden automatisch beim nächsten Spielstart angewandt – kein manuelles Tuning nötig.

## 5. Erweiterte Analyse (Post-Session)

Nach Spielende automatisch ausführen:

- **Crash-Report-Parsing:** `~/Library/Logs/DiagnosticReports/<game>*` → Absturzgrund extrahieren → bekannte Lösung vorschlagen
- **Wine-Log-Heatmap:** Welche `fixme:` treten am häufigsten auf? → Priorisierte Fix-Liste
- **Performance-Trend:** Vergleich mit letzten Sessions → "Du hast 5% weniger FPS als letzte Woche, Grund: macOS-Update?"

## 6. UI-Integration (Später)

In der GameDetailView oder einem neuen Tab:

| Bereich | Inhalt |
|---------|--------|
| **Diagnostics** | Letzte Session-Daten (Dauer, FPS, Stutters) |
| **Known Issues** | Automatisch erkannte Probleme + "Fix anwenden"-Button |
| **Performance History** | Chart der letzten 10 Sessions (FPS, Dauer) |
| **Community Insights** | "Andere Nutzer mit M3 erreichen ⌀ 50 FPS" |
| **Session Log** | Vollständiger Wine-Log der letzten Session (anklickbar) |

## Verwandte Konzepte

- **Game Session Optimizer** – Pre/Post-Script-System (siehe `fehlenden_features.md`)
  - Prozesse pausieren (Browser, Backup)
  - CPU-Politik (Performance-Cores forcieren)
  - GPU Low-Latency-Mode
  - Thermal-Throttling minimieren
- **Auto-Configuration** (Phase 2) – Bekannte optimale Settings pro Spiel automatisch vorschlagen
- **Game-Config-Presets** (Phase 2) – Hierarchisches Override (Global → Runner → Spiel)

## Offene Fragen

- [ ] Eigener XPC-Daemon (Option B) oder DYLD_INSERT (Option A)?
- [ ] Lokale Fix-Datenbank (JSON) oder SQLite für größere Datenmengen?
- [ ] Gemeinsames Format für den Community-Index (GitHub-Repo mit PRs?)
- [ ] Wie mit Anti-Cheat umgehen? (DYLD_INSERT blockt, ptrace blockt)
- [ ] macOS-Versions-Kompatibilitätstabelle (welche APIs in welcher Version?)
