import SwiftUI

struct WinetricksView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var winetricks = WinetricksManager.shared
    @ObservedObject var wineManager: WineManager
    @State private var selectedPrefix: WinePrefix?
    @State private var selectedVerbs: Set<String> = []
    @State private var searchText = ""
    @State private var selectedCategory: String = "Alle"
    @State private var isRunning = false
    @State private var task: Task<Void, Never>?
    var wineBinaryPath: String?

    init(wineManager: WineManager, initialPrefix: WinePrefix? = nil, wineBinaryPath: String? = nil) {
        self.wineManager = wineManager
        self.wineBinaryPath = wineBinaryPath
        _selectedPrefix = State(initialValue: initialPrefix)
    }

    private var categories: [String] {
        let cats = Set(winetricks.verbs.map(\.category)).sorted()
        return ["Alle"] + cats
    }

    private var filteredVerbs: [WinetricksVerb] {
        var result = winetricks.verbs
        if selectedCategory != "Alle" {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                LText("Winetricks")
                    .font(.title2)
                    .bold()
                Spacer()
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if !winetricks.isInstalled {
                notInstalledView
            } else {
                contentView
            }
        }
        .frame(minWidth: 760, minHeight: 720)
        .task {
            if winetricks.verbs.isEmpty {
                await winetricks.refreshVerbs()
            }
        }
        .onDisappear {
            cancel()
        }
    }

    private var notInstalledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.adjustable.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            LText("Winetricks nicht gefunden")
                .font(.title2)
            if winetricks.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: winetricks.downloadProgress)
                    LText("Lade Winetricks herunter...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 200)
            } else {
                LText("Winetricks wird automatisch von GitHub geladen und in der App installiert.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                Button {
                    Task {
                        try? await winetricks.downloadIfNeeded()
                        if winetricks.isInstalled {
                            await winetricks.refreshVerbs()
                        }
                    }
                } label: { LText("Winetricks automatisch installieren") }
                .buttonStyle(.borderedProminent)

                LText("Oder via Homebrew:\nbrew install winetricks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    winetricks.detect()
                    if winetricks.isInstalled {
                        Task { await winetricks.refreshVerbs() }
                    }
                } label: { LText("Erneut suchen") }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            prefixPicker
            categoryPicker
            searchBar
            verbList
            actionBar
            if !winetricks.output.isEmpty {
                outputLog
            }
        }
    }

    private var prefixPicker: some View {
        Picker(selection: $selectedPrefix) {
            LText("Kein Prefix ausgewählt").tag(nil as WinePrefix?)
            ForEach(wineManager.prefixes) { p in
                Text(p.name).tag(p as WinePrefix?)
            }
        } label: {
            LText("Prefix")
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var categoryPicker: some View {
        Picker(selection: $selectedCategory) {
            ForEach(categories, id: \.self) { cat in
                Text(cat).tag(cat)
            }
        } label: {
            LText("Kategorie")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(tr("Verb suchen…"), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var verbList: some View {
        List(filteredVerbs) { verb in
            HStack {
                Toggle(isOn: Binding(
                    get: { selectedVerbs.contains(verb.name) },
                    set: { on in
                        if on { selectedVerbs.insert(verb.name) }
                        else { selectedVerbs.remove(verb.name) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verb.name)
                            .font(.system(.body, design: .monospaced))
                            .bold()
                        if !verb.description.isEmpty {
                            Text(verb.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if !selectedVerbs.isEmpty {
                Text(verbatim: trf("%d ausgewählt", selectedVerbs.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isRunning {
                ProgressView()
                    .scaleEffect(0.8)
                Button { cancel() } label: { LText("Abbrechen") }
                    .buttonStyle(.bordered)
            } else {
                Button { run() } label: { LText("Ausführen") }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedVerbs.isEmpty || selectedPrefix == nil)
            }
        }
        .padding()
    }

    private var outputLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(winetricks.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .id("bottom")
            }
            .frame(height: 150)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 4)
            .onChange(of: winetricks.output) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func run() {
        guard let prefix = selectedPrefix else { return }
        isRunning = true
        task = Task {
            let stream = winetricks.run(
                verbs: Array(selectedVerbs),
                prefix: prefix.path,
                architecture: prefix.architecture.rawValue,
                winePath: wineBinaryPath
            )
            for await _ in stream {}
            isRunning = false
            selectedVerbs.removeAll()
        }
    }

    private func cancel() {
        task?.cancel()
        isRunning = false
    }
}
