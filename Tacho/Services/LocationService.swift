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
