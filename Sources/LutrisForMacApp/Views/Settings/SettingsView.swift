import SwiftUI

struct SettingsView: View {
    @StateObject private var lang = LanguageManager.shared
    @StateObject private var desktopManager = DesktopIntegrationManager.shared
    @AppStorage("steamGridDBApiKey") private var steamGridDBApiKey = "91e6b8297bb68f99548e95d4028be9fe"

    var body: some View {
        TabView {
            languageTab
                .tabItem {
                    Label { LText("Sprache / Language") } icon: { Image(systemName: "globe") }
                }

            generalTab
                .tabItem {
                    Label { LText("Allgemein") } icon: { Image(systemName: "gearshape") }
                }
        }
        .frame(width: 480, height: 360)
    }

    private var languageTab: some View {
        Form {
            Section {
                Picker(selection: $lang.language) {
                    ForEach(LanguageManager.availableLanguages, id: \.code) { opt in
                        Text(opt.name).tag(opt.code)
                    }
                } label: {
                    LText("Sprache / Language")
                }
                .pickerStyle(.menu)

                LText("Die Änderung wird sofort übernommen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                LText("The change takes effect immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle(isOn: $desktopManager.launchAtLogin) { LText("LutrisForMac beim Anmelden starten") }
            }

            Section(header: Text(verbatim: tr("API Keys"))) {
                SecureField(tr("SteamGridDB API Key"), text: $steamGridDBApiKey)
                    .helpLText("Dein persönlicher SteamGridDB API-Key. Wird für die Cover-Suche verwendet.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
