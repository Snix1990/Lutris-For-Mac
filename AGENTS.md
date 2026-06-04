# LutrisForMac – Project Summary

## Goal
Build a SwiftUI macOS game library manager (LutrisForMac) with fully integrated Wine, CrossOver, Steam, Cover, Installer, Discord RPC, Winetricks, Steam Emulator, console emulator download/installation, and 18‑language localization.

## Constraints & Preferences
- 2‑column NavigationSplitView (sidebar / detail); detail column contains LibraryView + GameDetailView overlay; no separate detail column anymore
- GameDetailPanel slides in/out with `.offset(x:)` animation (always rendered, never removed from hierarchy), `.compositingGroup()` for correct shadow rendering
- Sidebar width locked to 180px via `min:180, ideal:180, max:180` → not resizable
- "Favoriten" toggle is standalone at very top of sidebar, outside any Section
- Sidebar section headers use `Section(header: Text(verbatim: tr("..."))) { }` with `.font(.system(size: 16)).textCase(nil)` (3px larger than body)
- Sidebar toggle via `columnVisibility` binding + custom `.primaryAction` button; native toggle removed via `removeNativeSidebarToggle()` in `.task` + every `NSWindow.didBecomeKeyNotification`
- All icons removed from sidebar **except** the Favoriten star
- Every type in its own file (55+ Swift files)
- Installer uses JSON‑based script engine (10 task types) with templates, live progress, community script index
- CrossOver: multiple installations (Standard + CXPatch) selectable per game; bottles imported as WinePrefix entries with arch + Windows version detection
- CrossOver games launched via wine binary directly (Perl wrapper), NOT via NSWorkspace.open – sets `CX_BOTTLE` env var for bottle selection
- Wine‑Render/Performance settings hidden when runner=="CrossOver"
- LanguageManager with pure dictionary-based localization (no Bundle-swizzling); default "en", switchable via dropdown in Settings; all .lproj in `Locals/` folder
- Steam Emulator per‑game toggle (Steamless optional + Goldberg), session login via WKWebView, restore after game exit
- Console emulator auto‑download/install/update from official sources (GitHub releases, Homebrew, direct DMG/ZIP)
- Launch of native macOS apps via `NSWorkspace.shared.openApplication(at:configuration:)` with Discord RPC + pgrep process monitoring
- Plus button shows menu: "Manuell" (name input → library entry) or "Installieren" (existing installer)
- Game deselection: click sidebar filter, click empty space in library, or press sidebar "Alle Spiele" → panel slides out
- All content in detail panel has consistent 10px horizontal padding; GroupBox titles centered at 16pt font
- Bottom toolbar (delete/shortcut/play) fixed at bottom of panel, scrollable content above
- Folder structure: `App/`, `Locals/`, `Models/`, `Services/`, `ViewModels/`, `Views/`

## Progress

### Done

**Wine:**
- WineVersion/WinePrefix models + WineManager (auto-detect Homebrew, Crossover, Whisky, Kegworks; download Gcenx builds via URLSession with 8KB buffer; create/manage prefixes; winecfg/regedit launchers)
- WineSettingsView (version management with download & progress bar, prefix management, CrossOver-Tab)
- WineConfigView (per-game Wine settings: version, prefix, arch, desktop mode, audio driver, DXVMT/WineRenderMode/ESync/FSync/ShaderCache/D3DMetal)
- `WineManager.launchGame()` with full env setup (D3DMetal, DXVK+MVK, virtual desktop, audio driver)
- **CrossOver**: Multiple installations with custom paths, CXPatch detection + badge, CrossOver picker in WineConfigView, CrossOver tab in WineSettingsView, dynamic WineVersion entries per installation

