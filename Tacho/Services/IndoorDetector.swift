import Foundation

/// Innen/Außen-Erkennung durch Sensorfusion.
///
/// Drinnen liefert iOS oft WLAN-Positionen mit scheinbar guter Genauigkeit (±5–15 m),
/// daher reicht die Genauigkeit allein nicht. Ausgewertet werden deshalb:
/// – ob die Fixes echte Satelliten-Doppler-Geschwindigkeit enthalten (GNSS) oder nicht (WLAN/Funkzelle)
/// – Fix-Rate, horizontale & vertikale Genauigkeit, Alter des letzten Fixes
/// – Stockwerk-Angabe aus Apples Indoor-Karten
/// – Magnetfeld-Störungen durch Stahlbeton und Elektrik
/// – LiDAR/Kamera: erkannte Decke, Wände, Lichtstärke
/// Das Ergebnis wird mit Hysterese stabilisiert.
struct IndoorDetector {
    struct Input {
        var gnssRatio: Double?            // 0…1 Anteil der Fixes mit Doppler
        var fixRate: Double               // Hz
        var horizontalAccuracy: Double    // m, −1 = keiner
        var verticalAccuracy: Double?     // m (Median)
        var fixAge: TimeInterval?         // s
        var floorLevel: Int?
        var magneticField: Double?        // µT
        var magneticVariance: Double      // µT
        var moving: Bool
        var inVehicle: Bool
        var ceilingSeen: Bool
        var wallsSeen: Int
        var lightIntensity: Double?       // ARKit lm, ~1000 = neutral
    }

    struct Evidence: Identifiable, Equatable {
        let text: String
        let weight: Double               // >0 = drinnen, <0 = draußen
        var id: String { text }
    }

    struct Result: Equatable {
        var probability: Double = 0.5     // Wahrscheinlichkeit für „drinnen“
        var isIndoor = false
        var evidence: [Evidence] = []
    }

    private(set) var result = Result()
    private var smoothed = 0.0            // Logit, geglättet

    mutating func update(_ i: Input) -> Result {
        var ev: [Evidence] = []
        func add(_ w: Double, _ t: String) { ev.append(Evidence(text: t, weight: w)) }

        // 1) Satellitenqualität
        if let age = i.fixAge {
            if age > 12 { add(2.2, "Seit \(Int(age)) s kein Standort") }
            else if age > 5 { add(1.2, "Standort-Updates stocken") }
        } else {
            add(1.5, "Noch kein Standort")
        }
        if let r = i.gnssRatio {
            if r < 0.15 { add(2.4, "Keine Satelliten-Geschwindigkeit (WLAN-Ortung)") }
            else if r < 0.5 { add(1.0, "Satellitensignal lückenhaft") }
            else if r > 0.9 { add(-1.6, "Durchgehender Satellitenempfang") }
        }
        if i.fixAge.map({ $0 < 5 }) == true {
            if i.fixRate < 0.35 { add(0.9, "Sehr wenige Standort-Updates") }
            else if i.fixRate > 0.8 { add(-0.5, "Gleichmäßige 1-Hz-Updates") }
        }
        if i.horizontalAccuracy > 0 {
            if i.horizontalAccuracy > 40 { add(1.4, String(format: "Ungenau (± %.0f m)", i.horizontalAccuracy)) }
            else if i.horizontalAccuracy > 18 { add(0.6, String(format: "Mäßig genau (± %.0f m)", i.horizontalAccuracy)) }
            else if i.horizontalAccuracy <= 6 { add(-1.0, String(format: "Sehr genau (± %.0f m)", i.horizontalAccuracy)) }
        }
        if let v = i.verticalAccuracy {
            if v < 0 || v > 25 { add(0.8, "Keine verlässliche GPS-Höhe") }
            else if v < 8 { add(-0.7, "Präzise GPS-Höhe") }
        }

        // 2) Apple Indoor-Karten
        if let f = i.floorLevel { add(3.0, "Indoor-Karte meldet Etage \(f)") }

        // 3) Magnetfeld: Stahlbeton & Leitungen verzerren das Erdfeld
        if let m = i.magneticField, !i.inVehicle {
            let deviation = abs(m - 48)
            if deviation > 18 { add(0.9, String(format: "Magnetfeld gestört (%.0f µT)", m)) }
            else if deviation < 6 && i.magneticVariance < 1.5 { add(-0.4, "Ungestörtes Erdmagnetfeld") }
            if i.magneticVariance > 4 && !i.moving { add(0.5, "Magnetfeld schwankt im Stand") }
        }

        // 4) Kamera & LiDAR
        if i.ceilingSeen { add(3.0, "LiDAR: Decke erkannt") }
        if i.wallsSeen >= 2 { add(1.2, "LiDAR: \(i.wallsSeen) Wände erkannt") }
        if let lux = i.lightIntensity {
            if lux > 2500 { add(-1.0, "Kamera: Tageslicht-Helligkeit") }
            else if lux < 600 { add(0.4, "Kamera: gedämpftes Licht") }
        }

        // In Fahrzeugen ist schwaches GPS normal – nicht als „Gebäude“ werten
        let vehicleDamp = i.inVehicle ? 0.5 : 1.0
        let logit = ev.reduce(0) { $0 + $1.weight } * vehicleDamp - 0.2
        smoothed = smoothed * 0.6 + logit * 0.4
        let p = 1 / (1 + exp(-smoothed))

        var isIndoor = result.isIndoor
        if p > 0.65 { isIndoor = true }
        if p < 0.35 { isIndoor = false }

        result = Result(probability: p,
                        isIndoor: isIndoor,
                        evidence: ev.sorted { abs($0.weight) > abs($1.weight) })
        return result
    }
}
