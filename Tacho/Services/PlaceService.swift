import Foundation
import CoreLocation
import MapKit
import Observation

/// Erkennt Orte (Straße, Stadt, Points of Interest wie Bahnhöfe) und die
/// Umgebung: freier Himmel, Stadt­schlucht, Innenraum oder Tunnel.
@Observable
final class PlaceService {
    enum Surroundings: String {
        case openSky, partial, indoor, noSignal

        var title: String {
            switch self {
            case .openSky: "Freier Himmel"
            case .partial: "Teilweise abgeschirmt"
            case .indoor: "Innenraum / Tunnel"
            case .noSignal: "Kein GPS-Signal"
            }
        }

        var symbol: String {
            switch self {
            case .openSky: "sun.max.fill"
            case .partial: "building.2.fill"
            case .indoor: "house.fill"
            case .noSignal: "antenna.radiowaves.left.and.right.slash"
            }
        }
    }

    var street: String?
    var locality: String?
    var pointOfInterest: String?
    /// Name eines Bahnhofs / einer Station im Umkreis von ~350 m.
    var nearestStation: String?
    var surroundings: Surroundings = .noSignal
    var signalQuality: Double = 0   // 0…1

    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var lastGeocoded: CLLocation?
    @ObservationIgnored private var lastGeocodeDate = Date.distantPast
    @ObservationIgnored private var accuracyHistory: [Double] = []
    @ObservationIgnored private var lastStationLookup: CLLocation?
    @ObservationIgnored private var lastStationDate = Date.distantPast

    var shortDescription: String {
        if let poi = pointOfInterest { return poi }
        switch (street, locality) {
        case let (s?, l?): return "\(s), \(l)"
        case let (s?, nil): return s
        case let (nil, l?): return l
        default: return "Ort wird ermittelt …"
        }
    }

    /// Regelmäßig mit dem letzten GPS-Fix aufrufen.
    func update(location: CLLocation?, lastFix: Date?, now: Date = .now) {
        guard let location, let lastFix else {
            surroundings = .noSignal
            signalQuality = 0
            return
        }
        let age = now.timeIntervalSince(lastFix)
        let acc = location.horizontalAccuracy
        accuracyHistory.append(acc)
        if accuracyHistory.count > 10 { accuracyHistory.removeFirst() }
        let avgAcc = accuracyHistory.reduce(0, +) / Double(accuracyHistory.count)

        if age > 12 {
            surroundings = .noSignal
        } else if age > 5 || avgAcc > 35 {
            surroundings = .indoor
        } else if avgAcc > 12 {
            surroundings = .partial
        } else {
            surroundings = .openSky
        }
        let freshness = max(0, 1 - age / 12)
        signalQuality = max(0, min(1, (1 - (avgAcc - 3) / 60))) * freshness

        geocodeIfNeeded(location)
        lookupStationIfNeeded(location)
    }

    /// Sucht Bahnhöfe in der Nähe – ein Hinweis für die Zug-Erkennung.
    private func lookupStationIfNeeded(_ location: CLLocation) {
        let moved = lastStationLookup.map { location.distance(from: $0) } ?? .infinity
        guard moved > 400 || Date.now.timeIntervalSince(lastStationDate) > 120,
              Date.now.timeIntervalSince(lastStationDate) > 20 else { return }
        lastStationLookup = location
        lastStationDate = .now
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 350)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        Task { @MainActor in
            let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            let keywords = ["bahnhof", "hbf", "station", "s-bahn", "u-bahn", "gleis", "railway"]
            let prefixes = ["s ", "u ", "s+u "]   // z. B. „S Ostkreuz“, „U Alexanderplatz“
            let station = items.first { item in
                let n = (item.name ?? "").lowercased()
                return keywords.contains { n.contains($0) } || prefixes.contains { n.hasPrefix($0) }
            }
            self.nearestStation = station?.name
        }
    }

    private func geocodeIfNeeded(_ location: CLLocation) {
        let moved = lastGeocoded.map { location.distance(from: $0) } ?? .infinity
        guard moved > 150 || Date.now.timeIntervalSince(lastGeocodeDate) > 90 else { return }
        guard Date.now.timeIntervalSince(lastGeocodeDate) > 8, !geocoder.isGeocoding else { return }
        lastGeocoded = location
        lastGeocodeDate = .now
        Task { @MainActor in
            if let pm = try? await self.geocoder.reverseGeocodeLocation(location).first {
                self.street = pm.thoroughfare
                self.locality = pm.locality ?? pm.subAdministrativeArea
                self.pointOfInterest = pm.areasOfInterest?.first
            }
        }
    }

    /// Einmaliges Nachschlagen eines Ortsnamens (für Start/Ziel einer Fahrt).
    static func placeName(for location: CLLocation) async -> String? {
        let g = CLGeocoder()
        guard let pm = try? await g.reverseGeocodeLocation(location).first else { return nil }
        if let poi = pm.areasOfInterest?.first { return poi }
        if let s = pm.thoroughfare, let l = pm.locality { return "\(s), \(l)" }
        return pm.locality ?? pm.name
    }
}
