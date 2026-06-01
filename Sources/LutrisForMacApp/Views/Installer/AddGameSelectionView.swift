import SwiftUI

struct AddGameSelectionView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            LText("Spiel hinzufügen")
                .font(.title2).bold()

            HStack(spacing: 20) {
                selectionButton(
                    icon: "square.and.pencil",
                    title: tr("Manuelle Installation"),
                    description: tr("Lege ein Spiel manuell an und passe alle Einstellungen selbst an.")
                ) {
                    let game = viewModel.addPlaceholderGame()
                    viewModel.pendingManualGameID = game.id
                    dismiss()
                }

                selectionButton(
                    icon: "wand.and.stars",
                    title: tr("Installations-Wizard nutzen"),
                    description: tr("Der Assistent hilft dir Schritt für Schritt bei der Installation.")
                ) {
                    openWindow(id: "installer")
                    dismiss()
                }
            }

            Button { dismiss() } label: { LText("Abbrechen") }
                .keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(width: 520, height: 280)
        .background(MovableWindow())
    }

    private func selectionButton(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                Text(verbatim: title)
                    .font(.headline)
                Text(verbatim: description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160)
            }
            .frame(width: 200, height: 160)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Borderloses Fenster ohne jegliche Dekoration.
private struct MovableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.styleMask = [.fullSizeContentView, .titled, .closable]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.showsToolbarButton = false
            // Alle Traffic-Lights verstecken
            w.standardWindowButton(.closeButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
