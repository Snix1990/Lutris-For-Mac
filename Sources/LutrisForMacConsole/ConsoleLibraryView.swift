import SwiftUI
import Combine
import LutrisForMacCore

public struct ConsoleLibraryView: View {
    let games: [Game]
    @ObservedObject var consoleState: ConsoleState
    @ObservedObject var focusManager: ConsoleFocusManager
    let onLaunch: ((Game) -> Void)?
    let onShowDetails: ((Game) -> Void)?

    @State private var heroAppeared = false
    @State private var recentsAppeared = false
    @State private var gridAppeared = false
    @State private var gridColumns: Int = 4
    @State private var showFilterPanel: Bool = false
    @State private var showSortPanel: Bool = false
    @State private var heroBannerImage: NSImage?
    @FocusState private var searchFieldFocused: Bool

    @State private var cachedDisplayGames: [Game] = []
    @State private var cachedSearchFiltered: [Game] = []

    public init(
        games: [Game] = ConsoleDataSource.games,
        consoleState: ConsoleState,
        focusManager: ConsoleFocusManager,
        onLaunch: ((Game) -> Void)? = nil,
        onShowDetails: ((Game) -> Void)? = nil
    ) {
        self.games = games
        self.consoleState = consoleState
        self.focusManager = focusManager
        self.onLaunch = onLaunch
        self.onShowDetails = onShowDetails
    }

    private var displayGames: [Game] {
        cachedDisplayGames
    }

    private var searchFilteredGames: [Game] {
        cachedSearchFiltered
    }

