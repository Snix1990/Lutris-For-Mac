import SwiftUI
import LutrisForMacCore

// ================================================================
// WelcomeView.swift
// ================================================================
// Reagiert auf consoleConfirm (A / Enter / Leertaste)
// und auf Tap-Geste.
// ================================================================

public struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var textOpacity: CGFloat = 0
    @State private var subtitleOpacity: CGFloat = 0


    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 30) {
            Spacer()

            VStack(spacing: 16) {
                Text(verbatim: tr("WELCOME"))
                    .font(.system(size: 100, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.ps4Pink, .ps4Purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(textOpacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.6).delay(0.2)) {
                            textOpacity = 1.0
                        }
                    }

                Text(verbatim: tr("Press A to continue"))
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
                    .opacity(subtitleOpacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.6).delay(0.6)) {
                            subtitleOpacity = 1.0
                        }
                    }
            }

            Spacer()

            Spacer().frame(height: 20)
        }
        .contentShape(Rectangle())
        .onTapGesture { onContinue() }
        .onReceive(NotificationCenter.default.publisher(for: .consoleConfirm)) { _ in
            onContinue()
        }

    }
}
