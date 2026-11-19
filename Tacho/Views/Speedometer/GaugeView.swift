import SwiftUI

/// Analoges Tacho mit Skala, Leuchtbogen, Nadel und Spitzenwert-Marker.
struct GaugeView: View {
    var value: Double          // in Anzeigeeinheit
    var maxValue: Double
    var peak: Double
    var limit: Double?         // Warnschwelle in Anzeigeeinheit
    var unitLabel: String
    var colors: [Color]
    var subtitle: String

    private let startAngle = 135.0
    private let sweep = 270.0

    private func angle(for v: Double) -> Angle {
        .degrees(startAngle + sweep * min(max(v / maxValue, 0), 1.04))
    }

    private var majorStep: Double {
        switch maxValue {
        case ...20: 2
        case ...40: 5
        case ...60: 10
        case ...160: 20
        case ...400: 40
        default: 100
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2
            let over = limit.map { value > $0 } ?? false

            ZStack {
                // Glas-Zifferblatt
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .circle)

                // Hintergrundbogen
                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .padding(size * 0.06)

                // Leuchtender Fortschrittsbogen
                Circle()
                    .trim(from: 0, to: sweep / 360 * min(max(value / maxValue, 0), 1))
                    .stroke(
                        AngularGradient(colors: over ? [.orange, .red] : colors,
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(sweep)),
                        style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .padding(size * 0.06)
                    .shadow(color: (over ? Color.red : colors[1]).opacity(0.8), radius: size * 0.03)

                // Limit-Markierung
                if let limit, limit < maxValue {
                    Capsule()
                        .fill(.red)
                        .frame(width: size * 0.012, height: size * 0.07)
                        .offset(y: -(r - size * 0.06))
                        .rotationEffect(angle(for: limit) + .degrees(90))
                }

                // Skala
                ticks(size: size, r: r)

                // Spitzenwert
                if peak > 0.5 {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: size * 0.035))
                        .foregroundStyle(.white.opacity(0.85))
                        .offset(y: -(r - size * 0.015))
                        .rotationEffect(angle(for: peak) + .degrees(90))
                }

                // Nadel
                Needle(size: size, color: over ? .red : colors[1])
                    .rotationEffect(angle(for: value) + .degrees(90))
                    .animation(.interpolatingSpring(stiffness: 70, damping: 11), value: value)

                // Nabe
                Circle()
                    .fill(.black.opacity(0.6))
                    .frame(width: size * 0.09)
                    .glassEffect(.regular.tint(colors[1].opacity(0.4)), in: .circle)

                // Digitalwert im unteren Bereich
                VStack(spacing: 0) {
                    Text(value < 10 && maxValue <= 40 ? String(format: "%.1f", value) : String(format: "%.0f", value))
                        .font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: value))
                        .foregroundStyle(over ? .red : .white)
                    Text(unitLabel)
                        .font(.system(size: size * 0.05, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.system(size: size * 0.04, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .offset(y: size * 0.27)
                .animation(.snappy, value: value)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func ticks(size: Double, r: Double) -> some View {
        let minorStep = majorStep / 4
        let count = Int((maxValue / minorStep).rounded())
        ForEach(0...count, id: \.self) { i in
            let v = Double(i) * minorStep
            let major = i % 4 == 0
            Capsule()
                .fill(.white.opacity(major ? 0.9 : 0.35))
                .frame(width: major ? size * 0.008 : size * 0.004,
                       height: major ? size * 0.045 : size * 0.022)
                .offset(y: -(r - size * 0.13))
                .rotationEffect(angle(for: v) + .degrees(90))
            if major {
                Text("\(Int(v))")
                    .font(.system(size: size * 0.045, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .rotationEffect(-(angle(for: v) + .degrees(90)))
                    .offset(y: -(r - size * 0.21))
                    .rotationEffect(angle(for: v) + .degrees(90))
            }
        }
    }
}

private struct Needle: View {
    var size: Double
    var color: Color

    var body: some View {
        ZStack {
            NeedleShape()
                .fill(LinearGradient(colors: [color, .white], startPoint: .bottom, endPoint: .top))
                .frame(width: size * 0.03, height: size * 0.42)
                .shadow(color: color, radius: 8)
                .offset(y: -size * 0.17)
        }
    }
}

private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
