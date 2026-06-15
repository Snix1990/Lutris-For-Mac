import SwiftUI

struct RetroWaveBackground: View {
    let opacity: Double

    init(opacity: Double = 0.35) {
        self.opacity = opacity
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let w = size.width
                let h = size.height

                for band in 0..<6 {
                    let freq: CGFloat = 15 + CGFloat(band) * 4
                    let speed: CGFloat = 0.4 + CGFloat(band) * 0.15
                    let amp: CGFloat = 12 + CGFloat(band) * 6
                    let phase: CGFloat = CGFloat(band) * 1.2
                    let baseY = h * (0.15 + CGFloat(band) * 0.13)
                    let alpha = 0.08 + (1 - CGFloat(band) / 6) * 0.12

                    let hue: CGFloat = 0.55 + CGFloat(band) * 0.04
                    let color = Color(hue: hue, saturation: 0.8, brightness: 0.9, opacity: alpha * opacity)

                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: baseY))

                    for x in stride(from: 0, through: w, by: 2) {
                        let y = baseY + sin(x / freq + time * speed + phase) * amp
                            + sin(x / (freq * 0.5) + time * speed * 1.3 + phase) * amp * 0.3
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()

                    context.fill(path, with: .color(color))
                }
            }
        }
        .drawingGroup()
    }
}

struct RetroScanlines: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { _ in
            Canvas { context, size in
                for y in stride(from: 0, through: size.height, by: 3) {
                    var path = Path()
                    path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                    context.fill(path, with: .color(.black.opacity(0.08)))
                }
            }
        }
        .allowsHitTesting(false)
        .drawingGroup()
    }
}

struct VignetteOverlay: View {
    var body: some View {
        LinearGradient(
            colors: [.black.opacity(0.4), .clear, .clear, .black.opacity(0.4)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        RetroWaveBackground()
        RetroScanlines()
        VignetteOverlay()
    }
    .frame(width: 800, height: 500)
}