**Runner:**
- Runner model (categories: Wine, Native, Retro, Nintendo, PlayStation, Sega, Handheld, Other; config fields per runner; launch templates: .app, CLI, DOSBox, MAME, ScummVM, RetroArch)
- RunnerManager (detects 17+ runners on macOS: Wine, CrossOver, Whisky, Kegworks, DOSBox, DOSBox-X, ScummVM, MAME, Dolphin, Citra, Ryujinx, MelonDS, PCSX2, RPCS3, DuckStation, Flycast, PPSSPP, RetroArch, OpenEmu; custom runner support; `launchGame()` dispatches by template type)

**Services:**
- Service model + ServiceManager (scan Steam `appmanifest_*.acf`, Heroic Epic/GOG, itch.io `caves.json`, Battle.net known apps)
- ServiceSettingsView (service list + scan/import with progress; duplicate tracking via `imported_games.json`)
- Games have `serviceName: String?` field for service association; Picker in GameEditorView
- Sidebar has separate "Drittanbieter" (service filters) and "Scans" sections

**Installer:**
- InstallerScript model (JSON-based, 10 task types: mkdir, download, extract [zip/tar.*/dmg/7z/rar], execute, wineExecute, wineCfg, createPrefix, setEnvironment, message, input)
- InstallerEngine (variable substitution, live log, progress, user input via continuation, cancel support; DMG mount/unmount via hdiutil)
- InstallerWindowView (template selection → JSON editor → run → success view; auto-adds game to library)
- CommunityInstallerService (fetch script index from URL, cache, download individual script JSONs; configurable index URL in settings sheet)
- CommunityInstallerView (search/browse available community scripts, install button calls InstallerEngine.run(); settings for index URL)
- CommunityScript model (gameName, runner, platform, version, author, scriptURL, coverURL, requires)

**Controller:**
- ControllerManager (GameController.framework: GCControllerDidConnect/Disconnect observers, battery level, product info, vendor)
- ControllerSettingsView (connected controller list with type, battery, live status)

**Desktop Integration:**
- DesktopIntegrationManager (create/remove .app shortcut bundles on Desktop, login item via SMAppService, Discord RPC via Unix socket IPC with SET_ACTIVITY)
- DesktopIntegrationView (login item toggle, Discord RPC toggle, shortcut info)
- **Discord RPC Lifecycle**: Discord-Presence wird beim Spielstart gesetzt und per pgrep-basierter Prozessüberwachung (`waitForGameProcess(exePath:)`) beim Spiel-Ende gelöscht
- **Git**: Remote ist `origin` (HTTPS). `opencode` darf selbstständig committen und pushen. Vor Push immer `git pull --rebase` (global `pull.rebase true`). Commit-Nachrichten auf Englisch, prägnant.

**Search & Organisation:**
- SearchBar in LibraryView (Echtzeit-Filter, X-Button)
- Sort popover (Name, Zuletzt gespielt, Spielzeit, Bewertung, Hinzugefügt – auf-/absteigend)
- Favoriten (Stern in Sidebar/Row/Grid/Tile, Toggle im Editor)
- Kategorien (Freitext, Sidebar-Filter, Tag-Anzeige in Row/Detail)
- Sternebewertung (1–5, in Grid/Row/Detail/Editor, rücksetzbar)
- Spielzeit-Tracking (Sessions >10s, formatiert "2 Std. 30 Min")
- Letztes Spiel-Datum (wird beim Launch gespeichert)

**Cover/Banner:**
- Game-Modell-Felder: `coverURL: String`, `coverPath: String`
- CoverManager (Singleton; cached NSImage + `~/Library/Application Support/LutrisForMac/covers/{uuid}.jpg`; async download; setLocalImage per File Picker)
- SteamGridDBSearcher (Auto-Complete → Grid-Auswahl → Cover URL setzen; API-Key eingebaut)
- CoverSearchView (Sheet mit Suche, Grid-Vorschau, Übernehmen-Button)
- Cover-Anzeige in GameDetailView (120×180px), GameTileView (140px Banner-Hintergrund), GameRowView (40×60px Thumbnail)
- Cover loading triggered via `.onChange(of: game.id)` (fix: GameDetailView wird immer gerendert, daher kein erneutes `.onAppear`)
- Editor: URL + Laden + Online-Suche + Entfernen (Preview entfernt)

