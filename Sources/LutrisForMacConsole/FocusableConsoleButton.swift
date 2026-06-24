import SwiftUI

public struct FocusableConsoleButton: View {
    let title: String
    let icon: String
    let color: Color
    let section: ConsoleSection
    let buttonIndex: Int
    @ObservedObject var focusManager: ConsoleFocusManager
    let action: () -> Void
    let showsHighlightBorder: Bool

    @State private var isHovered = false

    private var isFocused: Bool {
        focusManager.isFocused(section: section, index: buttonIndex)
    }

    private var isHighlighted: Bool {
        isFocused || isHovered
    }

    public init(
        title: String,
        icon: String,
        color: Color,
        section: ConsoleSection,
        buttonIndex: Int,
        focusManager: ConsoleFocusManager,
        action: @escaping () -> Void,
        showsHighlightBorder: Bool = true
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.section = section
        self.buttonIndex = buttonIndex
        self.focusManager = focusManager
        self.action = action
        self.showsHighlightBorder = showsHighlightBorder
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 24, weight: .semibold))
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            .background(color)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(
            Capsule()
                .stroke(isHighlighted && showsHighlightBorder ? Color.ps4Pink.opacity(0.6) : Color.clear, lineWidth: 2)
        )
        .shadow(
            color: isHighlighted && showsHighlightBorder ? Color.ps4Pink.opacity(0.4) : .clear,
            radius: isHighlighted && showsHighlightBorder ? 12 : 0
        )
        .scaleEffect(isHighlighted ? 1.06 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHighlighted)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
