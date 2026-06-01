import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct InstallerView: View {
    @Binding var game: Game
    let onRun: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LText("Spiel installation")
                .font(.title2)
                .bold()

            Form {
                Section(header: Text(verbatim: tr("Spiel"))) {
                    TextField(tr("Name"), text: $game.name)
                    HStack {
                        TextField(tr("Installationspfad"), text: $game.installPath)
                        Button { chooseInstallPath() } label: { LText("Wählen") }
                    }
                }

                Section(header: Text(verbatim: tr("Installationsskript"))) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField(tr("Skriptpfad"), text: $game.installScriptPath)
                                .textFieldStyle(.roundedBorder)
                            Button { chooseInstallScript() } label: { LText("Wählen") }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button { NSApplication.shared.keyWindow?.close() } label: { LText("Schliessen") }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await onRun() }
                } label: {
                    Label { LText("Ausführen") } icon: { Image(systemName: "hammer") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }

    private func chooseInstallPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Auswählen")
        if panel.runModal() == .OK, let url = panel.url {
            game.installPath = url.path
        }
    }

    private func chooseInstallScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.shellScript]
        panel.prompt = tr("Skript wählen")
        if panel.runModal() == .OK, let url = panel.url {
            game.installScriptPath = url.path
        }
    }
}