**Statistics:**
- StatisticsView (Übersicht-Karten, Spielzeit, Aktivität, Plattform/Kategorie/Runner-Balken, Bewertungsverteilungs-Histogramm, Durchschnittsbewertung)
- ViewModel-Computed Properties (totalPlayTime, averageRating, mostPlayedGame, lastPlayedGame, platformStats, categoryStats, runnerStats, ratingStats)

**Steam Emulator:**
- Per-game toggle (Steamless optional + Goldberg)
- Session login via WKWebView
- Restore after game exit
- Fix: Emulator-Check vor Wine-Runner-Check; `useEmulator` überschreibt alle `-applaunch`-Checks
- Goldberg DLLs deployen per Button in GameDetailView

**Console Emulator System:**
- 18 Emulatoren mit Download/Install/Update/GitHub-API/Version-Tracking

**Language System:**
- 18 Sprachen: de, en, fr, es, it, pt‑BR, ru, zh‑Hans, ja, ko, ar, hi, tr, pl, nl, sv, vi, cs
- `LanguageManager` (Dictionary-basiert, kein Bundle-Swizzling)
- `LanguageStore` (non-isolated, `@unchecked Sendable`), `loadTranslations()`, `@Published var refreshID`
- `tr(_:)` / `trf(_:, _:)` globale Hilfsfunktionen
- `.helpLText("key")` View-Modifier
- `LText` View mit `@StateObject var lang = LanguageManager.shared`
- `.id(lang.refreshID)` auf root-Group erzwingt View-Neu-Erstellung bei Sprachwechsel
- Alle `Text("key")` → `LText("key")`, alle `Label`/`Button`/`Toggle`/`Picker` entsprechend
- `.navigationTitle` mit `Text(verbatim: tr(...))` umgeht `LocalizedStringKey`

**UI & Views:**
- 2-column NavigationSplitView (sidebar + detail), `.detailOnly`
- GameDetailView als Overlay-Panel (ZStack, `.offset(x:)`, `.compositingGroup()`, `.background(.background)`)
- Sidebar: Favoriten-Toggle → Filter → Plattform → Kategorien → Drittanbieter → Scans → System
- Alle Icons aus Sidebar entfernt (außer Favoriten-Stern)
- Plus-Button mit Menu (Manuell / Installieren)
- Deselection bei Klick auf leeren Raum / Sidebar-Filter / "Alle Spiele"
- GroupBox-basierte Content-Sections, Bottom-Toolbar fixiert
- SettingsView mit `.pickerStyle(.menu)`

**Data:**
- Game model: ~30+ Felder (name, platform, installPath, runner, coverURL, category, isFavorite, rating, playTime, lastPlayed, launcherCommand, installScriptPath, environmentVariables, notes, wine*(10), runnerConfig, steamAppID, launchViaSteam, steamEmulatorEnabled, serviceName)
- Persistence via `games.json` in `~/Library/Application Support/LutrisForMac/`
- Codable auto-migration, sample data on first launch

**Build & Structure:**
- `swift build` from project root – full clean build in ~3-4s (incremental ~1-2s)
- Folder structure: `App/`, `Locals/`, `Models/`, `Services/`, `ViewModels/`, `Views/`

### Known / Blocked
- Some download URLs reference Gcenx/wine-on-mac releases; actual builds may need arch verification

