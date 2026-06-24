import SwiftUI
import Foundation

// MARK: - Deine Color Palette (Customizable)

public extension Color {
    static let ps4Pink = Color(red: 0.95, green: 0.35, blue: 0.65)
    static let ps4Magenta = Color(red: 0.75, green: 0.25, blue: 0.8)
    static let ps4Purple = Color(red: 0.5, green: 0.25, blue: 0.9)
    static let ps4DeepPurple = Color(red: 0.2, green: 0.1, blue: 0.4)
    static let ps4Orange = Color(red: 1.0, green: 0.6, blue: 0.3)
    static let ps4Bg = Color(red: 0.05, green: 0.02, blue: 0.15)
}

// MARK: - Bezier Wave System

@MainActor
class BezierWaveSystem: ObservableObject {
    struct Anchor {
        var angle: CGFloat
        var speed: CGFloat
        var distance: CGFloat
    }

    struct Wave {
        var p1: CGPoint
        var p2: CGPoint
        var a1: Anchor
        var a2: Anchor
        var color: Color
        var lineWidth: CGFloat
    }

    @Published var waves: [Wave] = []

    func setup(screenSize: CGSize) {
        let w = screenSize.width
        let h = screenSize.height

        waves = [
            createWave(
                y: h * 0.43,
                color: Color.ps4Pink.opacity(0.4),
                lineWidth: 1.2,
                screenWidth: w,
                baseAngle1: 32,
                baseAngle2: 214,
                speed: 4.35
            ),
            createWave(
                y: h * 0.48,
                color: Color.ps4Magenta.opacity(0.5),
                lineWidth: 1.5,
                screenWidth: w,
                baseAngle1: 96,
                baseAngle2: 278,
                speed: 4.45
            ),
            createWave(
                y: h * 0.53,
                color: Color.ps4Purple.opacity(0.65),
                lineWidth: 1.8,
                screenWidth: w,
                baseAngle1: 158,
                baseAngle2: 18,
                speed: 4.55
            ),
            createWave(
                y: h * 0.58,
                color: Color.ps4Pink.opacity(0.75),
                lineWidth: 2.0,
                screenWidth: w,
                baseAngle1: 226,
                baseAngle2: 74,
                speed: 4.65
            )
        ]
    }

    private func createWave(
        y: CGFloat,
        color: Color,
        lineWidth: CGFloat,
        screenWidth: CGFloat,
        baseAngle1: CGFloat,
        baseAngle2: CGFloat,
        speed: CGFloat
    ) -> Wave {
        return Wave(
            p1: CGPoint(x: -screenWidth * 0.08, y: y),
            p2: CGPoint(x: screenWidth * 1.08, y: y),
            a1: Anchor(
                angle: baseAngle1,
                speed: speed,
                distance: screenWidth * 0.09
            ),
            a2: Anchor(
                angle: baseAngle2,
                speed: -speed * 0.85,
                distance: screenWidth * 0.09
            ),
            color: color,
            lineWidth: lineWidth
        )
    }

    static func bezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let oneMinusT = 1 - t
        let x = pow(oneMinusT, 3) * p0.x
            + 3 * pow(oneMinusT, 2) * t * p1.x
            + 3 * oneMinusT * pow(t, 2) * p2.x
            + pow(t, 3) * p3.x
        let y = pow(oneMinusT, 3) * p0.y
            + 3 * pow(oneMinusT, 2) * t * p1.y
            + 3 * oneMinusT * pow(t, 2) * p2.y
            + pow(t, 3) * p3.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Star Data (pre-computed positions)

struct StarData {
    let x: CGFloat
    let y: CGFloat
    let phase: Double
    let baseRadius: CGFloat
}

// MARK: - Main View

public struct RetroWaveBackground: View {
    @StateObject private var waveSystem = BezierWaveSystem()
    @State private var hasSetup = false
    @State private var animationStartDate: Date = .now
    @State private var stars: [StarData] = []

