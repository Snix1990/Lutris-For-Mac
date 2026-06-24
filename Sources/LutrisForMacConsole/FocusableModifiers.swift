import SwiftUI

struct FocusHighlightModifier: ViewModifier {
    let isFocused: Bool
    let isHovered: Bool
    let color: Color
    let cornerRadius: CGFloat

    private var isActive: Bool { isFocused || isHovered }

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isActive ? color : Color.clear, lineWidth: 3)
            )
            .shadow(
                color: isActive ? color.opacity(0.5) : .clear,
                radius: isActive ? 16 : 0
            )
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
    }
}

public extension View {
    func focusHighlight(isFocused: Bool, isHovered: Bool = false, color: Color = .ps4Pink, cornerRadius: CGFloat = 12) -> some View {
        modifier(FocusHighlightModifier(isFocused: isFocused, isHovered: isHovered, color: color, cornerRadius: cornerRadius))
    }
}
