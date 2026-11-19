import Foundation
import CoreMotion
import Observation

/// Bewegungssensoren: Aktivitätserkennung von iOS, Vibrationsanalyse und Barometer.
@Observable
final class MotionService {
    @ObservationIgnored private let activityManager = CMMotionActivityManager()
    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private let altimeter = CMAltimeter()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let queue = OperationQueue()

    // iOS-Aktivitätserkennung
    var systemActivity: CMMotionActivity?

    /// Standardabweichung des Beschleunigungsbetrags (g) – Maß für Erschütterung.
    var vibration: Double = 0
    /// Dominante „Schrittfrequenz“ in Hz (Zero-Crossing-Schätzung).
    var cadence: Double = 0
    /// Aktuelle Längs-/Gesamtbeschleunigung in g (ohne Schwerkraft).
    var gForce: Double = 0
    var peakGForce: Double = 0

    // Schrittzähler (funktioniert auch in der Hosentasche und ohne GPS)
    /// Geschwindigkeit aus der aktuellen Schritt-Pace in m/s.
    var pedometerSpeed: Double = 0
    /// Schritte pro Sekunde.
    var stepCadence: Double = 0
    var steps: Int = 0
    /// Schrittbasierte Strecke seit App-Start in m.
    var pedometerDistance: Double = 0
    var pedometerUpdated: Date?
    var pedometerAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    // Barometer
    var pressureKPa: Double?
    var relativeAltitude: Double = 0
    var barometerAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    @ObservationIgnored private var samples: [Double] = []
    @ObservationIgnored private var sampleTimes: [TimeInterval] = []

    init() {
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] act in
                guard let act else { return }
                self?.systemActivity = act
            }
        }

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 25.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                let a = motion.userAcceleration
                let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
                self.ingest(mag, at: motion.timestamp)
            }
        } else if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 25.0
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                let a = data.acceleration
                let mag = abs(sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 1.0)
                self.ingest(mag, at: data.timestamp)
            }
        }

        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: .now) { [weak self] data, _ in
                guard let data else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.steps = data.numberOfSteps.intValue
                    if let d = data.distance?.doubleValue { self.pedometerDistance = d }
                    if let pace = data.currentPace?.doubleValue, pace > 0 {
                        self.pedometerSpeed = 1 / pace
                    }
                    self.stepCadence = data.currentCadence?.doubleValue ?? 0
                    self.pedometerUpdated = .now
                }
            }
        }

        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                self.pressureKPa = data.pressure.doubleValue
                self.relativeAltitude = data.relativeAltitude.doubleValue
            }
        }
    }

    func resetPeak() { peakGForce = 0 }

    /// Aktuelle Schritt-Geschwindigkeit, falls frisch (sonst 0 – man steht).
    var freshPedometerSpeed: Double {
        guard let u = pedometerUpdated, Date.now.timeIntervalSince(u) < 6 else { return 0 }
        return pedometerSpeed
    }

    /// Barometer-Nullpunkt neu setzen (z. B. „Ich bin im Erdgeschoss“).
    func recalibrateFloor() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.stopRelativeAltitudeUpdates()
        relativeAltitude = 0
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.pressureKPa = data.pressure.doubleValue
            self.relativeAltitude = data.relativeAltitude.doubleValue
        }
    }

    private func ingest(_ magnitude: Double, at time: TimeInterval) {
        gForce = gForce * 0.8 + magnitude * 0.2
        peakGForce = max(peakGForce, gForce)

        samples.append(magnitude)
        sampleTimes.append(time)
        // 3-Sekunden-Fenster
        while let first = sampleTimes.first, time - first > 3 {
            sampleTimes.removeFirst()
            samples.removeFirst()
        }
        guard samples.count > 20 else { return }

        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)
        vibration = sqrt(variance)

        // Kadenz grob über Nulldurchgänge um den Mittelwert schätzen
        var crossings = 0
        for i in 1..<samples.count where (samples[i - 1] - mean) < 0 && (samples[i] - mean) >= 0 {
            crossings += 1
        }
        let span = (sampleTimes.last ?? time) - (sampleTimes.first ?? time)
        cadence = span > 0 ? Double(crossings) / span : 0
    }
}
