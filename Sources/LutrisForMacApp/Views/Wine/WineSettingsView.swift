import SwiftUI

struct WineSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var wineManager = WineManager.shared
    @State private var selectedTab: Tab = .versions

    enum Tab: String, CaseIterable {
        case versions = "Wine-Versionen"
        case prefixes = "Wineprefixes"
        case crossover = "CrossOver"
        case winetricks = "Winetricks"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                LText("Wine-Einstellungen")
                    .font(.title2)
                    .bold()
                Spacer()
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch selectedTab {
            case .versions:
                versionsTab
            case .prefixes:
                prefixesTab
            case .crossover:
                crossoverTab
            case .winetricks:
                WinetricksView(wineManager: wineManager)
            }
        }
    }

    // MARK: - Versions Tab

    private var versionsTab: some View {
        List {
            if !wineManager.installedVersions.isEmpty {
                Section(header: Text(verbatim: tr("Installierte Versionen"))) {
                    ForEach(wineManager.installedVersions) { version in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.displayName)
                                    .font(.headline)
                                Text(version.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    iconBadge(systemName: "checkmark.circle.fill", color: .green, text: tr("Installiert"))
                                    sourceBadge(version.type)
                                }
                            }
                            Spacer()
                            if version.wineBinaryPath.isEmpty || !FileManager.default.isExecutableFile(atPath: version.wineBinaryPath) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .helpLText("Wine-Binary nicht gefunden")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            wineManager.removeVersion(wineManager.installedVersions[index])
                        }
                    }
                }
            }

            let available = wineManager.availableDownloads
            if !available.isEmpty {
                Section(header: Text(verbatim: tr("Verfügbar zum Download"))) {
                    ForEach(available) { download in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(download.displayName)
                                    .font(.headline)
                                Text(download.url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                Task {
                                    try? await wineManager.downloadWine(download)
                                }
                            } label: {
                                LText("Herunterladen")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(wineManager.isDownloading)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if wineManager.isDownloading {
                Section("Download") {
                    VStack(alignment: .leading, spacing: 8) {
                        LText("Lade Wine herunter...")
                            .font(.headline)
                        ProgressView(value: wineManager.downloadProgress)
                        if let pct = wineManager.downloadProgress.map({ Int($0 * 100) }) {
                            Text("\(pct)%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            // Wine-Cache
            let cached = wineManager.cachedDownloadNames
            if !cached.isEmpty || !wineManager.availableDownloads.isEmpty {
                Section(header: Text(verbatim: tr("Wine-Cache (vorab geladen)"))) {
                    if !cached.isEmpty {
                        ForEach(cached, id: \.self) { name in
                            let isInstalled = wineManager.installedVersions.contains(where: { $0.name == name })
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(name)
                                        .font(.headline)
                                    if isInstalled {
                                        iconBadge(systemName: "checkmark.circle.fill", color: .green, text: tr("Installiert"))
                                    } else {
                                        iconBadge(systemName: "archivebox.fill", color: .orange, text: "Im Cache")
                                    }
                                }
                                Spacer()
                                if !isInstalled {
                                    Button {
                                        if let dl = wineManager.availableDownloads.first(where: { $0.name == name }) {
                                            Task { try? await wineManager.downloadWine(dl) }
                                        }
                                    } label: { LText("Installieren") }
                                }
                                Button(role: .destructive) {
                                    wineManager.removeCachedArchive(name)
                                } label: { LText("Cache leeren") }
                                    .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        LText("Noch nichts im Cache")
                            .foregroundColor(.secondary)
                    }

                    // Pre-download Buttons
                    if !wineManager.availableDownloads.isEmpty {
                        HStack(spacing: 8) {
                            LText("Ins Cache laden für später:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(wineManager.availableDownloads) { dl in
                                let already = wineManager.isCached(dl.name)
                                Button {
                                    if already {
                                        wineManager.removeCachedArchive(dl.name)
                                    } else {
                                        Task { try? await wineManager.downloadToCacheOnly(dl) }
                                    }
                                } label: {
                                    if already {
                                        Image(systemName: "archivebox.fill")
                                    } else {
                                        Image(systemName: "archivebox")
                                    }
                                }
                                .help(dl.displayName)
                            }
                        }
                    }
                }
            }

            if wineManager.isDownloadingToCache {
                Section("Cache-Download") {
                    VStack(alignment: .leading, spacing: 8) {
                        LText("Lade ins Cache...")
                            .font(.headline)
                        ProgressView(value: wineManager.cacheDownloadProgress)
                    }
                    .padding(.vertical, 8)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button { wineManager.refresh() } label: { LText("Nach Wine-Versionen suchen") }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
    }

    // MARK: - Prefixes Tab

    @State private var showNewPrefixSheet = false

    private var prefixesTab: some View {
        List {
            if wineManager.prefixes.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        LText("Keine Wineprefixes vorhanden")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section("Wineprefixes") {
                    ForEach(wineManager.prefixes) { prefix in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(prefix.name)
                                        .font(.headline)
                                    if prefix.name.hasPrefix("CrossOver: ") {
                                        badgeCrossOverBottle
                                    }
                                }
                                Text(prefix.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    iconBadge(systemName: "cpu", color: .blue, text: prefix.architecture.displayName)
                                    if !prefix.windowsVersion.isEmpty {
                                        iconBadge(systemName: "pc", color: .secondary, text: prefix.windowsVersion)
                                    }
                                    if let last = prefix.lastUsed {
                                        Text(verbatim: trf("Zuletzt: %@", last.formatted(date: .abbreviated, time: .shortened)))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Button("winecfg") {
                                wineManager.runWinecfg(for: prefix)
                            }
                            .buttonStyle(.bordered)
                            .helpLText("Wine-Konfiguration öffnen")

                            Button("regedit") {
                                wineManager.runRegedit(for: prefix)
                            }
                            .buttonStyle(.bordered)
                            .helpLText("Registry-Editor öffnen")
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            wineManager.deletePrefix(wineManager.prefixes[index])
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button { showNewPrefixSheet = true } label: { LText("Neuen Wineprefix erstellen") }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
        .sheet(isPresented: $showNewPrefixSheet) {
            NewPrefixSheet(wineManager: wineManager)
        }
    }

    // MARK: - CrossOver Tab

    @State private var showAddCrossover = false

    private var crossoverTab: some View {
        List {
            if wineManager.crossOverInstallations.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        LText("Keine CrossOver-Installationen gefunden")
                            .foregroundColor(.secondary)
                        LText("Lege CrossOver.app in den Programme-Ordner oder füge es manuell hinzu.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section(header: Text(verbatim: tr("Installierte CrossOver-Versionen"))) {
                    ForEach(wineManager.crossOverInstallations) { co in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(co.name)
                                        .font(.headline)
                                    if co.isCXPatch {
                                        badgeCXPatch
                                    }
                                }
                                Text(co.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !co.version.isEmpty {
                                    Text(verbatim: trf("Version %@", co.version))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if co.isInstalled {
                                iconBadge(systemName: "checkmark.circle.fill", color: .green, text: tr("Verfügbar"))
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .helpLText("Binary nicht gefunden")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            wineManager.removeCrossOverInstallation(wineManager.crossOverInstallations[index])
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button { showAddCrossover = true } label: { LText("CrossOver-Installation hinzufügen…") }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
        .fileImporter(isPresented: $showAddCrossover, allowedContentTypes: [.applicationBundle]) { result in
            if case .success(let url) = result {
                let path = url.path
                if path.hasSuffix(".app") || FileManager.default.isExecutableFile(atPath: "\(path)/Contents/SharedSupport/CrossOver/bin/wine") {
                    wineManager.addCrossOverInstallation(path: path)
                }
            }
        }
    }

    private var badgeCXPatch: some View {
        LText("CXPatch")
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.15))
            .foregroundColor(.purple)
            .cornerRadius(4)
    }

    private var badgeCrossOverBottle: some View {
        LText("CrossOver")
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.15))
            .foregroundColor(.purple)
            .cornerRadius(4)
    }

    // MARK: - Helpers

    private func iconBadge(systemName: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(color)
    }

    private func sourceBadge(_ source: WineVersion.WineSource) -> some View {
        let (icon, color): (String, Color) = {
            switch source {
            case .homebrew: return ("mug.fill", .orange)
            case .crossover: return ("star.fill", .purple)
            case .whisky: return ("drop.fill", .cyan)
            case .wineskin: return ("flask.fill", .green)
            case .system: return ("terminal.fill", .gray)
            case .downloaded: return ("arrow.down.circle.fill", .blue)
            case .yaagl: return ("ladybug.fill", .orange)
            case .custom: return ("gear", .primary)
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(source.rawValue.capitalized)
                .font(.caption2)
        }
        .foregroundColor(color)
    }
}
