import Foundation
import CoreMotion

/// Kombiniert iOS-Bewegungserkennung, GPS-Geschwindigkeitsprofil und
/// Vibrationsanalyse zu einer Schätzung der Fortbewegungsart.
struct ActivityClassifier {
    struct Result {
        var activity: ActivityType
        var confidence: Double   // 0…1
        var reason: String
    }

    private var speedWindow: [(Date, Double)] = []   // (Zeit, m/s)
    private var vibrationWindow: [Double] = []
    private var history: [(activity: ActivityType, confidence: Double)] = []
    private(set) var current = Result(activity: .stationary, confidence: 0.3, reason: "Warte auf GPS …")

    mutating func update(speed: Double,
                         accuracy: Double,
                         altitude: Double,
                         vibration: Double,
                         cadence: Double,
                         system: CMMotionActivity?,
                         stepCadence: Double = 0,
                         nearStation: Bool = false,
                         now: Date = .now) -> Result {
        speedWindow.append((now, speed))
        speedWindow.removeAll { now.timeIntervalSince($0.0) > 30 }
        vibrationWindow.append(vibration)
        if vibrationWindow.count > 30 { vibrationWindow.removeFirst(vibrationWindow.count - 30) }

        let speeds = speedWindow.map(\.1)
        let avg = speeds.reduce(0, +) / Double(max(speeds.count, 1))
        let maxV = speeds.max() ?? 0
        let variance = speeds.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(max(speeds.count, 1))
        let speedStd = sqrt(variance)
        let vib = vibrationWindow.reduce(0, +) / Double(max(vibrationWindow.count, 1))

        let kmh = speed * 3.6
        let avgKmh = avg * 3.6
        let maxKmh = maxV * 3.6

        var guess: ActivityType = .unknown
        var conf = 0.5
        var reason = ""

        let sys = system
        let sysConfident = (sys?.confidence ?? .low) != .low

        if avgKmh > 330 || (altitude > 2500 && avgKmh > 200) {
            guess = .plane; conf = 0.95; reason = "Sehr hohe Geschwindigkeit/Höhe"
        } else if kmh < 1.5 && avgKmh < 2.5 {
            guess = .stationary; conf = 0.85; reason = "Keine Bewegung"
        } else if let sys, sysConfident, sys.running, kmh < 30 {
            guess = .running; conf = 0.9; reason = "iOS: Laufbewegung erkannt"
        } else if stepCadence > 2.45 && kmh < 30 {
            guess = .running; conf = 0.85
            reason = "Schrittfrequenz \(Int(stepCadence * 60))/min – Laufschritt"
        } else if let sys, sysConfident, sys.walking, kmh < 10 {
            guess = .walking; conf = 0.9; reason = "iOS: Gehbewegung erkannt"
        } else if stepCadence > 1.1 && kmh < 9 {
            guess = .walking; conf = 0.85
            reason = "Schrittfrequenz \(Int(stepCadence * 60))/min – Gehen"
        } else if let sys, sysConfident, sys.cycling, kmh < 70 {
            guess = .cycling; conf = 0.85; reason = "iOS: Tretbewegung erkannt"
        } else if avgKmh < 7.5 && vib > 0.12 {
            guess = .walking; conf = 0.7; reason = "Schrittmuster, \(Int(avgKmh)) km/h"
        } else if avgKmh < 22 && vib > 0.3 && cadence > 1.8 && stepCadence == 0 || (avgKmh < 22 && vib > 0.3 && stepCadence > 2.2) {
            guess = .running; conf = 0.7; reason = "Starke rhythmische Erschütterung"
        } else {
            // Fahrzeuge: Zug vs. Auto vs. Rad vs. Scooter
            let automotive = (sys?.automotive ?? false)
            let smooth = vib < 0.06
            let steady = speedStd < 1.2   // m/s
            let badGPS = accuracy > 20

            if maxKmh > 165 && (smooth || badGPS) {
                guess = .train; conf = 0.8; reason = "Über 165 km/h & sehr ruhige Fahrt"
            } else if avgKmh >= 12 && avgKmh <= 27 && maxKmh <= 32 && !automotive && steady && vib > 0.05
                        && cadence < 1.5 && stepCadence < 0.5 && !(sys?.cycling ?? false) {
                guess = .eScooter; conf = 0.6; reason = "Konstant ~20 km/h ohne Tretrhythmus"
            } else if avgKmh >= 8 && avgKmh <= 40 && !automotive && cadence >= 1.0 {
                guess = .cycling; conf = 0.6; reason = "Radtempo mit Tretrhythmus"
            } else if avgKmh > 8 {
                var trainScore = 0.0
                if smooth { trainScore += 1.2 }
                if vib < 0.035 { trainScore += 0.8 }
                if badGPS { trainScore += 0.8 }
                if steady && avgKmh > 50 { trainScore += 0.6 }
                if maxKmh > 140 { trainScore += 0.8 }
                if nearStation { trainScore += 0.6 }
                // Lange, sanfte Beschleunigung ohne Stop-and-go
                if avgKmh > 60 && speedStd < 3 && vib < 0.08 { trainScore += 0.4 }
                var carScore = 0.0
                if automotive { carScore += 0.6 }
                if vib > 0.06 { carScore += 1.0 }
                if speedStd > 2.5 { carScore += 0.8 }
                if vib > 0.1 { carScore += 0.4 }
                if !badGPS { carScore += 0.3 }
                if trainScore > carScore {
                    guess = .train
                    conf = min(0.9, 0.5 + (trainScore - carScore) * 0.15)
                    reason = "Laufruhig, gleichmäßig – typisch Schiene"
                } else {
                    guess = .car
                    conf = min(0.9, 0.5 + (carScore - trainScore) * 0.15)
                    reason = "Fahrzeug mit Straßenvibration"
                }
            } else {
                guess = .walking; conf = 0.4; reason = "Langsame Bewegung"
            }
        }

        // Gewichtete Abstimmung mit Hysterese: ein Wechsel braucht deutlich mehr Evidenz
        // als das Beibehalten (verhindert z. B. „Stillstand“ an jeder roten Ampel).
        history.append((guess, conf))
        if history.count > 10 { history.removeFirst(history.count - 10) }
        var scores: [ActivityType: Double] = [:]
        for (i, h) in history.enumerated() {
            let recency = 0.6 + 0.4 * Double(i + 1) / Double(history.count)
            scores[h.activity, default: 0] += h.confidence * recency
        }
        let total = max(scores.values.reduce(0, +), 0.001)
        let best = scores.max { $0.value < $1.value }!
        let currentScore = scores[current.activity] ?? 0

        let switchFactor: Double
        switch current.activity {
        case .stationary, .unknown: switchFactor = 1.0          // schnell losfahren
        case _ where best.key == .stationary: switchFactor = 2.0 // kurze Stopps ignorieren
        default: switchFactor = 1.35
        }
        let winner = (best.key == current.activity || best.value > currentScore * switchFactor)
            ? best.key : current.activity
        let share = (scores[winner] ?? 0) / total
        current = Result(activity: winner,
                         confidence: min(0.99, winner == guess ? share * 0.6 + conf * 0.4 : share * 0.85),
                         reason: winner == guess ? reason : current.reason)
        return current
    }
}