## Key Decisions
- **2-column NavigationSplitView** – detail column entfernt, GameDetailView als Overlay-Panel im ZStack. Verhindert Column-Resizing beim Ein-/Ausblenden.
- **Panel immer im ZStack** – nicht per `if let` conditional. `.offset(x:)` statt `.transition(.move(edge:))` → kein Hinter-die-Icons-Rutschen beim Raussliden.
- **`.compositingGroup()` vor `.offset()`** – Background + View als Einheit rendern, Shadow-Artefakte vermeiden.
- **Kein Bundle-Swizzling** – `object_setClass`/`LocalizedBundle` entfernt. Pure Dictionary-Ansätze mit `LanguageStore` + `LText` View.
- **`LText` statt `Text`** – `@StateObject var lang = LanguageManager.shared`, Update via `@Published refreshID`.
- **`tr()` aus nonisolated-Kontext** – `LanguageStore` (non-isolated, Sendable).
- **SPM-Lowercase-Problem** – `.lproj` Lookup mit `code.lowercased()`. `.copy("Locals")` in Package.swift.
- **Sidebar-Breite fixiert** – `min == ideal == max = 180` verhindert Resize per Drag.
- **Sidebar icons entfernt** – alle bis auf Favoriten-Stern, für aufgeräumtes Layout.
- **CrossOver wine binary ist Perl-Wrapper** – erwartet `CX_BOTTLE` env var, ignoriert WINEPREFIX.
- **Game launch flow** – `launchViaSteamEmulator()` → Wine-Runner → NSWorkspace → RunnerManager.
- **`selectedRunner` filtert auch `serviceName`** – für korrekte Drittanbieter-Filterung.
- **Section-Header** – `Section(header: Text(verbatim: tr("..."))) { }` statt `Section { } header: { LText }` (Rendering-Bug in List).
- **Folder-Struktur** – App/Locals/Models/Services/ViewModels/Views/

## Relevant Files
- `App/LutrisForMacApp.swift`: Entry with WindowGroup(id:"installer"), WindowGroup(id:"wine-settings")
- `App/ContentView.swift`: 2-column NavigationSplitView, GameDetailView-Overlay mit `.compositingGroup()` + `.offset()`, `.id(lang.refreshID)` + `.environment(\.locale, lang.locale)`
- `App/WineMenuCommands.swift`: Menu commands for Wine
- `Views/SidebarView.swift`: Favoriten-Toggle an Spitze, Section-Header mit `Text(verbatim: tr("...")).font(.system(size: 16)).textCase(nil)`, Breite fix 180px, keine Icons
- `Views/Library/LibraryView.swift`: SearchBar + Sort + List/Grid + GameRowView + GameTileView; `.frame(maxHeight: .infinity)`
- `Views/Game/GameDetailView.swift`: Overlay-Panel, Cover via `.onChange(of: game.id)`, ScrollView + fixierte Bottom-Toolbar
- `Views/Game/GameEditorView.swift`: Runner-picker, Drittanbieter-Picker, WineConfigView, Organisation, Cover-Section (ohne Preview), notes, env vars, Steam-Optionen
- `Views/Settings/SettingsView.swift`: Language-Picker mit `.pickerStyle(.menu)`
- `Services/LanguageManager.swift`: Dictionary-basiert, kein ObjC. `LanguageStore` (non-isolated), `loadTranslations()`, `@Published refreshID`, `tr()` + `trf()` global, `.helpLText()` View-Modifier
- `Services/WineManager.swift`: Wine detection, download, prefix management, D3DMetal detection, env builder
- `Services/RunnerManager.swift`: 17+ runner detection, launch dispatch
- `Services/ServiceManager.swift`: Service scanning + import, `serviceName` tracking
- `Services/MediaStore.swift`: NSCache + Disk + Index für Cover/Banner/Icon, multi-format support
- `Services/DesktopIntegration.swift`: waitForGameProcess mit pgrep, Discord RPC
- `Services/SteamEmulatorManager.swift`: Steamless + Goldberg
- `Services/EmulatorManager.swift`: 18 Emulatoren detect/install/update
- `Services/ProcessRunner.swift`: Static async Process.run utility
- `Services/ProcessError.swift`: Error types
- `ViewModels/GameLibraryViewModel.swift`: Filter, sort, search, stats computed properties, `serviceName`-Filter
- `Models/Game.swift`: ~30+ Felder + `serviceName`
- `Locals/{lang}.lproj/Localizable.strings`: 18 Sprachen
- `Package.swift`: `.copy("Locals")` resource, Info.plist linker setting
