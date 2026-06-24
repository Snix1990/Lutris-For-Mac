import SwiftUI
import Combine
import LutrisForMacCore

// ================================================================
// ConsoleNavBar.swift
// ================================================================
// Die NavBar regelt nun Styles und Navigation komplett selbstständig.
// ================================================================

// MARK: - ConsoleNavTab

public struct ConsoleNavTab: Identifiable, Equatable {
    public let id: String
    let title: String
    let icon: String
    let screen: ConsoleScreen
    var forcedHighlight: Bool
    
    public init(
        id: String,
        title: String,
        icon: String,
        screen: ConsoleScreen,
        forcedHighlight: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.screen = screen
        self.forcedHighlight = forcedHighlight
    }

    public static func == (lhs: ConsoleNavTab, rhs: ConsoleNavTab) -> Bool {
        lhs.id == rhs.id
            && lhs.forcedHighlight == rhs.forcedHighlight
            && lhs.screen == rhs.screen
    }
}

// MARK: - ConsoleNavState

@MainActor
public class ConsoleNavState: ObservableObject {
    @Published public var tabs: [ConsoleNavTab] = [
        ConsoleNavTab(id: "lib", title: tr("Library"), icon: "square.grid.2x2.fill", screen: .library),
        ConsoleNavTab(id: "fav", title: tr("Favorites"), icon: "star.fill", screen: .favorites),
        ConsoleNavTab(id: "set", title: tr("Settings"), icon: "gearshape.fill", screen: .settings)
    ]
    @Published public var playerName: String = "Player 1"
    @Published public var playerAvatar: NSImage?
    @Published public var activeScreen: ConsoleScreen = .library
    @Published public var style: NavBarButtonStyle = .ps4Style

    public init() {
        loadCurrentUser()
    }

    
    public func navigate(to screen: ConsoleScreen) {
        self.activeScreen = screen
        // Notify Controller/State that navigation happened
        NotificationCenter.default.post(name: .consoleNavigate, object: screen)
    }

    public func loadCurrentUser() {
        playerName = NSFullUserName()
        playerAvatar = fetchUserAvatar()
    }

    private func fetchUserAvatar() -> NSImage? {
        if let path = userPicturePathFromDSCL() {
            if FileManager.default.fileExists(atPath: path),
               let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        let home = NSHomeDirectory()
        let username = NSUserName()
        let possiblePaths = [
            "\(home)/Library/User Pictures/\(username).tiff",
            "\(home)/Library/User Pictures/\(username).jpg",
            "\(home)/Library/User Pictures/\(username).png",
            "\(home)/Library/User Pictures/Users/\(username).tiff",
            "\(home)/Library/User Pictures/Users/\(username).jpg",
            "\(home)/Library/User Pictures/Users/\(username).png",
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }

    private func userPicturePathFromDSCL() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "read", "/Users/\(NSUserName())", "Picture"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let prefix = "Picture: "
            if let range = output.range(of: prefix) {
                let path = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : path
            }
        } catch {}
        return nil
    }
}

extension Notification.Name {
    static let consoleNavigate = Notification.Name("consoleNavigate")
}

// MARK: - NavBarButton

struct NavBarButton: View {
    let tab: ConsoleNavTab
    let style: NavBarButtonStyle
    let isActive: Bool
    @ObservedObject var focusManager: ConsoleFocusManager
    let section: ConsoleSection
    let index: Int
    @EnvironmentObject private var navState: ConsoleNavState
    
    @State private var isHovered = false
    
    private var isFocused: Bool {
        if section == .topBar {
            focusManager.activeSection == .topBar
                ? focusManager.focusedIndex == index
                : focusManager.lastTopBarFocusIndex == index
        } else {
            focusManager.isFocused(section: section, index: index)
        }
    }
    
    // Farben direkt aus dem aktuellen Style des navState beziehen
    private var fg: Color {
        let isHighlighted = tab.forcedHighlight || isFocused || isHovered
        return isHighlighted ? navState.style.highlightColor : (isActive ? navState.style.activeColor : navState.style.inactiveColor)
    }
    
    private var bg: Color {
        let isHighlighted = tab.forcedHighlight || isFocused || isHovered
        return isHighlighted ? navState.style.backgroundHighlighted : (isActive ? navState.style.backgroundActive : navState.style.backgroundDefault)
    }
    
    var body: some View {
        Button(action: { 
            focusManager.activeSection = section
            focusManager.focusedIndex = index
            if section == .topBar { focusManager.lastTopBarFocusIndex = index }
            navState.navigate(to: tab.screen)
        }) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: navState.style.fontSize))
                Text(tab.title)
                    .font(.system(size: navState.style.fontSize, weight: .light))
            }
            .foregroundColor(fg)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Capsule().fill(bg))
            .overlay(Capsule().stroke(isActive || (tab.forcedHighlight || isFocused || isHovered) ? navState.style.activeColor.opacity(0.4) : .clear, lineWidth: navState.style.borderWidth))
            .shadow(color: (tab.forcedHighlight || isFocused || isHovered) ? navState.style.activeColor.opacity(0.4) : .clear, radius: (tab.forcedHighlight || isFocused || isHovered) ? navState.style.shadowRadius : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - ConsoleNavBar

public struct ConsoleNavBar: View {
    @EnvironmentObject private var navState: ConsoleNavState
    @EnvironmentObject private var focusManager: ConsoleFocusManager

    public init() {}

    public var body: some View {
        if !navState.tabs.isEmpty {
            HStack(spacing: 40) {
                HStack(spacing: 32) {
                    ForEach(Array(navState.tabs.enumerated()), id: \.element.id) { index, tab in
                        NavBarButton(
                            tab: tab,
                            style: navState.style,
                            isActive: navState.activeScreen == tab.screen,
                            focusManager: focusManager,
                            section: .topBar,
                            index: index
                        )
                        .fixedSize()
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    if let avatar = navState.playerAvatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text(navState.playerName)
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 24)
            .onAppear {
                focusManager.topBarItemCount = navState.tabs.count
            }
            .onChange(of: navState.tabs) { _, newTabs in
                focusManager.topBarItemCount = newTabs.count
            }
        }
    }
}