    public let speedMultiplier: CGFloat
    public let lowPowerMode: Bool

    private static let starCount = 25

    public init(speedMultiplier: CGFloat = 1.0, lowPowerMode: Bool = false) {
        self.speedMultiplier = speedMultiplier
        self.lowPowerMode = lowPowerMode
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.ps4DeepPurple.opacity(0.6),
                        Color.ps4Bg
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if !lowPowerMode {
                    StarsLayer(stars: stars)
                        .ignoresSafeArea()

                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        Canvas { context, size in
                            if !hasSetup {
                                waveSystem.setup(screenSize: size)
                                stars = Self.makeStars(size: size)
                                animationStartDate = timeline.date
                                hasSetup = true
                            }
                            let elapsed = CGFloat(timeline.date.timeIntervalSince(animationStartDate))

                            for wave in waveSystem.waves {
                                drawWave(context: context, wave: wave, elapsed: elapsed, speedMultiplier: speedMultiplier)
                            }
                        }
                    }
                    .onChange(of: lowPowerMode) { _, newValue in
                        if !newValue { hasSetup = false }
                    }
                }
            }
        }
    }

    private static func makeStars(size: CGSize) -> [StarData] {
        (0..<starCount).map { i -> StarData in
            let seed = Double(i) * 12345.678
            return StarData(
                x: (sin(seed) * 0.5 + 0.5) * size.width,
                y: (cos(seed * 1.3) * 0.5 + 0.5) * size.height * 0.6,
                phase: 0.4 + Double(i) * 0.05,
                baseRadius: 0.3 + (Double(i) / Double(starCount)) * 0.6
            )
        }
    }

    private func drawWave(context: GraphicsContext, wave: BezierWaveSystem.Wave, elapsed: CGFloat, speedMultiplier: CGFloat) {
        let angle1 = wave.a1.angle + wave.a1.speed * elapsed * speedMultiplier
        let angle2 = wave.a2.angle + wave.a2.speed * elapsed * speedMultiplier
        let p0 = wave.p1
        let p1 = CGPoint(x: wave.p1.x + abs(sin(angle1 * .pi / 180)) * wave.a1.distance,
                         y: wave.p1.y + cos(angle1 * .pi / 180) * wave.a1.distance)
        let p2 = CGPoint(x: wave.p2.x + abs(sin(angle2 * .pi / 180)) * -wave.a2.distance,
                         y: wave.p2.y + cos(angle2 * .pi / 180) * wave.a2.distance)
        let p3 = wave.p2

        var path = Path()
        let steps = 80
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let point = BezierWaveSystem.bezierPoint(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(
            path,
            with: .color(wave.color.opacity(0.2)),
            style: StrokeStyle(lineWidth: wave.lineWidth + 4, lineCap: .round)
        )
        context.stroke(
            path,
            with: .color(wave.color.opacity(0.4)),
            style: StrokeStyle(lineWidth: wave.lineWidth + 2, lineCap: .round)
        )
        context.stroke(
            path,
            with: .color(wave.color),
            style: StrokeStyle(lineWidth: wave.lineWidth, lineCap: .round)
        )
    }
}

// MARK: - Sterne

struct StarsLayer: View {
    let stars: [StarData]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                for star in stars {
                    let twinkle = sin(time * star.phase + star.x + star.y) * 0.5 + 0.5
                    let radius = star.baseRadius * (0.5 + twinkle * 0.5)
                    let alpha = 0.15 + twinkle * 0.35

                    let path = Path(ellipseIn: CGRect(
                        x: star.x - radius,
                        y: star.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                    context.fill(path, with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        RetroWaveBackground()

        VStack {
            Text("WILLKOMMEN")
                .font(.system(size: 100, weight: .ultraLight, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.ps4Pink, .ps4Purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Drücke A um ein Spiel auszuwählen")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    .frame(width: 1280, height: 720)
}
