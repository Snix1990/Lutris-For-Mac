import SwiftUI

/// Winziges Panel: nur der Lock-Button + Settings-Button
struct LockButtonView: View {
    @StateObject private var osd = OSDManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Button {
                osd.toggleLock()
            } label: {
                Image(systemName: osd.settings.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: osd.settings.fontSize - 2))
                    .foregroundColor(osd.settings.isLocked ? .yellow : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Button {
                if osd.settings.isLocked {
                    osd.toggleLock()
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: osd.settings.fontSize - 2))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(2)
    }
}

/// Winziges Panel: nur die Media-Buttons (prev, play, next)
struct MediaButtonsView: View {
    @StateObject private var osd = OSDManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Button { osd.sendMediaCommand(.previousTrack) } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Button { osd.sendMediaCommand(.togglePlayPause) } label: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Button { osd.sendMediaCommand(.nextTrack) } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
        .padding(2)
    }
}
