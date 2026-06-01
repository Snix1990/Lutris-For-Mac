# LutrisForMac

**macOS-native Game Library Manager** – SwiftUI + AppKit, inspiriert von [Lutris.net](https://lutris.net).

## Features

### Bibliothek
- 2‑Spalten-Navigation (Sidebar / Detail) – GameDetailView als Overlay-Panel (`.offset(x:)`, immer gerendert, nie aus dem Hierarchy entfernt)
- Listen- & Grid-Ansicht mit Cover-Thumbnails (6:9 Aspect Ratio)
- Echtzeit-Suche, Sortierung (Name, Spielzeit, Bewertung, Datum, Hinzugefügt)
- Favoriten, Kategorien (Freitext-Tags), 1–5‑Sterne-Bewertung
- Spielzeit-Tracking & letztes Spiel-Datum
- Sidebar: Favoriten-Toggle → Filter → Plattform → Kategorien → Drittanbieter → Scans → System (nur Favoriten-Stern als Icon)

### Runner (17+ erkannt)
- **Wine**: CrossOver, Whisky, Kegworks, Homebrew-Wine, Gcenx-Builds, Yaagl
- **CrossOver**: Mehrere Installationen (Standard + CXPatch), benutzerdefinierte Pfade, Bottle-Picker, CXPatch-Badge, **CrossOverTricks** (silent auto-install, 24 Komponenten, Bottle-Auswahl)
- **DOS**: DOSBox, DOSBox‑X
- **ScummVM**, **MAME**
- **Nintendo**: Dolphin (GC/Wii), Citra (3DS), Ryujinx (Switch), MelonDS (DS)
- **PlayStation**: PCSX2 (PS2), RPCS3 (PS3), DuckStation (PS1), Flycast (Dreamcast), PPSSPP (PSP)
- **RetroArch**, **OpenEmu**
- Benutzerdefinierte Runner mit Launch-Template und Konfigurationsfeldern

### Wine-Management
- Versionen downloaden (Gcenx‑/Yaagl‑Wine-Builds) mit Fortschrittsanzeige, Cache in `wine-cache/`
- Prefixe erstellen/löschen (win32/win64), Auswahl existierender Prefixe im Installer
- Pro-Spiel: Wine-Version, Prefix, Architektur, Desktop-Modus, Audio-Treiber, Launch-Arguments
- Render-Modus: Auto (D3DMetal wenn verfügbar, sonst DXVK+MVK), DXVK+MVK, D3DMetal
- ESync/FSync/MSync, Shader Cache
- Game launch via wine binary (Perl-Wrapper) mit `CX_BOTTLE`-Env

### Drittanbieter-Dienste
- **Steam**: Liest `appmanifest_*.acf`, App-Infos via SteamDB
- **Heroic**: Epic & GOG-Spiele
- **itch.io**: Lokaler `caves.json`-Import
- **Battle.net**: Bekannte App-IDs
- **Ryujinx**: Scannt `config.json` (`game_dirs`/`GamesList`), rekursiver ROM-Scan (`.nsp`/`.xci`/`.nca`)
- Service-Zuordnung pro Spiel über `serviceName`-Feld, Sidebar-Filter matcht `runner` und `serviceName`

### Installer
- 5‑Schritte-Wizard (Spiel → Runner → Quelle → Details → Installation) statt freiem Task-Builder
- JSON-basierte Script-Engine (10 Task-Typen: mkdir, download, extract, execute, wineExecute, wineCfg, createPrefix, setEnvironment, message, input)
- DMG-Mount/Unmount via hdiutil, 7z/RAR via lokale Tools
- Community-Script-Index (konfigurierbare URL, Cache, Suche/Browse)
- Prefix-Auswahl im Wizard (neu oder vorhanden)
- Auto-Add zur Bibliothek nach erfolgreicher Installation

### Steam Emulator
- Per‑Game Toggle (Steamless optional + Goldberg)
- Session Login via WKWebView (Cookie-basiert)
- Restore nach Spiel-Ende
- Goldberg DLLs deployen per Button

### Console Emulators
- 18 Emulatoren: Auto-Download/Install/Update aus offiziellen Quellen (GitHub Releases, Homebrew, DMG/ZIP)
- Version-Tracking

### Media / Artwork
- **MediaStore**: `NSCache` (200 Objekte / 100 MB) + Disk-Cache in `media/`
- Drei Typen: Cover, Banner, Icon – **multi-format** (jpg/png/ico/gif/… wird aus Quell-URL übernommen)
- `media_index.json` für schnelle Existenz-Prüfung, alte `covers/` automatisch migriert
- Banner als GameDetailView-Header-Hintergrund mit Gradient-Overlay
- SteamGridDB-Suche mit Auto-Complete + Grid-Auswahl
- Lokale Dateien via File Picker

### Desktop-Integration
- Desktop-Shortcuts (.app-Bundle mit Wrapper-Script)
- Login-Item (SMAppService)
- Discord Rich Presence (Unix Socket IPC, pgrep-basierte Prozess-Überwachung)

### Controller
- GameController.framework: PS/Xbox/Nintendo/MFi-Controller
- Batteriestand, Produktinfo, Live-Status in Einstellungen

### Statistiken
- Gesamtspielzeit, Durchschnittsbewertung, meist-/zuletzt gespieltes Spiel
- Plattform-/Kategorie-/Runner-Balken, Bewertungs-Histogramm, Aktivität

### Lokalisierung
- 18 Sprachen: de, en, fr, es, it, pt‑BR, ru, zh‑Hans, ja, ko, ar, hi, tr, pl, nl, sv, vi, cs
- Dictionary-basiertes System (kein Bundle-Swizzling), `LText` View + `tr()`‑Helper
- Sprachwechsel via Dropdown in Settings, sofortige UI-Aktualisierung

## Architektur

```
Sources/LutrisForMacApp/
├── App/          # ContentView (NavigationSplitView + Overlay), LutrisForMacApp, WineMenuCommands
├── Models/       # Game, Runner, WineVersion, WinePrefix, InstallerScript, …
├── ViewModels/   # GameLibraryViewModel (Filter, Sort, Stats, Persistence)
├── Views/        # SidebarView, LibraryView, GameDetailView, GameEditorView, …
├── Services/     # MediaStore, WineManager, RunnerManager, ServiceManager, EmulatorManager, …
├── Utilities/    # ProcessRunner, ProcessError
├── Locals/       # 18 .lproj mit Localizable.strings
└── package.swift
```

- **Persistence**: `games.json` via Codable, Auto-Migration, `decodeIfPresent` für alle Felder
- **GameDetailView**: **immer gerendert** (kein `if let`), `.offset(x:)` + `.compositingGroup()` + `.background(.background)` für Panel-Slide
- **Textfelder**: alle mit lokalem `@State` Buffer + `@FocusState` + Commit auf Enter/Blur/Game-Switch (verhindert Per-Key-Binding-Propagation)
- **Keine externen Abhängigkeiten** – reines SwiftUI + Foundation + AppKit

## Bauen & Starten

```bash
cd "/Users/mac/Documents/Lutris for mac"
swift build
swift run LutrisForMac
```

Für Xcode:

```bash
open Package.swift
```

> Release‑Build: `swift build -c release && swift run -c release`

## Systemanforderungen

- **macOS 14+** (Sonoma), getestet auf macOS 26.5 Tahoe
- **Apple Silicon** (M1+) empfohlen, x86_64 nicht aktiv getestet
- **Swift 6.0+**

## Projekt-Status

Aktiv in Entwicklung. Siehe [AGENTS.md](AGENTS.md) für detaillierten Fortschritt und [fehlenden_features.md](fehlenden_features.md) für die Roadmap.

### Bekannte Einschränkungen
- Discord RPC benötigt echte App-ID (aktuell Platzhalter)
- Wine-Download-URLs referenzieren Gcenx-Builds – Arch-Kompatibilität prüfen
- SteamGridDB-API‑Key konfigurierbar in Einstellungen
- Kein Proton/UMU – Linux-only (ELFs, Kernel-Features)
- Kein Lutris.net-API-Sync (zukünftig)
