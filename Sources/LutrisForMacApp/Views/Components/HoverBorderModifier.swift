import SwiftUI

struct HoverBorderModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverBorder() -> some View {
        modifier(HoverBorderModifier())
    }
}
