import Foundation
import CoreLocation
import Observation

/// Bestimmt das Stockwerk aus der Barometer-Höhe relativ zur Straßenhöhe.
///
/// Die Straßenhöhe („Erdgeschoss-Referenz“) wird automatisch gelernt, sobald man
/// draußen ist, und pro Ort gespeichert – betritt man später dasselbe Gebäude,
/// stimmt die Etage sofort. Alternativ: Apples Indoor-Karten oder manuelle Angabe.
@Observable
final class FloorEstimator {
    enum Source: Equatable {
        case none, learnedOutdoors, savedPlace, manual, indoorMap

        var title: String {
            switch self {
            case .none: "Unbekannt"
            case .learnedOutdoors: "Draußen gelernt"
            case .savedPlace: "Gespeicherter Ort"
            case .manual: "Manuell festgelegt"
            case .indoorMap: "Apple Indoor-Karte"
            }
        }
    }

    private struct Reference: Codable {
        var lat: Double
        var lon: Double
        var groundAltitude: Double   // barometrische Höhe auf Straßenniveau
        var date: Date
        var absolute: Bool           // absolute Barometerhöhe (sonst relativ, nur Sitzung)
    }

    var floor: Int?
    /// Höhe über Straßenniveau in m.
    var heightAboveGround: Double?
    var source: Source = .none
    var floorHeight: Double = 3.0

    @ObservationIgnored private var groundAltitude: Double?
    @ObservationIgnored private var groundIsAbsolute = false
    /// Wo die Referenz gilt – Gelände ist nicht überall gleich hoch.
    @ObservationIgnored private var groundLocation: CLLocation?
    @ObservationIgnored private var lastRemember = Date.distantPast
    @ObservationIgnored private var outdoorSamples: [Double] = []
    @ObservationIgnored private var saved: [Reference] = []
    @ObservationIgnored private let storeKey = "floorReferences"

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let refs = try? JSONDecoder().decode([Reference].self, from: data) {
            saved = refs
        }
    }

    /// Jede Sekunde aufrufen.
    func update(baroAltitude: Double?,
                baroIsAbsolute: Bool,
                location: CLLocation?,
                confidentlyOutdoors: Bool,
                isIndoor: Bool,
                indoorMapFloor: Int?) {
        // Apples Indoor-Karte hat Vorrang, wenn vorhanden
        if let f = indoorMapFloor {
            floor = f
            source = .indoorMap
            if let b = baroAltitude {
                groundAltitude = b - Double(f) * floorHeight
                groundIsAbsolute = baroIsAbsolute
                groundLocation = location
            }
            heightAboveGround = Double(f) * floorHeight
            return
        }

        guard let b = baroAltitude else { floor = nil; heightAboveGround = nil; return }

        // Absolute und relative Höhen nicht mischen
        if groundAltitude != nil && groundIsAbsolute != baroIsAbsolute { groundAltitude = nil; source = .none }

        if confidentlyOutdoors {
            // Draußen = Straßenniveau → Referenz lernen (geglättet über ~10 s)
            outdoorSamples.append(b)
            if outdoorSamples.count > 10 { outdoorSamples.removeFirst() }
            if outdoorSamples.count >= 5 {
                let sorted = outdoorSamples.sorted()
                groundAltitude = sorted[sorted.count / 2]
                groundIsAbsolute = baroIsAbsolute
                source = .learnedOutdoors
                groundLocation = location
                if baroIsAbsolute, let loc = location, Date.now.timeIntervalSince(lastRemember) > 30 {
                    lastRemember = .now
                    remember(loc, ground: groundAltitude!)
                }
            }
        } else {
            outdoorSamples.removeAll()
        }

        // Referenz von einem weit entfernten Ort taugt nicht (anderes Geländeniveau)
        if source != .manual, let gl = groundLocation, let loc = location,
           loc.distance(from: gl) > 350, loc.horizontalAccuracy < 100 {
            groundAltitude = nil
            groundLocation = nil
            source = .none
        }

        // Keine Referenz? Gespeicherten Ort in der Nähe suchen
        if groundAltitude == nil, baroIsAbsolute, let loc = location, let ref = nearbyReference(loc) {
            groundAltitude = ref.groundAltitude
            groundIsAbsolute = true
            groundLocation = CLLocation(latitude: ref.lat, longitude: ref.lon)
            source = .savedPlace
        }

        guard let ground = groundAltitude else {
            floor = nil
            heightAboveGround = nil
            return
        }

        let h = b - ground
        heightAboveGround = h
        if !isIndoor && confidentlyOutdoors {
            floor = 0
            return
        }
        // Rundung mit Hysterese, damit die Anzeige an der Grenze nicht flackert
        let raw = h / floorHeight
        if let current = floor {
            if abs(raw - Double(current)) > 0.65 { floor = Int(raw.rounded()) }
        } else {
            floor = Int(raw.rounded())
        }
    }

    /// „Ich bin gerade auf Etage n.“
    func setCurrentFloor(_ n: Int, baroAltitude: Double?, baroIsAbsolute: Bool, location: CLLocation?) {
        guard let b = baroAltitude else { return }
        let ground = b - Double(n) * floorHeight
        groundAltitude = ground
        groundIsAbsolute = baroIsAbsolute
        floor = n
        heightAboveGround = Double(n) * floorHeight
        source = .manual
        groundLocation = location
        if baroIsAbsolute, let loc = location { remember(loc, ground: ground) }
    }

    func forgetSavedPlaces() {
        saved = []
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    var savedPlaceCount: Int { saved.count }

    // MARK: - Speicher

    private func nearbyReference(_ loc: CLLocation) -> Reference? {
        // Wetterbedingte Luftdruckänderungen verschieben die Höhe; Referenzen gelten max. 6 h
        // (bzw. 2 h, wenn der Ort weiter weg ist).
        saved
            .filter { Date.now.timeIntervalSince($0.date) < 6 * 3600 }
            .map { ($0, loc.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon))) }
            .filter { $0.1 < 250 }
            .min { $0.1 < $1.1 }?.0
    }

    private func remember(_ loc: CLLocation, ground: Double) {
        saved.removeAll { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: loc) < 120 }
        saved.append(Reference(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                               groundAltitude: ground, date: .now, absolute: true))
        saved = Array(saved.suffix(60))
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
