import Foundation

/// Woher die aktuelle Geschwindigkeit stammt.
enum SpeedSource: String, Codable, CaseIterable {
    case gps
    case visual
    case lidar
    case pedometer

    var title: String {
        switch self {
        case .gps: "GPS"
        case .visual: "Kamera"
        case .lidar: "Kamera + LiDAR"
        case .pedometer: "Schrittzähler"
        }
    }

    var symbol: String {
        switch self {
        case .gps: "location.fill"
        case .visual: "camera.aperture"
        case .lidar: "cube.transparent"
        case .pedometer: "shoeprints.fill"
        }
    }

    var isIndoor: Bool { self != .gps }
}

/// Nutzung von Kamera/LiDAR in Innenräumen.
enum IndoorMode: String, CaseIterable, Identifiable {
    case auto, always, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Automatisch"
        case .always: "Immer an"
        case .off: "Aus"
        }
    }
}
