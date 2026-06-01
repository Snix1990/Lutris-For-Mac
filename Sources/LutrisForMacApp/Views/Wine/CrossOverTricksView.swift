import SwiftUI

struct CrossOverTricksView: View {
    @StateObject private var manager = CrossOverTricksManager.shared
    @ObservedObject var wineManager: WineManager
    @State private var selectedBottle: WinePrefix?
    @State private var selectedComponents: Set<String> = []
    @State private var searchText = ""
    @State private var isRunning = false
    @State private var task: Task<Void, Never>?
    @State private var installFailed = false

    init(wineManager: WineManager, initialPrefix: WinePrefix? = nil) {
        self.wineManager = wineManager
        _selectedBottle = State(initialValue: initialPrefix)
    }

    private var filteredComponents: [(id: String, name: String, description: String)] {
        var result = CrossOverTricksManager.knownComponents
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if installFailed {
                errorBanner
            }
            if manager.isDownloading {
                downloadingBanner
            }
            bottlePicker
            searchBar
            componentList
            actionBar
            if !manager.output.isEmpty {
                outputLog
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onDisappear { cancel() }
        .task {
            guard !manager.isInstalled, !installFailed else { return }
            do {
                try await manager.downloadIfNeeded()
            } catch {
                installFailed = true
            }
        }
    }

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            LText("crossovertricks konnte nicht installiert werden.")
                .font(.caption)
            Button {
                installFailed = false
                Task { try? await manager.downloadIfNeeded() }
            } label: { LText("Erneut versuchen") }
                .buttonStyle(.link)
            Button {
                manager.detect()
                if manager.isInstalled { installFailed = false }
            } label: { LText("Erneut suchen") }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var downloadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
            LText("Installiere crossovertricks…")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            ProgressView(value: manager.downloadProgress)
                .frame(width: 100)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var bottlePicker: some View {
        Picker(selection: $selectedBottle) {
            LText("Kein Bottle ausgewählt").tag(nil as WinePrefix?)
            ForEach(wineManager.prefixes) { p in
                Text(p.name).tag(p as WinePrefix?)
            }
        } label: {
            LText("Bottle (CrossOver-Prefix)")
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(tr("Komponente suchen…"), text: $searchText)
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

    private var componentList: some View {
        List(filteredComponents, id: \.id) { component in
            HStack {
                Toggle(isOn: Binding(
                    get: { selectedComponents.contains(component.id) },
                    set: { on in
                        if on { selectedComponents.insert(component.id) }
                        else { selectedComponents.remove(component.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(component.name)
                            .font(.system(.body, design: .monospaced))
                            .bold()
                        Text(component.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .disabled(!manager.isInstalled)
            }
        }
        .listStyle(.plain)
    }

    private var actionBar: some View {
        HStack {
            if !selectedComponents.isEmpty {
                Text(verbatim: trf("%d ausgewählt", selectedComponents.count))
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
                Button { run() } label: { LText("Installieren") }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedComponents.isEmpty || selectedBottle == nil || !manager.isInstalled)
            }
        }
        .padding()
    }

    private var outputLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(manager.output)
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
            .onChange(of: manager.output) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func run() {
        guard let bottle = selectedBottle else { return }
        isRunning = true
        let components = Array(selectedComponents)
        task = Task {
            let stream = manager.run(components: components, bottleName: bottle.name)
            for await _ in stream {}
            isRunning = false
            selectedComponents.removeAll()
        }
    }

    private func cancel() {
        task?.cancel()
        isRunning = false
    }
}
