import SwiftUI

public struct ConsoleButtonStyle: ButtonStyle {
    let color: Color

    public init(color: Color) {
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .semibold))
            .padding(.vertical, 14)
            .padding(.horizontal, 32)
            .background(configuration.isPressed ? color.opacity(0.6) : color)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}
