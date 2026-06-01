import SwiftUI
import WebKit

struct SteamLoginView: View {
    @Binding var isPresented: Bool
    @State private var status = "Lade Steam-Login…"
    @State private var sessionFound = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(status).font(.caption).foregroundColor(.secondary)
                Spacer()
                if sessionFound {
                    ProgressView().scaleEffect(0.7).padding(.trailing, 4)
                }
                Button { isPresented = false } label: { LText("Schließen") }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(8)

            SteamWebView(
                status: $status,
                sessionFound: $sessionFound,
                onSessionCaptured: { accountName, cookie in
                    SteamEmulatorManager.shared.saveSession(accountName: accountName, cookie: cookie)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isPresented = false
                    }
                }
            )
        }
        .frame(width: 620, height: 560)
    }
}

struct SteamWebView: NSViewRepresentable {
    @Binding var status: String
    @Binding var sessionFound: Bool
    var onSessionCaptured: (String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://steamcommunity.com/login/home/")!))
        context.coordinator.startPolling(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: SteamWebView
        weak var webView: WKWebView?
        var pollTimer: Timer?

        init(parent: SteamWebView) {
            self.parent = parent
        }

        func startPolling(_ wv: WKWebView) {
            webView = wv
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkCookies()
            }
        }

        func checkCookies() {
            guard !parent.sessionFound else { return }
            webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                if let secureCookie = cookies.first(where: { $0.name == "steamLoginSecure" }),
                   let steamID = secureCookie.value.components(separatedBy: "%7C").first,
                   !steamID.isEmpty {
                    let accountName = cookies.first(where: { $0.name == "steamLogin" })?.value
                        .components(separatedBy: "%7C").first ?? ""
                    DispatchQueue.main.async {
                        self.parent.status = "Session erkannt – Account: \(accountName)"
                        self.parent.sessionFound = true
                        self.pollTimer?.invalidate()
                        self.pollTimer = nil
                        self.parent.onSessionCaptured(accountName, secureCookie.value)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.status = "Seite lädt…"
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if let url = webView.url?.absoluteString {
                    self.parent.status = url
                }
                // Beim Seitenwechsel nochmal prüfen
                self.checkCookies()
            }
        }
    }
}

struct SteamSessionStatusView: View {
    @ObservedObject private var emu = SteamEmulatorManager.shared
    @State private var showLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let account = emu.sessionAccountName {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .imageScale(.small)
                    Text("Steam: \(account)")
                        .font(.caption)
                    Button { emu.clearSession() } label: { LText("Abmelden") }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.red)
                }
            } else {
                Button { showLogin = true } label: { LText("Bei Steam anmelden…") }
                .font(.caption)
            }

            if let steamID = emu.sessionSteamID {
                Text("Steam64-ID: \(steamID)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showLogin) {
            SteamLoginView(isPresented: $showLogin)
        }
    }
}

struct SteamEmulatorToolsSection: View {
    @StateObject private var emu = SteamEmulatorManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SteamSessionStatusView()
                .onAppear { emu.refreshDownloadedFlags() }

            if emu.downloadComplete {
                LText("✅ Emulator installiert")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if emu.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    if let progress = emu.downloadProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text(emu.downloadStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = emu.downloadError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    let missing = [(emu.isSteamlessDownloaded, "Steamless"), (emu.isGoldbergDownloaded, "Goldberg")]
                        .filter { !$0.0 }
                        .map { $0.1 }
                    Button { Task { emu.downloadError = nil; try? await emu.downloadTools() } } label: { Text(verbatim: trf("%@ herunterladen", missing.isEmpty ? "Emulator-Tools" : missing.joined(separator: " + "))) }
                    .font(.caption)
                }
            }
        }
    }
}
