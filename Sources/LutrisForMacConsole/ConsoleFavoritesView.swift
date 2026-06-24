import SwiftUI
import Combine
import LutrisForMacCore

public struct ConsoleFavoritesView: View {
    let games: [Game]
    let onBack: () -> Void
    @ObservedObject var consoleState: ConsoleState
    @ObservedObject var focusManager: ConsoleFocusManager
    let onLaunch: ((Game) -> Void)?
    let onShowDetails: ((Game) -> Void)?

    @State private var gridAppeared = false
    @State private var gridColumns: Int = 4
    @FocusState private var searchFieldFocused: Bool

    private var favoriteGames: [Game] {
        consoleState.sortGames(games.filter { $0.isFavorite })
    }

    private var searchFiltered: [Game] {
        guard consoleState.isSearchActive, !consoleState.searchText.isEmpty else { return favoriteGames }
        return favoriteGames.filter { $0.name.localizedCaseInsensitiveContains(consoleState.searchText) }
    }

    private var displayGames: [Game] {
        consoleState.isSearchActive ? searchFiltered : favoriteGames
    }

    private var currentKeyboardRows: [[String]] {
        KeyboardLayoutService.keyboardRows(
            page: consoleState.keyboardPage,
            shifted: consoleState.isShifted,
            layout: consoleState.layoutType
        )
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geo in
            let cols = max(Int((geo.size.width - 120) / 220), 2)
            let cardWidth: CGFloat = {
                let gapSpacing: CGFloat = 20
                let w = geo.size.width - 120
                return (w - CGFloat(cols - 1) * gapSpacing) / CGFloat(cols)
            }()

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 60)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 36) {
                            ScrollController().frame(width: 0, height: 0)

                            allGamesGrid(columns: cols, cardWidth: cardWidth)
                                .opacity(gridAppeared ? 1.0 : 0.0)
                                .onAppear {
                                    withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                                        gridAppeared = true
                                    }
                                }

                            if consoleState.isSearchActive
                                && consoleState.isKeyboardVisible
                                && consoleState.searchActivatedByController {
                                OnScreenKeyboardView(
                                    keyboardRows: currentKeyboardRows,
                                    focusedIndex: focusManager.focusedIndex,
                                    keyboardPage: consoleState.keyboardPage,
                                    isShifted: consoleState.isShifted,
                                    layoutType: consoleState.layoutType,
                                    onKeyPressed: { key in handleKeyPress(key) }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .padding(.bottom, 20)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 28)
                    }
                    .onChange(of: focusManager.focusedIndex) { _, newIndex in
                        guard focusManager.activeSection == .allGames else { return }
                        let games = displayGames
                        guard newIndex >= 0, newIndex < games.count else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(games[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                setupInitialState(cols: cols)
            }
            .onChange(of: cols) { _, newCols in
                focusManager.gridColumnCount = newCols
                gridColumns = newCols
            }
            .onChange(of: consoleState.isPhysicalKeyboardActive) { _, active in
                if active {
                    consoleState.isKeyboardVisible = false
                    focusManager.keyboardActive = false
                    focusManager.isKeyboardMode = false
                    focusManager.updateItemCountForCurrentSection()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        searchFieldFocused = true
                    }
                }
            }
            .modifier(ControllerNavigationModifier(
                consoleState: consoleState,
                focusManager: focusManager,
                gridColumns: gridColumns,
                onConfirm: { section, index in handleConfirm(section, index) },
                onBack: { handleBack() },
                onSearchToggle: { handleSearchToggle() },
                onUpdateFocusState: { updateFocusState() },
                onSearchActiveChanged: { active in
                    if !active { gridAppeared = false }
                }
            ))
        }
    }

    // MARK: - Initial State

    private func setupInitialState(cols: Int) {
        focusManager.gridColumnCount = cols
        focusManager.activeSection = .allGames
        focusManager.itemCountInSection = favoriteGames.count
        focusManager.focusedIndex = 0
        gridColumns = cols
    }

    private func updateFocusState() {
        let games = consoleState.isSearchActive ? searchFiltered : favoriteGames
        if focusManager.activeSection == .allGames {
            focusManager.itemCountInSection = games.count
        }
    }

    // MARK: - Search Logic

    private func handleConfirm(_ section: ConsoleSection, _ index: Int) {
        switch section {
        case .search:
            if index == 0 {
                if consoleState.isPhysicalKeyboardActive {
                    searchFieldFocused = true
                } else {
                    withAnimation(.spring(response: 0.4)) {
                        consoleState.isKeyboardVisible = true
                    }
                }
            } else if consoleState.isKeyboardVisible {
                let key = keyAtFlatIndex(index)
                handleKeyPress(key)
            }

        case .allGames:
            let games = consoleState.isSearchActive ? searchFiltered : favoriteGames
            if index < games.count {
                onShowDetails?(games[index])
            }

        default:
            break
        }
    }

    private func handleBack() {
        if consoleState.isSearchActive {
            if consoleState.isKeyboardVisible {
                withAnimation(.spring(response: 0.3)) {
                    consoleState.isKeyboardVisible = false
                    focusManager.keyboardActive = false
                    focusManager.isKeyboardMode = false
                }
                focusManager.focusedIndex = 0
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    consoleState.deactivateSearch()
                }
                focusManager.activeSection = .allGames
                focusManager.focusedIndex = 0
                gridAppeared = false
            }
        } else {
            onBack()
        }
    }

    private func handleSearchToggle() {
        if consoleState.isSearchActive {
            withAnimation(.easeOut(duration: 0.25)) {
                consoleState.deactivateSearch()
            }
            focusManager.activeSection = .allGames
            focusManager.focusedIndex = 0
            gridAppeared = false
        } else {
            consoleState.activateSearch(fromController: true)
            focusManager.activeSection = .search
            focusManager.focusedIndex = 0
            focusManager.isKeyboardMode = true
            focusManager.keyboardActive = true
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.2)) {
                    consoleState.isKeyboardVisible = true
                }
            }
        }
    }

    private func handleKeyPress(_ key: String) {
        switch key {
        case "_backspace":
            if !consoleState.searchText.isEmpty {
                consoleState.searchText.removeLast()
            }
        case "_space":
            consoleState.searchText.append(" ")
        case "_done":
            if consoleState.searchText.isEmpty {
                withAnimation(.easeOut(duration: 0.25)) {
                    consoleState.deactivateSearch()
                }
                focusManager.activeSection = .allGames
                focusManager.focusedIndex = 0
                focusManager.keyboardActive = false
                focusManager.isKeyboardMode = false
            } else {
                withAnimation(.spring(response: 0.3)) {
                    consoleState.isKeyboardVisible = false
                    focusManager.keyboardActive = false
                    focusManager.isKeyboardMode = false
                }
                let games = consoleState.isSearchActive ? searchFiltered : favoriteGames
                if !games.isEmpty {
                    focusManager.activeSection = .allGames
                    focusManager.focusedIndex = 0
                    focusManager.itemCountInSection = games.count
                }
            }
        case "_shift":
            consoleState.toggleShift()
        default:
            if !KeyboardLayoutService.isSpecialKey(key) {
                consoleState.searchText.append(key)
            }
        }
    }

    private func keyAtFlatIndex(_ flatIndex: Int) -> String {
        KeyboardLayoutService.keyAtFlatIndex(flatIndex, rows: currentKeyboardRows)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        let isFocused = focusManager.isFocused(section: .search, index: 0)

        return HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(consoleState.isSearchActive ? 0.9 : 0.4))

            if consoleState.isSearchActive && consoleState.isPhysicalKeyboardActive {
                TextField(tr("Suche..."), text: $consoleState.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                    .font(.system(size: 20, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit {
                        if consoleState.searchText.isEmpty {
                            withAnimation(.easeOut(duration: 0.25)) {
                                consoleState.deactivateSearch()
                            }
                            focusManager.activeSection = .allGames
                            focusManager.focusedIndex = 0
                        } else {
                            let games = consoleState.isSearchActive ? searchFiltered : favoriteGames
                            if !games.isEmpty {
                                focusManager.activeSection = .allGames
                                focusManager.focusedIndex = 0
                                focusManager.itemCountInSection = games.count
                            }
                        }
                    }
            } else {
                Text(consoleState.searchText.isEmpty
                     ? tr("Suche")
                     : consoleState.searchText)
                    .font(.system(size: 20, weight: .regular, design: .monospaced))
                    .foregroundColor(consoleState.searchText.isEmpty ? .white.opacity(0.3) : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !consoleState.searchText.isEmpty {
                Button(action: { consoleState.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            if !consoleState.isSearchActive {
                Button(action: { handleSearchToggle() }) {
                    Image(systemName: "return.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if consoleState.isPhysicalKeyboardActive {
                Text("⌨")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isFocused ? Color.ps4Pink.opacity(0.15) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Color.ps4Pink : Color.white.opacity(0.15), lineWidth: isFocused ? 2 : 1)
                )
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.2), value: isFocused)
    }

    // MARK: - All Games Grid

    private func allGamesGrid(columns: Int, cardWidth: CGFloat) -> some View {
        let games = displayGames
        return VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: tr("FAVORITEN"))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

            if games.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.2))
                    Text(verbatim: tr("Keine Favoriten"))
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: 20), count: columns),
                    spacing: 20
                ) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { idx, game in
                        FocusableGameCard(
                            game: game,
                            section: .allGames,
                            index: idx,
                            focusManager: focusManager,
                            onShowDetails: onShowDetails,
                            coverWidth: cardWidth - 8
                        )
                    }
                }
            }
        }
    }
}
