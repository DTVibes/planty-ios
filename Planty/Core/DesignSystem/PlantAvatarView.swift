import PlantyKit
import SwiftUI

/// The plant character. This is the code-drawn fallback used for every species until its
/// illustrated asset set (pot, 4 growth stages, 5 faces) is added. Mood changes the leaves'
/// colour and posture and the face; the leaves sway gently unless Reduce Motion is on.
struct PlantAvatarView: View {
    var mood: PlantMood = .happy
    var growthStage: GrowthStage = .growing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let sway = reduceMotion ? 0 : sin(time * 2 * .pi / (mood == .thirsty ? 8 : 5)) * 1.8
            let blink = reduceMotion ? false : time.truncatingRemainder(dividingBy: 6) > 5.82
            Canvas { context, size in
                let scale = min(size.width / 120, size.height / 140)
                context.translateBy(x: (size.width - 120 * scale) / 2, y: (size.height - 140 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                drawShadow(in: &context)
                var leaves = context
                leaves.translateBy(x: 60, y: 92)
                leaves.rotate(by: .degrees(sway))
                leaves.translateBy(x: -60, y: -92)
                drawLeaves(in: &leaves)
                drawPot(in: &context)
                drawFace(in: &context, blinking: blink)
            }
        }
        .aspectRatio(120 / 140, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(mood.title))
    }

    // MARK: - Drawing

    private var leafColors: (light: Color, dark: Color) {
        switch mood {
        case .thirsty, .needsAttention: return (Color(light: 0xC3D2AA, dark: 0xA9B993), Color(light: 0x889E73, dark: 0x70845F))
        default: return (Color(light: 0x8ACB98, dark: 0x7DBE8F), Color(light: 0x2E6A43, dark: 0x2E6A43))
        }
    }

    /// Leaf angles and sizes; more and larger leaves at later growth stages, drooping when thirsty.
    private var leafLayout: [(x: Double, y: Double, angle: Double, scale: Double)] {
        let droop = (mood == .thirsty || mood == .needsAttention) ? 1.6 : 1.0
        var layout: [(Double, Double, Double, Double)] = [(60, 48, 0, 1.0)]
        if growthStage.rawValue >= GrowthStage.growing.rawValue {
            layout.append((38, 56, -50 * droop, 0.85))
            layout.append((84, 53, 46 * droop, 0.85))
        }
        if growthStage.rawValue >= GrowthStage.mature.rawValue {
            layout.append((46, 70, -80 * droop, 0.7))
            layout.append((76, 68, 78 * droop, 0.7))
        }
        let sizeBoost = growthStage == .small ? 0.75 : (growthStage == .thriving ? 1.1 : 1.0)
        return layout.map { (x: $0.0, y: $0.1, angle: $0.2, scale: $0.3 * sizeBoost) }
    }

    private func drawShadow(in context: inout GraphicsContext) {
        let shadow = Path(ellipseIn: CGRect(x: 24, y: 129, width: 72, height: 10))
        context.fill(shadow, with: .color(Color.plantyForest.opacity(0.14)))
    }

    private func drawLeaves(in context: inout GraphicsContext) {
        let colors = leafColors
        for leaf in leafLayout {
            var stem = Path()
            stem.move(to: CGPoint(x: 60, y: 90))
            stem.addQuadCurve(to: CGPoint(x: leaf.x, y: leaf.y), control: CGPoint(x: (60 + leaf.x) / 2, y: leaf.y + 20))
            context.stroke(stem, with: .color(Color(light: 0x3E7A50, dark: 0x5F9A6E)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

            var leafContext = context
            leafContext.translateBy(x: leaf.x, y: leaf.y)
            leafContext.rotate(by: .degrees(leaf.angle))
            leafContext.scaleBy(x: leaf.scale, y: leaf.scale)
            let shape = Self.leafPath
            leafContext.fill(
                shape,
                with: .radialGradient(
                    Gradient(colors: [colors.light, colors.dark]),
                    center: CGPoint(x: -6, y: -26),
                    startRadius: 2,
                    endRadius: 40
                ),
                style: FillStyle(eoFill: true)
            )
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: -2))
            vein.addLine(to: CGPoint(x: 0, y: -34))
            leafContext.stroke(vein, with: .color(.white.opacity(0.35)), lineWidth: 1)
        }
    }

    /// Monstera-style leaf with splits, drawn with its base at (0, 0) pointing up.
    private static let leafPath: Path = {
        var path = Path()
        path.move(to: .zero)
        path.addCurve(to: CGPoint(x: -19, y: -29), control1: CGPoint(x: -15, y: -2), control2: CGPoint(x: -24, y: -15))
        path.addCurve(to: CGPoint(x: 0, y: -35), control1: CGPoint(x: -15, y: -39), control2: CGPoint(x: -5, y: -41))
        path.addCurve(to: CGPoint(x: 19, y: -29), control1: CGPoint(x: 5, y: -41), control2: CGPoint(x: 15, y: -39))
        path.addCurve(to: .zero, control1: CGPoint(x: 24, y: -15), control2: CGPoint(x: 15, y: -2))
        path.closeSubpath()
        for split in [[(-20.0, -22.0), (-9.0, -20.0), (-19.0, -16.0)],
                      [(-16.0, -10.0), (-6.0, -12.0), (-12.0, -5.0)],
                      [(20.0, -22.0), (9.0, -20.0), (19.0, -16.0)],
                      [(16.0, -10.0), (6.0, -12.0), (12.0, -5.0)]] {
            path.move(to: CGPoint(x: split[0].0, y: split[0].1))
            path.addLine(to: CGPoint(x: split[1].0, y: split[1].1))
            path.addLine(to: CGPoint(x: split[2].0, y: split[2].1))
            path.closeSubpath()
        }
        return path
    }()

