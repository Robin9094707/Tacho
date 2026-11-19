import Foundation

enum SpeedUnit: String, CaseIterable, Identifiable, Codable {
    case kmh
    case mph
    case ms
    case knots

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kmh: "km/h"
        case .mph: "mph"
        case .ms: "m/s"
        case .knots: "kn"
        }
    }

    /// Umrechnung von m/s in diese Einheit.
    func convert(_ metersPerSecond: Double) -> Double {
        switch self {
        case .kmh: metersPerSecond * 3.6
        case .mph: metersPerSecond * 2.236936
        case .ms: metersPerSecond
        case .knots: metersPerSecond * 1.943844
        }
    }

    /// Umrechnung von km/h in diese Einheit.
    func fromKmh(_ kmh: Double) -> Double { convert(kmh / 3.6) }

    /// Umrechnung von dieser Einheit nach km/h.
    func toKmh(_ value: Double) -> Double {
        switch self {
        case .kmh: value
        case .mph: value * 1.609344
        case .ms: value * 3.6
        case .knots: value * 1.852
        }
    }

    var usesMiles: Bool { self == .mph }

    func formatDistance(_ meters: Double) -> String {
        if usesMiles {
            let miles = meters / 1609.344
            return miles < 10 ? String(format: "%.2f mi", miles) : String(format: "%.1f mi", miles)
        }
        if meters < 1000 { return String(format: "%.0f m", meters) }
        let km = meters / 1000
        return km < 100 ? String(format: "%.2f km", km) : String(format: "%.0f km", km)
    }

    func formatSpeed(_ metersPerSecond: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f %@", convert(max(0, metersPerSecond)), label)
    }

    /// Pace (min/km bzw. min/mi) – spannend fürs Laufen.
    func formatPace(_ metersPerSecond: Double) -> String {
        guard metersPerSecond > 0.3 else { return "–" }
        let unitMeters = usesMiles ? 1609.344 : 1000
        let secs = unitMeters / metersPerSecond
        let m = Int(secs) / 60, s = Int(secs) % 60
        return String(format: "%d:%02d /%@", m, s, usesMiles ? "mi" : "km")
    }
}

enum Fmt {
    static func duration(_ t: TimeInterval) -> String {
        let total = Int(max(0, t))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func altitude(_ m: Double) -> String { String(format: "%.0f m", m) }

    static func heading(_ deg: Double) -> String {
        guard deg >= 0 else { return "–" }
        let dirs = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        let idx = Int((deg + 22.5) / 45) % 8
        return "\(dirs[idx]) \(Int(deg))°"
    }
}
