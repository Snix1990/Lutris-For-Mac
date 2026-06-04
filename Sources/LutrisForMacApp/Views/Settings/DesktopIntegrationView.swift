import SwiftUI

struct DesktopIntegrationView: View {
    @StateObject private var integration = DesktopIntegrationManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            LText("Desktop-Integration")
                .font(.title2)
                .bold()
                .padding()

            Divider()

            Form {
                Section(header: Text(verbatim: tr("Allgemein"))) {
                    Toggle(isOn: $integration.launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            LText("Automatisch starten")
                            LText("LutrisForMac beim Anmelden starten")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Discord Rich Presence") {
                    Toggle(isOn: $integration.discordEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            LText("Discord-Status anzeigen")
                            LText("Zeigt 'Spielt X' in deinem Discord-Profil")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if integration.discordEnabled {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.green)
                            LText("Aktiv – Status wird beim Spielstart aktualisiert")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Shortcuts (Applications)") {
                    VStack(alignment: .leading, spacing: 8) {
                        LText("Lege Shortcuts im Ordner ~/Applications/Lutris/ an:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.accentColor)
                            LText("Klick auf das Link-Symbol in der Game-Detail-Leiste")
                                .font(.caption)
                        }

                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            LText("Nochmal klicken entfernt den Shortcut")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 380)
    }
}
