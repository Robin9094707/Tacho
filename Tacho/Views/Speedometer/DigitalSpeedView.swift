import SwiftUI

/// Große digitale Anzeige mit Balken-Tachometer.
struct DigitalSpeedView: View {
    var value: Double
    var maxValue: Double
    var limit: Double?
    var unitLabel: String
    var colors: [Color]

    private let segments = 28

    var body: some View {
        let over = limit.map { value > $0 } ?? false
        let fraction = min(max(value / maxValue, 0), 1)
        let lit = Int((fraction * Double(segments)).rounded(.up))

        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: value < 10 ? "%.1f" : "%.0f", value))
                    .font(.system(size: 132, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: value))
                    .foregroundStyle(
                        over
                        ? AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(LinearGradient(colors: [.white, colors[1]], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: (over ? Color.red : colors[1]).opacity(0.6), radius: 18)
                Text(unitLabel)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy(duration: 0.25), value: value)

            // Segmentbalken
            HStack(spacing: 3) {
                ForEach(0..<segments, id: \.self) { i in
                    let t = Double(i) / Double(segments - 1)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < lit ? segmentColor(t, over: over) : Color.white.opacity(0.08))
                        .frame(height: 10 + t * 26)
                        .shadow(color: i < lit ? segmentColor(t, over: over).opacity(0.7) : .clear, radius: 4)
                }
            }
            .frame(height: 40, alignment: .bottom)
            .animation(.easeOut(duration: 0.2), value: lit)
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 36))
    }

    private func segmentColor(_ t: Double, over: Bool) -> Color {
        if over { return .red }
        if t < 0.5 { return colors[0] }
        if t < 0.8 { return colors[1] }
        return colors[2]
    }
}

/// HUD-Modus: Gespiegelt für die Windschutzscheibe, maximal groß.
struct HUDView: View {
    var value: Double
    var unitLabel: String
    var color: Color
    var mirrored: Bool

    var body: some View {
        VStack(spacing: -10) {
            Text(String(format: "%.0f", value))
                .font(.system(size: 220, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .contentTransition(.numericText(value: value))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.9), radius: 24)
            Text(unitLabel)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.8))
        }
        .animation(.snappy(duration: 0.25), value: value)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
