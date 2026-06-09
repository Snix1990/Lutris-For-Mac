import SwiftUI

struct SettingsView: View {
    @StateObject private var lang = LanguageManager.shared
    @StateObject private var desktopManager = DesktopIntegrationManager.shared
    @StateObject private var screenshotManager = ScreenshotManager.shared
    @StateObject private var cloudSettings = CloudSyncSettingsManager.shared
    @AppStorage("steamGridDBApiKey") private var steamGridDBApiKey = "91e6b8297bb68f99548e95d4028be9fe"
    @State private var cloudPassword: String = ""
    @State private var cloudStatusMessage: String = ""
    @State private var cloudStatusIsError = false
    @State private var isTestingConnection = false
    @State private var isSigningIntoApple = false

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

            screenshotTab
                .tabItem {
                    Label { LText("Screenshots") } icon: { Image(systemName: "camera") }
                }

            romFoldersTab
                .tabItem {
                    Label { LText("ROM-Ordner") } icon: { Image(systemName: "folder") }
                }

            cloudTab
                .tabItem {
                    Label { LText("Cloud-Sync") } icon: { Image(systemName: "icloud") }
                }

            keybindsTab
                .tabItem {
                    Label { LText("Tastenkombinationen") } icon: { Image(systemName: "keyboard") }
                }