    private var availableCategories: [String] {
        Array(Set(displayGames.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    private var availablePlatforms: [String] {
        Array(Set(displayGames.map(\.platform).filter { !$0.isEmpty })).sorted()
    }

    private var availableRunners: [String] {
        Array(Set(displayGames.map(\.runner).filter { !$0.isEmpty })).sorted()
    }

    private struct FilterItem: Identifiable {
        let id = UUID()
        let kind: FilterKind
        let label: String
        let isSelected: Bool
    }

    private var flatFilterItems: [FilterItem] {
        var items: [FilterItem] = []
        for cat in availableCategories {
            items.append(FilterItem(kind: .category, label: cat, isSelected: consoleState.selectedCategory == cat))
        }
        for plat in availablePlatforms {
            items.append(FilterItem(kind: .platform, label: plat, isSelected: consoleState.selectedPlatform == plat))
        }
        for run in availableRunners {
            items.append(FilterItem(kind: .runner, label: run, isSelected: consoleState.selectedRunner == run))
        }
        return items
    }

    private var currentKeyboardRows: [[String]] {
        KeyboardLayoutService.keyboardRows(
            page: consoleState.keyboardPage,
            shifted: consoleState.isShifted,
            layout: consoleState.layoutType
        )
    }

    private func recalcCaches() {
        let filtered = games.filter { game in
            if consoleState.showFavoritesOnly, !game.isFavorite { return false }
            if let cat = consoleState.selectedCategory, game.category != cat { return false }
            if let plat = consoleState.selectedPlatform, game.platform != plat { return false }
            if let run = consoleState.selectedRunner, game.runner != run { return false }
            return true
        }
        cachedDisplayGames = consoleState.sortGames(filtered)

        if consoleState.isSearchActive, !consoleState.searchText.isEmpty {
            cachedSearchFiltered = filtered.filter { $0.name.localizedCaseInsensitiveContains(consoleState.searchText) }
        } else {
            cachedSearchFiltered = filtered
        }
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

                if showFilterPanel && !consoleState.isSearchActive {
                    FilterPanelView(
                        consoleState: consoleState,
                        focusManager: focusManager,
                        availableCategories: availableCategories,
                        availablePlatforms: availablePlatforms,
                        availableRunners: availableRunners,
                        onClose: {
                            withAnimation(.spring(response: 0.35)) {
                                showFilterPanel = false
                            }
                            focusManager.activeSection = .allGames
                            focusManager.focusedIndex = 0
                        }
                    )
                    .padding(.horizontal, 60)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showSortPanel && !consoleState.isSearchActive {
                    SortPanelView(
                        consoleState: consoleState,
                        focusManager: focusManager,
                        onClose: {
                            withAnimation(.spring(response: 0.35)) {
                                showSortPanel = false
                            }
                            focusManager.activeSection = .allGames
                            focusManager.focusedIndex = 0
                        }
                    )
                    .padding(.horizontal, 60)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 36) {
                            ScrollController().frame(width: 0, height: 0)

                            if !consoleState.isSearchActive && !consoleState.filterActive,
                               let lastGame = displayGames.sorted(by: {
                                   ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
                               }).first {
                                HeroSectionView(
                                    game: lastGame,
                                    bannerImage: heroBannerImage,
                                    focusManager: focusManager,
                                    onLaunch: onLaunch,
                                    onShowDetails: onShowDetails
                                )
                                .scaleEffect(heroAppeared ? 1.0 : 0.7)
                                .opacity(heroAppeared ? 1.0 : 0.0)
                                .onAppear {
                                    heroAppeared = true
                                }
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: heroAppeared)
                                .task(id: lastGame.id) {
                                    let store = MediaStore.shared
                                    let gameID = lastGame.id.uuidString
                                    if let cached = store.cachedImage(for: gameID, type: .banner) {
                                        heroBannerImage = cached
                                    } else if !lastGame.bannerURL.isEmpty {
                                        heroBannerImage = await store.loadImage(from: lastGame.bannerURL, gameID: gameID, type: .banner)
                                    } else {
                                        heroBannerImage = nil
                                    }
                                }
                            }

                            if !consoleState.isSearchActive && !consoleState.filterActive {
                                RecentSectionView(
                                    games: recentGames,
                                    cardWidth: cardWidth,
                                    focusManager: focusManager,
                                    onShowDetails: onShowDetails
                                )
                                .opacity(recentsAppeared ? 1.0 : 0.0)
                                .offset(y: recentsAppeared ? 0 : 30)
                                .onAppear {
                                    recentsAppeared = true
                                }
                                .animation(.easeOut(duration: 0.5).delay(0.2), value: recentsAppeared)
                            }

                            allGamesSection(columns: cols, cardWidth: cardWidth)
                                .opacity(gridAppeared ? 1.0 : 0.0)
                                .onAppear {
                                    gridAppeared = true
                                }
                                .animation(.easeOut(duration: 0.5).delay(0.3), value: gridAppeared)
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 28)
                    }
                    .onChange(of: focusManager.focusedIndex) { _, newIndex in
                        guard focusManager.activeSection == .allGames else { return }
                        let games = consoleState.isSearchActive ? searchFilteredGames : displayGames
                        guard newIndex >= 0, newIndex < games.count else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(games[newIndex].id, anchor: .center)
                        }
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
                        onKeyPressed: { key in
                            handleKeyPress(key)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 60)
                    .padding(.bottom, 24)
                }
            }
            .onAppear {
                setupInitialState(cols: cols)
                recalcCaches()
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
            .onChange(of: consoleState.showFavoritesOnly) { _, _ in recalcCaches() }
            .onChange(of: consoleState.selectedCategory) { _, _ in recalcCaches() }
            .onChange(of: consoleState.selectedPlatform) { _, _ in recalcCaches() }
            .onChange(of: consoleState.selectedRunner) { _, _ in recalcCaches() }
            .onChange(of: consoleState.isSearchActive) { _, _ in recalcCaches() }
            .onChange(of: consoleState.searchText) { _, _ in recalcCaches() }
            .onChange(of: consoleState.sortOption) { _, _ in recalcCaches() }
            .onChange(of: consoleState.sortAscending) { _, _ in recalcCaches() }
            .modifier(ControllerNavigationModifier(
                consoleState: consoleState,
                focusManager: focusManager,
                gridColumns: gridColumns,
                onConfirm: { section, index in handleConfirm(section, index) },
                onBack: { handleBack() },
                onSearchToggle: { handleSearchToggle() },
                onUpdateFocusState: { updateFocusState(cols: cols) },
                onSearchActiveChanged: { active in
                    if !active {
                        heroAppeared = false
                        recentsAppeared = false
                        gridAppeared = false
                    }
                }
            ))
        }
    }

    // MARK: - Initial State

    private func setupInitialState(cols: Int) {
        focusManager.gridColumnCount = cols
        focusManager.updateVisibleSections(searchActive: consoleState.isSearchActive)
        updateFocusState(cols: cols)
        gridColumns = cols
    }

