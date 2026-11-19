import SwiftUI

/// Die Fortbewegungsarten, die Tacho erkennt.
enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case stationary
    case walking
    case running
    case cycling
    case eScooter
    case car
    case train
    case plane
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stationary: "Stillstand"
        case .walking: "Gehen"
        case .running: "Rennen"
        case .cycling: "Fahrrad"
        case .eScooter: "E-Scooter"
        case .car: "Auto"
        case .train: "Zug"
        case .plane: "Flugzeug"
        case .unknown: "Unbekannt"
        }
    }

    var symbol: String {
        switch self {
        case .stationary: "figure.stand"
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .eScooter: "scooter"
        case .car: "car.fill"
        case .train: "tram.fill"
        case .plane: "airplane"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .stationary: Color(red: 0.55, green: 0.6, blue: 0.7)
        case .walking: Color(red: 0.25, green: 0.85, blue: 0.55)
        case .running: Color(red: 1.0, green: 0.45, blue: 0.25)
        case .cycling: Color(red: 0.2, green: 0.75, blue: 1.0)
        case .eScooter: Color(red: 0.65, green: 0.45, blue: 1.0)
        case .car: Color(red: 1.0, green: 0.78, blue: 0.2)
        case .train: Color(red: 1.0, green: 0.3, blue: 0.45)
        case .plane: Color(red: 0.35, green: 0.95, blue: 0.95)
        case .unknown: Color.gray
        }
    }

    /// Sinnvolles Skalenende für das analoge Tacho in km/h.
    var gaugeMaxKmh: Double {
        switch self {
        case .stationary, .walking, .unknown: 20
        case .running: 30
        case .cycling: 60
        case .eScooter: 40
        case .car: 240
        case .train: 320
        case .plane: 1000
        }
    }

    /// Typische Arten für Auswahl & Filter (ohne Stillstand/Unbekannt).
    static var selectable: [ActivityType] {
        [.walking, .running, .cycling, .eScooter, .car, .train, .plane]
    }
}
