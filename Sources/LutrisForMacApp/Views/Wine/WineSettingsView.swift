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
                WinetricksView(wineManager: wineManager, showHeader: false)
            }
        }
    }

    // MARK: - Versions Tab

    @State private var hoveredDownload: String?

    private var versionsTab: some View {
        GroupBox {
            ScrollView {
                let downloads = WineManager.allKnownDownloads
                if downloads.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        LText("Keine Wine-Versionen gefunden")
                            .foregroundColor(.secondary)
                        Button { wineManager.refresh() } label: { LText("Nach Wine-Versionen suchen") }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 4) {
                        ForEach(downloads) { download in
                            let isHovered = hoveredDownload == download.name
                            let isCached = wineManager.cachedDownloadNames.contains(download.name)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(download.displayName)
                                        .font(.headline)
                                }
                                Spacer()
                                if isCached {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                        LText("Downloaded")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.accentColor)
                                } else {
                                    Button {
                                        Task { try? await wineManager.downloadToCacheOnly(download) }
                                    } label: {
                                        LText("In Cache laden")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(wineManager.isDownloadingToCache)
                                }
                            }
                            .padding(10)
                            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                            .onHover { hovering in
                                hoveredDownload = hovering ? download.name : nil
                            }
                        }
                    }
                }
            }
            .padding(6)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Prefixes Tab

    @State private var showNewPrefixSheet = false
    @State private var hoveredPrefix: UUID?

    private var prefixesTab: some View {
        GroupBox {
            ScrollView {
                VStack(spacing: 6) {
                    if wineManager.prefixes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            LText("Keine Wineprefixes vorhanden")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        Text(verbatim: "Wineprefixes")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                        ForEach(wineManager.prefixes) { prefix in
                            let isHovered = hoveredPrefix == prefix.id
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(prefix.name)
                                            .font(.headline)
                                        if prefix.name.hasPrefix("CrossOver: ") {
                                            badge(text: "CrossOver", color: .purple)
                                        }
                                    }
                                    Text(prefix.path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 8) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "cpu")
                                                .font(.caption2)
                                            Text(prefix.architecture.displayName)
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.blue)
                                        if !prefix.windowsVersion.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "pc")
                                                    .font(.caption2)
                                                Text(prefix.windowsVersion)
                                                    .font(.caption2)
                                            }
                                            .foregroundColor(.secondary)
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

                                Button {
                                    wineManager.deletePrefix(prefix)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                                .helpLText("Prefix löschen")
                            }
                            .padding(10)
                            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                            .onHover { hovering in
                                hoveredPrefix = hovering ? prefix.id : nil
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button { showNewPrefixSheet = true } label: { LText("Neuen Wineprefix erstellen") }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showNewPrefixSheet) {
            NewPrefixSheet(wineManager: wineManager)
        }
    }

    // MARK: - CrossOver Tab

    @State private var showAddCrossover = false
    @State private var hoveredCrossover: UUID?

    private var crossoverTab: some View {
        GroupBox {
            ScrollView {
                VStack(spacing: 6) {
                    if wineManager.crossOverInstallations.isEmpty {
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
                    } else {
                        Text(verbatim: tr("Installierte CrossOver-Versionen"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                        ForEach(wineManager.crossOverInstallations) { co in
                            let isHovered = hoveredCrossover == co.id
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(co.name)
                                            .font(.headline)
                                        if co.isCXPatch {
                                            badge(text: "CXPatch", color: .purple)
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
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                        Text(verbatim: tr("Verfügbar"))
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.green)
                                } else {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .helpLText("Binary nicht gefunden")
                                }
                            }
                            .padding(10)
                            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                            .onHover { hovering in
                                hoveredCrossover = hovering ? co.id : nil
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button { showAddCrossover = true } label: { LText("CrossOver-Installation hinzufügen…") }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .fileImporter(isPresented: $showAddCrossover, allowedContentTypes: [.applicationBundle]) { result in
            if case .success(let url) = result {
                let path = url.path
                if path.hasSuffix(".app") || FileManager.default.isExecutableFile(atPath: "\(path)/Contents/SharedSupport/CrossOver/bin/wine") {
                    wineManager.addCrossOverInstallation(path: path)
                }
            }
        }
    }

    // MARK: - Badges

    private func badge(text: String, color: Color) -> some View {
        LText(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    // MARK: - Helpers

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