    private func updateFocusState(cols: Int) {
        let displayGames = consoleState.isSearchActive ? searchFilteredGames : self.displayGames
        let section = focusManager.activeSection
        if section == .allGames || section == .filter {
            focusManager.itemCountInSection = displayGames.count
        }
        focusManager.gridColumnCount = cols
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
            let games = consoleState.isSearchActive ? searchFilteredGames : displayGames
            if index < games.count {
                onShowDetails?(games[index])
            }

        case .filter:
            let items = flatFilterItems
            guard index < items.count else { return }
            let item = items[index]
            switch item.kind {
            case .category:
                if consoleState.selectedCategory == item.label {
                    consoleState.clearCategoryFilter()
                } else {
                    consoleState.selectedCategory = item.label
                }
            case .platform:
                if consoleState.selectedPlatform == item.label {
                    consoleState.clearPlatformFilter()
                } else {
                    consoleState.selectedPlatform = item.label
                }
            case .runner:
                if consoleState.selectedRunner == item.label {
                    consoleState.clearRunnerFilter()
                } else {
                    consoleState.selectedRunner = item.label
                }
            }
            focusManager.itemCountInSection = items.count

        case .hero:
            let heroGame = displayGames.sorted(by: {
                ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
            }).first
            if index == 0, let lastGame = heroGame {
                onLaunch?(lastGame)
            } else if index == 1, let lastGame = heroGame {
                onShowDetails?(lastGame)
            }

        default:
            break
        }
    }

    private func handleBack() {
        if showFilterPanel {
            withAnimation(.spring(response: 0.35)) {
                showFilterPanel = false
            }
            focusManager.activeSection = .allGames
            focusManager.focusedIndex = 0
            return
        }
        if showSortPanel {
            withAnimation(.spring(response: 0.35)) {
                showSortPanel = false
            }
            focusManager.activeSection = .allGames
            focusManager.focusedIndex = 0
            return
        }
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
                focusManager.focusedIndex = 0
                focusManager.activeSection = .topBar
                heroAppeared = false
                recentsAppeared = false
                gridAppeared = false
            }
        }
    }

    private func handleSearchToggle() {
        if consoleState.isSearchActive {
            withAnimation(.easeOut(duration: 0.25)) {
                consoleState.deactivateSearch()
            }
            focusManager.activeSection = .topBar
            focusManager.focusedIndex = 0
            heroAppeared = false
            recentsAppeared = false
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
                focusManager.activeSection = .topBar
                focusManager.focusedIndex = 0
                focusManager.keyboardActive = false
                focusManager.isKeyboardMode = false
            } else {
                withAnimation(.spring(response: 0.3)) {
                    consoleState.isKeyboardVisible = false
                    focusManager.keyboardActive = false
                    focusManager.isKeyboardMode = false
                }
                let games = consoleState.isSearchActive ? searchFilteredGames : displayGames
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
                            focusManager.activeSection = .topBar
                            focusManager.focusedIndex = 0
                        } else {
                            let games = consoleState.isSearchActive ? searchFilteredGames : displayGames
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
                    .foregroundColor(consoleState.searchText.isEmpty
                                     ? .white.opacity(0.3)
                                     : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !consoleState.searchText.isEmpty {
                Button(action: {
                    consoleState.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                let opening = !showFilterPanel
                withAnimation(.spring(response: 0.35)) {
                    showFilterPanel = opening
                }
                if opening {
                    focusManager.activeSection = .filter
                    focusManager.focusedIndex = 0
                    focusManager.itemCountInSection =
                        availableCategories.count + availablePlatforms.count + availableRunners.count
                } else {
                    focusManager.activeSection = .allGames
                    focusManager.focusedIndex = 0
                }
            }) {
                Image(systemName: consoleState.hasContentFilter
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundColor(consoleState.hasContentFilter ? Color.ps4Pink : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Button(action: {
                let opening = !showSortPanel
                if opening { showFilterPanel = false }
                withAnimation(.spring(response: 0.35)) {
                    showSortPanel = opening
                }
                if opening {
                    focusManager.activeSection = .filter
                    focusManager.focusedIndex = 0
                    focusManager.itemCountInSection = SortOption.allCases.count
                } else {
                    focusManager.activeSection = .allGames
                    focusManager.focusedIndex = 0
                }
            }) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            if !consoleState.isSearchActive {
                Button(action: {
                    handleSearchToggle()
                }) {
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
                .fill(isFocused
                      ? Color.ps4Pink.opacity(0.15)
                      : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Color.ps4Pink : Color.white.opacity(0.15),
                                lineWidth: isFocused ? 2 : 1)
                )
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.2), value: isFocused)
        .onChange(of: searchFieldFocused) { _, focused in
            if focused && consoleState.isPhysicalKeyboardActive {
                // TextField hat Fokus, ggf. weiterer Handler
            }
        }
    }

    // MARK: - Recent Games

    private var recentGames: [Game] {
        displayGames
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - All Games Grid

    @State private var gamesGridId = UUID()

    private func allGamesSection(columns: Int, cardWidth: CGFloat) -> some View {
        let displayGames = consoleState.isSearchActive ? searchFilteredGames : self.displayGames

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: tr(consoleState.isSearchActive ? "ERGEBNISSE" : "ALL GAMES"))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                if consoleState.isSearchActive {
                    Text("(\(displayGames.count))")
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            if displayGames.isEmpty && consoleState.isSearchActive {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.2))
                    Text(verbatim: tr("Keine Spiele gefunden"))
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyGamesGrid(
                    games: displayGames,
                    columns: columns,
                    cardWidth: cardWidth,
                    section: .allGames,
                    focusManager: focusManager,
                    onShowDetails: onShowDetails,
                    focusedIndex: focusManager.activeSection == .allGames ? focusManager.focusedIndex : -1
                )
                .id(gamesGridId)
            }
        }
        .onChange(of: displayGames.count) { _, _ in
            gamesGridId = UUID()
        }
    }
}
