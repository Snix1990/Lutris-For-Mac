import SwiftUI

struct OSDOverlayView: View {
    @StateObject private var osd = OSDManager.shared
    @State private var showSettings = false

    var body: some View {
        if showSettings {
            settingsContent
        } else {
            displayContent
        }
    }

    // MARK: - Normal display (L‑Shape)

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: FPS — RAM% — CPU% — Settings, von rechts verankert
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if osd.settings.showFPS {
                    OSDLabel(value: osd.fps, suffix: "FPS", label: "")
                        .fixedSize(horizontal: true, vertical: false)
                }
                if osd.settings.showRAM {
                    OSDLabel(value: osd.ramUsage, suffix: "%", label: "RAM")
                        .fixedSize(horizontal: true, vertical: false)
                }
                if osd.settings.showCPU {
                    OSDLabel(value: osd.cpuUsage, suffix: "%", label: "CPU")
                        .fixedSize(horizontal: true, vertical: false)
                }
                if osd.settings.showGPU {
                    OSDLabel(value: PerformanceMonitor.shared.gpuUsage, suffix: "%", label: "GPU")
                        .fixedSize(horizontal: true, vertical: false)
                }
                lockButton
                    .accessibilityIdentifier("lock_btn")
                settingsButton
            }
            .font(.system(size: osd.settings.fontSize, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Color.black.opacity(osd.settings.opacity)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 6, bottomLeadingRadius: 6,
                            bottomTrailingRadius: 0, topTrailingRadius: 6
                        )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
            )

            // Bottom bar: nur so breit wie der Inhalt, rechtsbündig
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if osd.settings.showFrameTimes {
                        OSDLabel(value: osd.frameTime, suffix: "ms", label: "FT")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if osd.settings.showMediaPlayer {
                        mediaRow
                    }
                    if osd.settings.showLogging {
                        loggingRow
                    }
                }
                .font(.system(size: osd.settings.fontSize, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Color.black.opacity(osd.settings.opacity)
                        .clipShape(
                            UnevenRoundedRectangle(
                                cornerRadii: RectangleCornerRadii(
                                    topLeading: 0, bottomLeading: 6,
                                    bottomTrailing: 6, topTrailing: 0
                                )
                            )
                        )
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                )
            }
        }
        .onAppear { osd.resizeToFit() }
        .onChange(of: osd.fps) { _ in } // keep alive
    }

    // MARK: - Inline settings

    private var settingsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showSettings = false
                    osd.exitSettingsMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                        Text("Zurück")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("OSD")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // Platzhalter für symmetrische Breite
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            OSDSettingsView()
                .frame(width: 320)
        }
        .background(Color.black.opacity(osd.settings.opacity))
        .cornerRadius(6)
    }

    private var mediaRow: some View {
        HStack(spacing: 4) {
            Button { osd.sendMediaCommand(.previousTrack) } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 9))
            }
            .accessibilityIdentifier("media_btn")
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Button { osd.sendMediaCommand(.togglePlayPause) } label: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 9))
            }
            .accessibilityIdentifier("media_btn")
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Button { osd.sendMediaCommand(.nextTrack) } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 9))
            }
            .accessibilityIdentifier("media_btn")
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Text(verbatim: osd.mediaTitle.isEmpty ? "—" : osd.mediaTitle)
                .foregroundColor(.white)
        }
    }

    private var loggingRow: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(osd.loggingActive ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(verbatim: osd.loggingActive ? "Logging" : "Inactive")
                .foregroundColor(osd.loggingActive ? .green : .gray)
        }
    }

    private var lockButton: some View {
        Button {
            osd.toggleLock()
        } label: {
            Image(systemName: osd.settings.isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: osd.settings.fontSize - 2))
                .foregroundColor(osd.settings.isLocked ? .yellow : .white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help(osd.settings.isLocked ? "OSD entsperren" : "OSD sperren (durchklickbar)")
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
            osd.resizeForSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: osd.settings.fontSize - 2))
                .foregroundColor(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("OSD Einstellungen")
    }

    private func openSettings() {
        showSettings = true
        osd.resizeForSettings()
    }
}

struct OSDLabel: View {
    let value: Double
    let suffix: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(verbatim: label)
                    .foregroundColor(.white.opacity(0.6))
            }
            Text(verbatim: formatted)
                .foregroundColor(.white)
                .fontWeight(.semibold)
            Text(verbatim: suffix)
                .foregroundColor(.white.opacity(0.5))
                .font(.system(size: 10))
        }
    }

    private var formatted: String {
        if suffix == "FPS" || suffix == "ms" {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