            osdTab
                .tabItem {
                    Label { LText("OSD") } icon: { Image(systemName: "rectangle.3.group") }
                }
        }
        .frame(width: 880, height: 580)
        .onAppear {
            cloudPassword = cloudSettings.savedPassword ?? ""
        }
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

            Section {
                HStack {
                    LText("Version")
                    Spacer()
                    Text(verbatim: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var screenshotTab: some View {
        Form {
            Section(header: Text(verbatim: tr("Screenshot-Ordner"))) {
                HStack {
                    Text(screenshotManager.screenshotFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.message = tr("Wähle einen Ordner für Screenshots")
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                screenshotManager.screenshotFolder = url
                            }
                        }
                    } label: {
                        LText("Ändern…")
                    }
                }
            }

            Section(header: Text(verbatim: tr("Tastenkürzel"))) {
                HStack {
                    LText("Screenshot aufnehmen")
                    Spacer()
                    KeybindRecorderView(
                        keyCode: $screenshotManager.hotkeyKeyCode,
                        modifiers: $screenshotManager.hotkeyModifiers
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var romFoldersTab: some View {
        RomFolderSettingsView()
    }

    private var cloudTab: some View {
        Form {
            Section(header: Text(verbatim: tr("Anbieter"))) {
                Picker(selection: $cloudSettings.settings.providerType) {
                    ForEach(CloudProviderType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                } label: {
                    LText("Cloud-Anbieter")
                }

                if cloudSettings.settings.providerType.needsURL {
                    TextField(tr("Server-URL"), text: $cloudSettings.settings.serverURL)
                        .helpLText("z.B. https://meinserver.de/remote.php/dav/files/benutzer")
                }

                if cloudSettings.settings.providerType.needsUsername {
                    TextField(tr("Benutzername"), text: $cloudSettings.settings.username)
                }

                if cloudSettings.settings.providerType.needsPassword {
                    SecureField(tr("Passwort"), text: $cloudPassword)
                }

                if cloudSettings.settings.providerType.usesAppleSignIn {
                    appleSignInSection
                }
            }

            if cloudSettings.settings.providerType.needsURL {
                Section {
                    HStack(spacing: 12) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            LText("Verbindung testen")
                        }
                        .disabled(isTestingConnection || cloudSettings.settings.serverURL.isEmpty)

                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.7)
                        }

                        if !cloudStatusMessage.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: cloudStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundColor(cloudStatusIsError ? .red : .green)
                                Text(cloudStatusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button {
                        cloudSettings.savePassword(cloudPassword)
                        cloudStatusMessage = tr("Passwort gespeichert")
                        cloudStatusIsError = false
                    } label: {
                        LText("Passwort speichern")
                    }
                    .disabled(cloudPassword.isEmpty)

                    if cloudSettings.savedPassword != nil {
                        Button(role: .destructive) {
                            cloudSettings.clearPassword()
                            cloudPassword = ""
                            cloudStatusMessage = tr("Passwort entfernt")
                            cloudStatusIsError = false
                        } label: {
                            LText("Passwort löschen")
                        }
                    }
                }
            }

            Section(header: Text(verbatim: tr("Sync"))) {
                Toggle(isOn: $cloudSettings.settings.syncEnabled) {
                    LText("Cloud-Sync aktivieren")
                }

                Toggle(isOn: $cloudSettings.settings.autoSyncOnLaunch) {
                    LText("Automatisch syncen beim Spielstart")
                }
                .disabled(!cloudSettings.settings.syncEnabled)
            }

            if cloudSettings.settings.isValid {
                Section {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        LText("Cloud-Sync ist bereit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appleSignInSection: some View {
        Group {
            if cloudSettings.appleSignedIn {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: cloudSettings.appleUserDisplayName)
                            .font(.body)
                        LText("Angemeldet mit Apple iCloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        cloudSettings.clearAppleAuth()
                    } label: {
                        LText("Abmelden")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            } else {
                Button {
                    Task { await signInWithApple() }
                } label: {
                    HStack {
                        Image(systemName: "apple.logo")
                            .font(.title3)
                        if isSigningIntoApple {
                            ProgressView()
                                .scaleEffect(0.7)
                            LText("Anmelden…")
                        } else {
                            LText("Mit Apple anmelden")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isSigningIntoApple)
            }

            if !iCloudAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    LText("iCloud ist nicht aktiviert. Bitte in den Systemeinstellungen anmelden.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func signInWithApple() async {
        isSigningIntoApple = true
        defer { isSigningIntoApple = false }
        do {
            let result = try await AppleSignInManager.shared.signIn()
            cloudSettings.setAppleAuth(userID: result.userID, displayName: result.displayName)
        } catch {
            cloudStatusMessage = trf("Fehler: %@", error.localizedDescription)
            cloudStatusIsError = true
        }
    }

    private func testConnection() async {
        guard let url = URL(string: cloudSettings.settings.serverURL) else {
            cloudStatusMessage = tr("Ungültige Server-URL")
            cloudStatusIsError = true
            return
        }

        isTestingConnection = true
        cloudStatusMessage = ""
        defer { isTestingConnection = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "OPTIONS"

        if !cloudSettings.settings.username.isEmpty && !cloudPassword.isEmpty {
            let auth = "\(cloudSettings.settings.username):\(cloudPassword)"
            if let data = auth.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...399).contains(http.statusCode) {
                    cloudStatusMessage = trf("Verbunden (%d)", http.statusCode)
                    cloudStatusIsError = false
                } else {
                    cloudStatusMessage = trf("Fehler: HTTP %d", http.statusCode)
                    cloudStatusIsError = true
                }
            } else {
                cloudStatusMessage = tr("Keine gültige Antwort")
                cloudStatusIsError = true
            }
        } catch {
            cloudStatusMessage = trf("Fehler: %@", error.localizedDescription)
            cloudStatusIsError = true
        }
    }

    private var keybindsTab: some View {
        KeybindSettingsView()
    }

    private var osdTab: some View {
        OSDSettingsView()
    }
}

// MARK: - Keybind Recorder

struct KeybindRecorderView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: NSEvent.ModifierFlags

    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording = true
        } label: {
            Text(verbatim: isRecording ? "..." : displayString)
                .frame(minWidth: 80)
        }
        .buttonStyle(.bordered)
        .background(isRecording ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .onAppear { NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }
            keyCode = event.keyCode
            modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            isRecording = false
            return nil
        }}
    }

    private var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if let name = keyCodeName(keyCode) { parts.append(name) }
        return parts.isEmpty ? "—" : parts.joined()
    }

    private func keyCodeName(_ code: UInt16) -> String? {
        switch Int(code) {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 18: return "1"; case 19: return "2"; case 20: return "3"
        case 21: return "4"; case 22: return "6"; case 23: return "5"; case 24: return "="
        case 25: return "9"; case 26: return "7"; case 27: return "-"; case 28: return "8"
        case 29: return "0"; case 30: return "]"; case 31: return "O"; case 32: return "U"
        case 33: return "["; case 34: return "I"; case 35: return "P"; case 36: return "Return"
        case 37: return "L"; case 38: return "J"; case 39: return "'"; case 40: return "K"
        case 41: return ";"; case 42: return "\\"; case 43: return ","; case 44: return "/"
        case 45: return "N"; case 46: return "M"; case 47: return "."; case 48: return "Tab"
        case 49: return "Space"; case 50: return "`"; case 51: return "Delete"
        case 53: return "Esc"; case 122: return "F1"; case 120: return "F2"
        case 99: return "F3"; case 118: return "F4"; case 96: return "F5"
        case 97: return "F6"; case 98: return "F7"; case 100: return "F8"
        case 101: return "F9"; case 109: return "F10"; case 103: return "F11"
        case 111: return "F12"; default: return nil
        }
    }
}