    private func drawPot(in context: inout GraphicsContext) {
        let rim = Path(roundedRect: CGRect(x: 27, y: 84, width: 66, height: 12), cornerRadius: 6)
        context.fill(rim, with: .color(Color(light: 0xE4DAC6, dark: 0xC9BEA6)))
        context.fill(Path(ellipseIn: CGRect(x: 32, y: 84.5, width: 56, height: 5)), with: .color(Color(light: 0x5A4332, dark: 0x4A3628)))
        var body = Path()
        body.move(to: CGPoint(x: 32, y: 95))
        body.addLine(to: CGPoint(x: 88, y: 95))
        body.addLine(to: CGPoint(x: 82.5, y: 127))
        body.addQuadCurve(to: CGPoint(x: 76, y: 132), control: CGPoint(x: 81.5, y: 132))
        body.addLine(to: CGPoint(x: 44, y: 132))
        body.addQuadCurve(to: CGPoint(x: 37.5, y: 127), control: CGPoint(x: 38.5, y: 132))
        body.closeSubpath()
        context.fill(body, with: .linearGradient(
            Gradient(colors: [Color(light: 0xE9E0CC, dark: 0xD6CCB6), Color(light: 0xFFFDF8, dark: 0xF2EDE2), Color(light: 0xD0C3A8, dark: 0xB8AA8E)]),
            startPoint: CGPoint(x: 32, y: 110),
            endPoint: CGPoint(x: 88, y: 110)
        ))
    }

    private func drawFace(in context: inout GraphicsContext, blinking: Bool) {
        let ink = GraphicsContext.Shading.color(Color(rgbHex: 0x24382B))
        let stroke = StrokeStyle(lineWidth: 2.4, lineCap: .round)
        if mood == .thriving {
            var eyes = Path()
            eyes.move(to: CGPoint(x: 46, y: 108)); eyes.addQuadCurve(to: CGPoint(x: 54, y: 108), control: CGPoint(x: 50, y: 103.5))
            eyes.move(to: CGPoint(x: 66, y: 108)); eyes.addQuadCurve(to: CGPoint(x: 74, y: 108), control: CGPoint(x: 70, y: 103.5))
            context.stroke(eyes, with: ink, style: stroke)
        } else if blinking {
            var eyes = Path()
            eyes.move(to: CGPoint(x: 47, y: 108)); eyes.addLine(to: CGPoint(x: 53, y: 108))
            eyes.move(to: CGPoint(x: 67, y: 108)); eyes.addLine(to: CGPoint(x: 73, y: 108))
            context.stroke(eyes, with: ink, style: stroke)
        } else {
            for x in [50.0, 70.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 3.4, y: 104.6, width: 6.8, height: 6.8)), with: ink)
                context.fill(Path(ellipseIn: CGRect(x: x - 2.2, y: 105.7, width: 2.2, height: 2.2)), with: .color(.white))
            }
        }

        var mouth = Path()
        switch mood {
        case .thriving, .happy:
            mouth.move(to: CGPoint(x: 53, y: 115)); mouth.addQuadCurve(to: CGPoint(x: 67, y: 115), control: CGPoint(x: 60, y: 122))
        case .neutral:
            mouth.move(to: CGPoint(x: 54, y: 117)); mouth.addLine(to: CGPoint(x: 66, y: 117))
        case .thirsty, .needsAttention:
            mouth.move(to: CGPoint(x: 53, y: 120)); mouth.addQuadCurve(to: CGPoint(x: 67, y: 120), control: CGPoint(x: 60, y: 115))
        }
        context.stroke(mouth, with: ink, style: stroke)

        if mood == .happy || mood == .thriving {
            let blush = GraphicsContext.Shading.color(Color(rgbHex: 0xEBA49A).opacity(0.55))
            context.fill(Path(ellipseIn: CGRect(x: 39, y: 111.4, width: 8, height: 5.2)), with: blush)
            context.fill(Path(ellipseIn: CGRect(x: 73, y: 111.4, width: 8, height: 5.2)), with: blush)
        }
    }
}

private extension Color {
    init(rgbHex: UInt32) {
        self.init(uiColor: UIColor(rgb: rgbHex))
    }
}

#Preview("Moods") {
    HStack {
        ForEach(PlantMood.allCases, id: \.self) { mood in
            VStack {
                PlantAvatarView(mood: mood, growthStage: .mature).frame(height: 110)
                MoodBadge(mood: mood)
            }
        }
    }
    .padding()
    .plantyScreenBackground()
}
