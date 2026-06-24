//
//  ConsoleState.swift
//  LutrisForMac
//
//  Created by SniX on 18.06.26.
//


// ConsoleState.swift

import SwiftUI
import LutrisForMacCore

@MainActor
public class ConsoleState: ObservableObject {
    public enum Screen {
        case welcome
        case library
        case settings
    }

    @Published public var currentScreen: Screen = .welcome
    @Published public var waveAnimationProgress: CGFloat = 1.0

    // MARK: - Search State

    @Published public var searchText: String = ""
    @Published public var isSearchActive: Bool = false
    /// Wurde die Suche durch den Select-Button (Controller) gestartet?
    @Published public var searchActivatedByController: Bool = false
    @Published public var isKeyboardVisible: Bool = false
    @Published public var isPhysicalKeyboardActive: Bool = false
    @Published public var isShifted: Bool = false
    @Published public var keyboardPage: Int = 0
    @Published public var layoutType: KeyboardLayoutType = .qwerty

    // MARK: - Filter & Favorites

    /// Zeigt nur Favoriten an (toggle über Favoriten-Tab)
    @Published public var showFavoritesOnly: Bool = false
    /// Kategorie-Filter (z.B. "RPG", "Abenteuer")
    @Published public var selectedCategory: String?
    /// Plattform-Filter (z.B. "Steam", "Windows")
    @Published public var selectedPlatform: String?
    /// Runner-Filter (z.B. "Wine", "Native")
    @Published public var selectedRunner: String?

    // MARK: - Sort

    @Published public var sortOption: SortOption = .name
    @Published public var sortAscending: Bool = true

    public func sortGames(_ games: [Game]) -> [Game] {
        let sorted: [Game]
        switch sortOption {
        case .name:
            sorted = games.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .lastPlayed:
            sorted = games.sorted {
                let l = $0.lastPlayed ?? Date.distantPast
                let r = $1.lastPlayed ?? Date.distantPast
                return l > r
            }
        case .playTime:
            sorted = games.sorted { $0.playTime > $1.playTime }
        case .rating:
            sorted = games.sorted { $0.rating > $1.rating }
        case .recentlyAdded:
            sorted = games.sorted { $0.id.uuidString > $1.id.uuidString }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    public var filterActive: Bool {
        showFavoritesOnly
            || selectedCategory != nil
            || selectedPlatform != nil
            || selectedRunner != nil
    }

    /// Nur Category/Platform/Runner-Filter (ohne showFavoritesOnly)
    /// → für die Filter-Button-Anzeige in der Search-Bar,
    /// damit der Favorites-Tab nicht den Button-Eindruck verändert.
    public var hasContentFilter: Bool {
        selectedCategory != nil
            || selectedPlatform != nil
            || selectedRunner != nil
    }

    private var autoTransitionTask: Task<Void, Never>?

    public init() {}

    // MARK: - Filter Helpers

    public func setFilter(category: String?) {
        selectedCategory = category
        deactivateSearch()
    }

    public func setFilter(platform: String?) {
        selectedPlatform = platform
        deactivateSearch()
    }

    public func setFilter(runner: String?) {
        selectedRunner = runner
        deactivateSearch()
    }

    public func clearAllFilters() {
        showFavoritesOnly = false
        selectedCategory = nil
        selectedPlatform = nil
        selectedRunner = nil
        // Explizites Refresh für SwiftUI falls mehrere Properties gleichzeitig geändert werden
        objectWillChange.send()
    }

    public func clearCategoryFilter() { selectedCategory = nil }
    public func clearPlatformFilter() { selectedPlatform = nil }
    public func clearRunnerFilter()  { selectedRunner = nil }

    // MARK: - Search Helpers

    public func activateSearch(fromController: Bool = false) {
        isSearchActive = true
        isKeyboardVisible = false
        isPhysicalKeyboardActive = false
        searchActivatedByController = fromController
        isShifted = false
        searchText = ""
        keyboardPage = 0
        layoutType = KeyboardLayoutService.currentLayout()
        cancelAutoTransition()
    }

    public func deactivateSearch() {
        isSearchActive = false
        isKeyboardVisible = false
        isPhysicalKeyboardActive = false
        isShifted = false
        searchText = ""
        keyboardPage = 0
    }

    public func toggleKeyboard() {
        isKeyboardVisible.toggle()
    }

    public func switchKeyboardPage() {
        keyboardPage = keyboardPage == 0 ? 1 : 0
        isShifted = false // Shift reset bei Seitenwechsel
    }

    public func toggleShift() {
        isShifted.toggle()
    }

    // MARK: - Screen Navigation

    public func showLibrary() {
        currentScreen = .library
        withAnimation(.easeInOut(duration: 0.8)) {
            waveAnimationProgress = 0.0
        }
        autoTransitionTask?.cancel()
    }

    public func showSettings() {
        currentScreen = .settings
        withAnimation(.easeInOut(duration: 0.8)) {
            waveAnimationProgress = 0.0
        }
        autoTransitionTask?.cancel()
    }

    public func showWelcome() {
        currentScreen = .welcome
        withAnimation(.easeInOut(duration: 0.8)) {
            waveAnimationProgress = 1.0
        }
    }

    public func startAutoTransition(after seconds: TimeInterval = 8.0) {
        autoTransitionTask?.cancel()

        autoTransitionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentScreen == .welcome else { return }
                self.showLibrary()
            }
        }
    }

    public func cancelAutoTransition() {
        autoTransitionTask?.cancel()
    }
}
