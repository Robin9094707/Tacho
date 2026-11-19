import Foundation
import CoreLocation
import Observation

/// Liefert GPS-Position, Geschwindigkeit, Kurs und Kompass.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?

    var authorization: CLAuthorizationStatus = .notDetermined
    var location: CLLocation?
    /// Geglättete Geschwindigkeit in m/s.
    var speed: Double = 0
    /// Rohwert vom GPS in m/s (−1 = ungültig).
    var rawSpeed: Double = -1
    var course: Double = -1
    var heading: Double = -1
    var altitude: Double = 0
    var horizontalAccuracy: Double = -1
    var lastFix: Date?
    /// Stockwerk aus Indoor-Karten (Flughäfen, Einkaufszentren …), falls Apple es liefert.
    var floorLevel: Int?
    var verticalAccuracy: Double = -1

    /// Ein Eintrag pro empfangenem Standort – Grundlage der Innen/Außen-Erkennung.
    struct FixInfo {
        let date: Date
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        /// Satellitenortung liefert Geschwindigkeit & Kurs; WLAN-/Funkzellenortung nicht.
        let hasDoppler: Bool
    }
    @ObservationIgnored private(set) var fixLog: [FixInfo] = []

    /// Anteil der Fixes der letzten 20 s mit gültiger Doppler-Geschwindigkeit (≈ echtes GNSS).
    var gnssRatio: Double? {
        let recent = fixLog.filter { Date.now.timeIntervalSince($0.date) < 20 }
        guard recent.count >= 3 else { return nil }
        return Double(recent.filter(\.hasDoppler).count) / Double(recent.count)
    }

    /// Fixes pro Sekunde in den letzten 10 s (GNSS liefert stabil ≈ 1 Hz).
    var fixRate: Double {
        Double(fixLog.filter { Date.now.timeIntervalSince($0.date) < 10 }.count) / 10
    }

    var medianVerticalAccuracy: Double? {
        let v = fixLog.filter { Date.now.timeIntervalSince($0.date) < 20 }.map(\.verticalAccuracy).sorted()
        return v.isEmpty ? nil : v[v.count / 2]
    }

    /// Wird für jeden neuen, brauchbaren Standort aufgerufen.
    @ObservationIgnored var onLocation: ((CLLocation, Double) -> Void)?

    @ObservationIgnored private var previous: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 2
        authorization = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func requestAlways() { manager.requestAlwaysAuthorization() }

    func setBackgroundRecording(_ enabled: Bool) {
        if enabled {
            if backgroundSession == nil { backgroundSession = CLBackgroundActivitySession() }
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        } else {
            backgroundSession?.invalidate()
            backgroundSession = nil
            manager.allowsBackgroundLocationUpdates = false
        }
    }

    // MARK: - Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations { handle(loc) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        heading = h
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func handle(_ loc: CLLocation) {
        if abs(loc.timestamp.timeIntervalSinceNow) < 15 {
            fixLog.append(FixInfo(date: loc.timestamp,
                                  horizontalAccuracy: loc.horizontalAccuracy,
                                  verticalAccuracy: loc.verticalAccuracy,
                                  hasDoppler: loc.speedAccuracy >= 0 && loc.speed >= 0))
            fixLog.removeAll { Date.now.timeIntervalSince($0.date) > 30 }
            floorLevel = loc.floor?.level
            verticalAccuracy = loc.verticalAccuracy
        }
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else {
            horizontalAccuracy = loc.horizontalAccuracy
            return
        }
        // Veraltete Punkte ignorieren
        guard abs(loc.timestamp.timeIntervalSinceNow) < 15 else { return }

        var v = loc.speed
        if v < 0 || loc.speedAccuracy < 0 || loc.speedAccuracy > 8 {
            // Fallback: aus Strecke / Zeit ableiten
            if let prev = previous {
                let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
                if dt > 0.2 { v = loc.distance(from: prev) / dt } else { v = speed }
            } else { v = 0 }
        }
        if v < 0.25 { v = 0 } // GPS-Rauschen im Stand

        // Sanfte Glättung, reagiert aber schnell auf große Änderungen
        let alpha = abs(v - speed) > 3 ? 0.7 : 0.45
        speed = speed + alpha * (v - speed)
        if speed < 0.15 { speed = 0 }

        rawSpeed = loc.speed
        course = loc.course
        altitude = loc.altitude
        horizontalAccuracy = loc.horizontalAccuracy
        location = loc
        lastFix = loc.timestamp
        previous = loc
        onLocation?(loc, speed)
    }
}
