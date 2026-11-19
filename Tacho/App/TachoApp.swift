import SwiftUI
import SwiftData

@main
struct TachoApp: App {
    @State private var engine = TachoEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .preferredColorScheme(.dark)
                .onAppear { engine.start() }
        }
        .modelContainer(for: [Trip.self, SprintResult.self])
    }
}

/// Zentrale Einstellungen-Schlüssel.
enum Pref {
    static let unit = "unit"
    static let gaugeStyle = "gaugeStyle"
    static let speedLimit = "speedLimitKmh"
    static let autoPause = "autoPause"
    static let keepAwake = "keepAwake"
    static let theme = "theme"
    static let haptics = "haptics"
    static let showMiniMap = "showMiniMap"
}

enum GaugeStyle: String, CaseIterable, Identifiable {
    case analog, digital, hud
    var id: String { rawValue }
    var title: String {
        switch self {
        case .analog: "Analog"
        case .digital: "Digital"
        case .hud: "HUD"
        }
    }
    var symbol: String {
        switch self {
        case .analog: "gauge.with.dots.needle.67percent"
        case .digital: "textformat.123"
        case .hud: "car.windshield.front"
        }
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case activity, neon, sunset, ice, racing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .activity: "Nach Aktivität"
        case .neon: "Neon"
        case .sunset: "Sunset"
        case .ice: "Ice"
        case .racing: "Racing"
        }
    }

    func colors(for activity: ActivityType) -> [Color] {
        switch self {
        case .activity: [activity.color.opacity(0.9), activity.color, .white]
        case .neon: [Color(red: 0.1, green: 1, blue: 0.7), Color(red: 0.2, green: 0.6, blue: 1), Color(red: 0.9, green: 0.2, blue: 1)]
        case .sunset: [Color(red: 1, green: 0.8, blue: 0.3), Color(red: 1, green: 0.45, blue: 0.3), Color(red: 0.9, green: 0.15, blue: 0.45)]
        case .ice: [Color(red: 0.75, green: 0.95, blue: 1), Color(red: 0.35, green: 0.7, blue: 1), Color(red: 0.4, green: 0.4, blue: 1)]
        case .racing: [Color(red: 0.3, green: 1, blue: 0.4), Color(red: 1, green: 0.85, blue: 0.1), Color(red: 1, green: 0.15, blue: 0.15)]
        }
    }

    func accent(for activity: ActivityType) -> Color { colors(for: activity)[1] }
}
