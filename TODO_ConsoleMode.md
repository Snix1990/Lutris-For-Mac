# Console Mode / Big Picture – Todo

## 1 Design & Konzept
- [ ] Moodboard / Referenzen (Steam Big Picture, Playstation UI, Xbox Dashboard, LaunchBox)
- [ ] Entscheidung: Eigenständiges Fenster vs. Fullscreen-Override der bestehenden App
- [ ] Farbpalette + Typografie (groß, kontrastreich, TV-tauglich)
- [ ] UI-Skalierung: automatisch an Bildschirmauflösung anpassen (720p–4K)
- [ ] Sound-Design: Navigations-SFX, Startton, Fehlerton

## 2 Controller-Navigation (vollständig)
- [ ] Fokus-basiertes Navigationssystem (kein Mauszeiger nötig)
- [ ] D-Pad / Stick: Grid-Navigation (oben/unten/links/rechts)
- [ ] A / B / X / Y Belegung: Bestätigen, Zurück, Kontextmenü, Aktion
- [ ] Schultertasten LB/RB: Kategoriesprünge (Seitenleiste, Filter)
- [ ] Start/Select: Einstellungen / Kontextmenü
- [ ] Controller-Vibration bei Interaktion (Haptic Feedback)
- [ ] On-Screen-Tastatur für Texteingabe (Spielname-Suche, WLAN-Passwort)
- [ ] Maus-/Tastatur-Fallback: gleichzeitig bedienbar

## 3 Fullscreen-Launch
- [ ] Dedizierte Vollbild-Scene (eigenes NSWindow / NSWindow.fullScreen)
- [ ] Sanfter Übergang (Crossfade/Scale-Animation beim Start)
- [ ] Splash-Screen mit App-Logo + Ladebalken
- [ ] Automatischer Wechsel in den Konsolen-Modus beim Controller-Anschluss (optional)

## 4 Startbildschirm (Dashboard)
- [ ] Hero-Slot: Großes Cover des zuletzt gespielten Spiels + „Weiterspielen“
- [ ] Raster: Alle Spiele (masonry / uniforme Kacheln 3:4 oder 16:9)
- [ ] Nach Plattform/Runner filterbar (seitliches Overlay-Menü)
- [ ] Favoriten-Reihe (horizontal scrollbar, oben)
- [ ] Zuletzt gespielte Chronologie

## 5 Spiel-Detail-Ansicht
- [ ] Großes Cover/Hintergrundbild (Parallax-Effekt)
- [ ] Metadaten: Spielzeit, Kategorie, Bewertung (Sterne), letztes Spielen
- [ ] Aktionen: Starten, Einstellungen, Speicherstände, Shortcut-Infos
- [ ] Button-Overlay: „A drücken zum Starten“

## 6 Einstellungen (Console-UI)
- [ ] WLAN/Netzwerk-Status-Anzeige
- [ ] Controller-Konfiguration (Button-Mapping, Deadzone, Vibrationsstärke)
- [ ] Audio-Ausgabe (Lautstärke, Ausgabegerät)
- [ ] Cloud-Save-Status + manueller Sync
- [ ] Runtime-OSD-Konfiguration (ein/aus, Position, Metriken)
- [ ] System-Info: macOS-Version, Speicher, GPU

## 7 Medien & Atmosphäre
- [ ] Hintergrundmusik (eigene Playlist oder Soundtrack aus Spielbibliothek)
- [ ] Dynamischer Hintergrund (UI-Hintergrund basierend auf aktuellem Spiel-Cover)
- [ ] Video-Preview / Trailer (wenn im Spiel hinterlegt)
- [ ] Screenshot-Galerie pro Spiel

## 8 Suspend / Resume
- [ ] Spiel pausieren + in den Hintergrund (SIGSTOP)
- [ ] Overlay „Drücke PS/Xbox-Button für Menü“
- [ ] Schnelles Wiederaufnehmen aus dem Standby

## 9 Multi-User / Profiles
- [ ] Profile pro Benutzer (Avatare, Namen, getrennte Spielzeit-Statistiken)
- [ ] Schneller Benutzerwechsel per Controller (wie PS4/Xbox)
- [ ] Cloud-Save-Profilzuordnung

## 10 Onboarding & Tutorial
- [ ] Erster Start: Controller-Verbindung prüfen / anleiten
- [ ] Interaktives Tutorial („Drücke A um ein Spiel zu starten“)
- [ ] Sprachausgabe (Voice-Over für Sehbehinderte, optional)

## 11 Screensaver / Idle
- [ ] Bildschirmschoner nach Inaktivität (Cover-Diaschau)
- [ ] Automatischer Wechsel in Energiesparmodus
- [ ] Controller-Bewegung weckt auf

## 12 Leistung & Stabilität
- [ ] Metal-beschleunigte UI (kein CPU-Rendering)
- [ ] 60 fps garantieren (auch auf älteren Macs)
- [ ] RAM-Sparmodus (Spieleliste auslagern, Cover-Cache begrenzen)
- [ ] Accessibility: VoiceOver, Kontrast-Modus, Schriftvergrößerung
