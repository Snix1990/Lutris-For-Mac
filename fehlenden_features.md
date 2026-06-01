# Fehlende Features – Priorisierte Roadmap

## Phase 1 – Niedrige Komplexität, sofort sichtbar

| Rang | Feature | Aufwand | Begründung |
|------|---------|---------|------------|
| 1 | **GOG Galaxy Scanner** | 1–2h | Service-Eintrag existiert, nur Scanlogik fehlt (gleiches Pattern wie Steam/Heroic/itch.io). Viele macOS-Nutzer haben GOG-Bibliotheken. |
| 2 | **Epic Games Store Scanner (via Heroic)** | 1–2h | Heroic-Configs auf macOS lesbar. Epic hat macOS zwar fallen gelassen, aber bestehende Käufe sind via Heroic verfügbar. |
| 3 | **GPU-Reporting** | 0,5h | Metal GPU via `MTLCreateSystemDefaultDevice()` abfragen, Treiberinfo anzeigen. Minimaler Aufwand. |
| 4 | **Web-Browser-Integration (lutris://)** | 1h | `CFBundleURLTypes` in Info.plist + SwiftUI `onOpenURL`. Ermöglicht Deep-Links von Installern/Webseiten. |
| 5 | **CLI** | 2–3h | Swift ArgumentParser. `--list-games`, `--install`, `--exec` für Power-User, Scripting, Debugging. |

## Phase 2 – Hoher Nutzen, moderate Komplexität

| Rang | Feature | Aufwand | Begründung |
|------|---------|---------|------------|
| 6 | **Game-Config-Presets** | 3–5h | Hierarchisches Override (Global → Runner → Spiel). Einmal konfigurieren, alle Spiele profitieren. Z.B. „DXVK immer an" oder „Audio immer coreaudio". Größter Hebel für wiederkehrende Einstellungen. |
| 7 | **Auto-Configuration** | 4–8h | Bekannte optimale Settings pro Spiel/Runner automatisch vorschlagen (Known-Good-Datenbank in JSON). Reduziert Fehlkonfigurationen und Frust bei neuen Spielen massiv. |
| 8 | **Humble Bundle Integration** | 3–5h | API-Zugriff auf Humble-Library. Viele macOS-Nutzer mit Humble-Choice-Abos. Synchronisation der gekauften Spiele. |
| 9 | **Spiel exportieren/importieren** | 3–5h | Game + Config + Cover als Archiv sichern und auf anderen Rechnern wiederherstellen. Nützlich für Migration oder Backup. |

## Phase 3 – Erweiterungen für spezifische Use Cases

| Rang | Feature | Aufwand | Begründung |
|------|---------|---------|------------|
| 10 | **Amazon Prime Gaming** | 3–5h | Spiel-Library via Prime Gaming importieren. Niedrigere Nutzerbasis auf macOS, aber einfache API-Integration. |
| 11 | **Mehrere Storage Locations** | 4–6h | Spiele über verschiedene Laufwerke/Verzeichnisse verteilen. Relevant für Nutzer mit kleiner System-SSD + großer Daten-HDD. |
| 12 | **Lutris.net Account Sync** | 5–8h | API-Integration für Library-Sync und Community-Installer-Zugriff. Erfordert lutris.net-API-Kenntnisse (besteht die API noch?). |

## Phase 4 – Spezialthemen

| Rang | Feature | Aufwand | Begründung |
|------|---------|---------|------------|
| 13 | **Cloud-Saves** | 8–15h | Service-spezifische APIs (Steam Cloud, EGS, GOG). Aufwändig pro Anbieter, niedriger macOS-spezifischer Mehrwert. |
| 14 | **TOSEC-Datenbank** | 3–5h | ROM-Sammlungs-Erkennung und -Benennung. Nischenfeature für Retro-Enthusiasten mit großen ROM-Sets. |
| 15 | **Fehlende Emulatoren** (ResidualVM, AGS, Mednafen, FS-UAE, Vice, Stella, Atari800, Hatari, Virtual Jaguar, Snes9x, Mupen64Plus, Reicast, Frotz, jzIntv, O2EM, ZDoom, DeSmuME, DGen, ShadPS4, Azahar) | 1–3h pro Stück | Je Emulator: Download-Logik, Versions-Erkennung, Launcher-Pattern. Rein mechanische Arbeit, niedriger Einzelnutzen. Sinnvoll wenn ein bestimmter Emulator gebraucht wird. |

## Zurückgestellt – Game Session Optimizer (Ideenfindung)

Ein Pre/Post-Script-System, das vor Spielstart systemweite Optimierungen setzt und nach Spielende zurücksetzt. Keine Runtime, nur macOS-native APIs + optional injected Dylib für Core-Pinning.

**Mögliche Optimierungen (pro Session konfigurierbar):**

| Bereich | Maßnahme | Technik |
|---------|----------|---------|
| **Prozesse** | Browser, Backup, Spotlight pausieren | `kill -STOP` / `pmset` |
| **CPU** | Nebenthreads auf BG-Priorität, Game auf Performance-Cores | `setpriority()` + `thread_affinity_policy` |
| **GPU** | Low-Latency-Mode, VRAM freihalten, Shader-Cache vorheizen | Metal API (via Dylib-Hook) |
| **Thermal** | Throttling minimieren, Lüfterprofil setzen | `pmset -a` + `powermetrics` |
| **Display** | ProMotion erzwingen, 60-Hz-Fallback verhindern | CoreDisplay-Override |

**Geplanter Ansatz (zwei Optionen):**

*Option A – Lightweight (injected Dylib):*
- `DYLD_INSERT_LIBRARIES` + injected C-Dylib (~50 Zeilen) für `pthread_create`-Interception → Core-Pinning
- Swift-Launcher mit `posix_spawnattr_t` vor dem Spiel-`exec`
- Teardown-Hook nach Spielende (Prozess-Monitoring via `pgrep`)

*Option B – Runtime (eigener Prozess als Session-Manager):*
- Separation:-Daemon (XPC Service oder launchd-Job), der:
  - Game-Prozess als Child spawnen (`posix_spawn`)
  - Thread-Politiken + Core-Affinity im Game-Prozess via `task_policy_set()` / `thread_policy_set()` setzen (von außen möglich via `task_for_pid` mit `com.apple.system-task-ports`)
  - System-Zustand sichern (Browser-PIDs, Power-Settings) vor Session → nach Session-Ende restoren
- Vorteil: kein `DYLD_INSERT_LIBRARIES` (sicherer, kein Anti-Cheat-Trigger, keine Inkompatibilität mit anderen System-Interceptions)
- Nachteil: benötigt `com.apple.system-task-ports` Authorization (einmalige Berechtigungs-Anfrage)

**GUI in LutrisForMac:**
- per-Game Profil (Stufe "Off", "Balanced", "Aggressive")
- Profile in `games.json` speicherbar

**Warum zurückgestellt:** Hoher Testaufwand pro macOS-Version (APIs ändern sich), Risiko von Systeminstabilität bei aggressiven Settings. Benötigt gründliches Design und Opt-Out-Mechanismus für Benutzer.

## Auf macOS nicht machbar (gestrichen)

- **Proton-GE / UMU** – Linux-only (ELF-Binaries, Steam-Runtime-Container, Linux-Kernel-Features). Auf macOS via CrossOver/Whisky/Gcenx-Wine abgedeckt.
- **Xenia** (Xbox 360) – D3D12-Features nicht via Metal/MoltenVK abbildbar
- **Wine Wayland-Treiber** – Wayland ist Linux-spezifisch; macOS nutzt Quartz/Core Graphics
- **Proton Experimental/Bleeding Edge** – Proton ist fest an die Steam Linux Runtime gebunden
- **Lutris Runtime** – Linux-Container-Isolation; auf macOS durch stabiles ABI + gebündelte Dependencies in CrossOver/Wine obsolet

## Priorisierungs-Prinzipien

- **Phase 1**: Bestehende Infrastruktur nutzen (ServiceManager, Info.plist), geringer Aufwand, sofort sichtbar
- **Phase 2**: Features, die das Kern-Erlebnis nachhaltig verbessern – weniger Konfigurationsaufwand, mehr Automation
- **Phase 3**: Nützlich für spezifische Zielgruppen (Mehrere Drives, Prime-Nutzer, Lutris.net-Community)
- **Phase 4**: Hoher Aufwand für geringen/flachen Nutzen; erst angehen wenn Basis solide ist oder konkreter Bedarf
- **Zurückgestellt**: Game Session Optimizer – benötigt gründliches Design + Test, bevor er ins Produkt einfließt
