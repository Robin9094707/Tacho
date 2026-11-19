import SwiftUI

/// Kachel für einen Messwert im Liquid-Glass-Look.
struct StatTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint.opacity(0.9))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// Zeigt die erkannte Fortbewegungsart mit Konfidenz.
struct ActivityBadge: View {
    var activity: ActivityType
    var confidence: Double?
    var manual: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.symbol)
                .font(.headline)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 0) {
                Text(activity.title)
                    .font(.subheadline.weight(.bold))
                Text(manual ? "Manuell" : confidence.map { "Auto · \(Int($0 * 100)) %" } ?? "Auto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(activity.color.opacity(0.35)).interactive(), in: .capsule)
        .animation(.smooth, value: activity)
    }
}

/// Animierter Farbverlauf-Hintergrund, der die Aktivitätsfarbe aufnimmt.
struct AmbientBackground: View {
    var color: Color
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t * 0.35)) * 0.12
            let c = Float(cos(t * 0.27)) * 0.12
            let pts: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(0.5 + s, 0), SIMD2(1, 0),
                SIMD2(0, 0.5 + c), SIMD2(0.5 - s, 0.5 + s), SIMD2(1, 0.5 - c),
                SIMD2(0, 1), SIMD2(0.5 + c, 1), SIMD2(1, 1)
            ]
            let mid = Color(red: 0.05, green: 0.05, blue: 0.12)
            let right = Color(red: 0.08, green: 0.02, blue: 0.12)
            let low = Color(red: 0.03, green: 0.06, blue: 0.1)
            let cols: [Color] = [
                .black, color.opacity(0.35 * intensity), .black,
                mid, color.opacity(0.18 * intensity), right,
                .black, low, .black
            ]
            MeshGradient(width: 3, height: 3, points: pts, colors: cols)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 1.2), value: color)
    }
}

/// Mini-Liniendiagramm für die letzten Sekunden.
struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV: Double = max(values.max() ?? 1, 0.5)
            let w = Double(geo.size.width), h = Double(geo.size.height)
            let step: Double = values.count > 1 ? w / Double(values.count - 1) : 0
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: Double(i) * step, y: h * (1 - v / maxV))
            }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.45), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Kleine Routen-Silhouette ohne Kartenkacheln (für Listen).
struct RouteShape: Shape {
    var points: [TrackPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count > 1 else { return p }
        let lats = points.map(\.lat), lons = points.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return p }
        let latScale = cos((minLat + maxLat) / 2 * .pi / 180)
        let w = max((maxLon - minLon) * latScale, 1e-9)
        let h = max(maxLat - minLat, 1e-9)
        let rw = Double(rect.width), rh = Double(rect.height)
        let scale: Double = min(rw / w, rh / h)
        let ox: Double = Double(rect.minX) + (rw - w * scale) / 2
        let oy: Double = Double(rect.minY) + (rh - h * scale) / 2
        let stride = max(1, points.count / 300)
        var first = true
        for (i, pt) in points.enumerated() where i % stride == 0 || i == points.count - 1 {
            let x = ox + (pt.lon - minLon) * latScale * scale
            let y = oy + (maxLat - pt.lat) * scale
            if first { p.move(to: CGPoint(x: x, y: y)); first = false } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

/// Farbe für eine Geschwindigkeit relativ zum Maximum (grün → gelb → rot).
func speedColor(_ fraction: Double) -> Color {
    let f = min(max(fraction, 0), 1)
    if f < 0.5 {
        return Color(red: 0.2 + f * 1.6, green: 0.9, blue: 0.4 - f * 0.6)
    }
    return Color(red: 1.0, green: 0.9 - (f - 0.5) * 1.6, blue: 0.1)
}
