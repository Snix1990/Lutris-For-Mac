import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @Binding var selectedGameID: UUID?
    @Binding var viewMode: ViewMode
    let onLaunch: ((Game) -> Void)?
    @State private var showSortMenu = false
    @State private var dropTarget = false
    @FocusState private var searchFocused: Bool

    init(viewModel: GameLibraryViewModel, selectedGameID: Binding<UUID?>, viewMode: Binding<ViewMode>, onLaunch: ((Game) -> Void)? = nil) {
        self.viewModel = viewModel
        self._selectedGameID = selectedGameID
        self._viewMode = viewMode
        self.onLaunch = onLaunch
    }

    enum ViewMode: String, CaseIterable {
        case list
        case grid
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(tr("Suchen..."), text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !viewModel.searchText.isEmpty {
                        Button { viewModel.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

                sortButton
                    .popover(isPresented: $showSortMenu) { sortPopover }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                if viewModel.filteredGames.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        LText("Keine Spiele gefunden")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch viewMode {
                    case .list:
                        listContent
                    case .grid:
                        gridContent
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onDrop(of: [.fileURL], delegate: dropDelegate)
            .overlay(
                dropTarget ?
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .padding(8)
                        .animation(.easeInOut(duration: 0.2), value: dropTarget)
                    : nil
            )
        }
        .navigationTitle(Text(verbatim: tr("Meine Bibliothek")))
        .navigationSplitViewColumnWidth(min: 400, ideal: 700, max: .infinity)
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut(Keybinds.shortcut(for: .search).key, modifiers: Keybinds.shortcut(for: .search).modifiers)
                .hidden()
        )
    }

    private var sortButton: some View {
        Button { showSortMenu.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(viewModel.sortOption.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    private var sortPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            LText("Sortieren nach")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $viewModel.sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(verbatim: option.displayName).tag(option)
                }
            }
            .pickerStyle(.radioGroup)

            Divider()

            Toggle(isOn: $viewModel.sortAscending) {
                HStack {
                    Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                    Text(verbatim: tr(viewModel.sortAscending ? "Aufsteigend" : "Absteigend"))
                }
            }
            .toggleStyle(.button)
        }
        .padding()
        .frame(width: 200)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredGames) { game in
                    GameRowView(game: game, isSelected: game.id == selectedGameID, onLaunch: onLaunch.map { launch in { launch(game) } })
                        .highPriorityGesture(
                            TapGesture().onEnded { selectedGameID = game.id }
                        )
                }
            }
        }
        .onTapGesture { selectedGameID = nil }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                ForEach(viewModel.filteredGames) { game in
                    GameTileView(game: game, isSelected: game.id == selectedGameID, onLaunch: onLaunch.map { launch in { launch(game) } })
                        .highPriorityGesture(
                            TapGesture().onEnded { selectedGameID = game.id }
                        )
                }
            }
            .padding()
        }
        .onTapGesture { selectedGameID = nil }
    }

    // MARK: - Drag & Drop

    private var dropDelegate: some DropDelegate {
        GameDropDelegate(viewModel: viewModel, isTarget: $dropTarget)
    }

    private struct GameDropDelegate: DropDelegate {
        let viewModel: GameLibraryViewModel
        @Binding var isTarget: Bool

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.fileURL])
        }

        func dropEntered(info: DropInfo) {
            isTarget = true
        }

        func dropExited(info: DropInfo) {
            isTarget = false
        }

        func performDrop(info: DropInfo) -> Bool {
            isTarget = false
            guard let item = info.itemProviders(for: [.fileURL]).first else { return false }
            item.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self.viewModel.addGame(from: url)
                }
            }
            return true
        }
    }
}
