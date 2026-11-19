import Foundation
import CoreMotion
import Observation

/// Alle Bewegungssensoren in einem Strom:
/// Beschleunigung, Gyroskop, Magnetometer, Barometer (relativ + absolut),
/// Schrittzähler inkl. Stockwerkzählung und die iOS-Aktivitätserkennung.
@Observable
final class MotionService {
    @ObservationIgnored private let activityManager = CMMotionActivityManager()
    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private let altimeter = CMAltimeter()
    @ObservationIgnored private let pedometer = CMPedometer()

    // iOS-Aktivitätserkennung
    var systemActivity: CMMotionActivity?

    // Beschleunigung
    /// Standardabweichung des Beschleunigungsbetrags (g) – Maß für Erschütterung.
    var vibration: Double = 0
    /// Dominante Rhythmus-Frequenz in Hz (Zero-Crossing-Schätzung).
    var cadence: Double = 0
    var gForce: Double = 0
    var peakGForce: Double = 0

    // Gyroskop
    /// Drehrate um die senkrechte Achse (rad/s, geglättet) – Kurvenfahrt.
    var yawRate: Double = 0
    /// Höchste Gier-Rate der letzten 30 s (rad/s) – Autos biegen ab, Züge kaum.
    var maxYawRate30s: Double = 0

    // Magnetometer
    /// Kalibrierte Feldstärke in µT (Erdfeld ≈ 48 µT in Mitteleuropa).
    var magneticField: Double?
    /// Schwankung der Feldstärke (µT, Std.-Abw. über 3 s).
    var magneticVariance: Double = 0
    var magnetometerCalibrated = false

    // Schrittzähler
    var pedometerSpeed: Double = 0
    /// Schritte pro Sekunde.
    var stepCadence: Double = 0
    var steps: Int = 0
    var pedometerDistance: Double = 0
    var pedometerUpdated: Date?
    var floorsAscended = 0
    var floorsDescended = 0
    var pedometerAvailable: Bool { CMPedometer.isStepCountingAvailable() }
    var floorCountingAvailable: Bool { CMPedometer.isFloorCountingAvailable() }

    // Barometer
    var pressureKPa: Double?
    var relativeAltitude: Double = 0
    /// Barometrische Höhe über NN (iPhone 12 und neuer).
    var absoluteAltitude: Double?
    var absoluteAltitudeAccuracy: Double?
    /// Vertikalgeschwindigkeit aus dem Barometer (m/s, + = aufwärts).
    var verticalSpeed: Double = 0
    var barometerAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }
    var absoluteAltitudeAvailable: Bool { CMAltimeter.isAbsoluteAltitudeAvailable() }

    /// Beste verfügbare barometrische Höhe: absolut, sonst relativ seit Start.
    var baroAltitude: Double? {
        if let a = absoluteAltitude { return a }
        return barometerAvailable && pressureKPa != nil ? relativeAltitude : nil
    }
    var baroIsAbsolute: Bool { absoluteAltitude != nil }

    @ObservationIgnored private var samples: [Double] = []
    @ObservationIgnored private var sampleTimes: [TimeInterval] = []
    @ObservationIgnored private var magSamples: [Double] = []
    @ObservationIgnored private var yawPeaks: [(TimeInterval, Double)] = []
    @ObservationIgnored private var altSamples: [(Date, Double)] = []
    @ObservationIgnored private var highRate = true
    @ObservationIgnored private var lastYawMax: TimeInterval = 0

    func start() {
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] act in
                guard let act else { return }
                self?.systemActivity = act
            }
        }

        startDeviceMotion()

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
                    self.floorsAscended = data.floorsAscended?.intValue ?? 0
                    self.floorsDescended = data.floorsDescended?.intValue ?? 0
                    self.pedometerUpdated = .now
                }
            }
        }

        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                self.pressureKPa = data.pressure.doubleValue
                self.relativeAltitude = data.relativeAltitude.doubleValue
                if self.absoluteAltitude == nil { self.trackVertical(self.relativeAltitude) }
            }
        }
        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                self.absoluteAltitude = data.altitude
                self.absoluteAltitudeAccuracy = data.accuracy
                self.trackVertical(data.altitude)
            }
        }
    }

    private func startDeviceMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            if motionManager.isAccelerometerAvailable {
                motionManager.accelerometerUpdateInterval = 1.0 / 25.0
                motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                    guard let self, let data else { return }
                    let a = data.acceleration
                    self.ingestAcceleration(abs(sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 1.0), at: data.timestamp)
                }
            }
            return
        }
        motionManager.deviceMotionUpdateInterval = highRate ? 1.0 / 25.0 : 1.0 / 10.0
        // Dieser Referenzrahmen liefert zusätzlich ein kalibriertes Magnetfeld.
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xArbitraryCorrectedZVertical)
            ? .xArbitraryCorrectedZVertical : .xArbitraryZVertical
        motionManager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.ingest(motion)
        }
    }

    /// Spart Energie: Im Stillstand reichen 10 Hz statt 25 Hz.
    func setHighRate(_ high: Bool) {
        guard high != highRate, motionManager.isDeviceMotionActive else { return }
        highRate = high
        motionManager.deviceMotionUpdateInterval = high ? 1.0 / 25.0 : 1.0 / 10.0
    }

    func resetPeak() { peakGForce = 0 }

    var freshPedometerSpeed: Double {
        guard let u = pedometerUpdated, Date.now.timeIntervalSince(u) < 6 else { return 0 }
        return pedometerSpeed
    }

    /// Steigt bzw. sinkt man gerade (Treppe, Aufzug, Rolltreppe)?
    enum VerticalMotion: Equatable {
        case none, stairsUp, stairsDown, elevatorUp, elevatorDown

        var title: String {
            switch self {
            case .none: "Keine Höhenänderung"
            case .stairsUp: "Treppe hoch"
            case .stairsDown: "Treppe runter"
            case .elevatorUp: "Aufzug/Rolltreppe hoch"
            case .elevatorDown: "Aufzug/Rolltreppe runter"
            }
        }

        var symbol: String {
            switch self {
            case .none: "equal.circle"
            case .stairsUp: "figure.stairs"
            case .stairsDown: "figure.stairs"
            case .elevatorUp: "arrow.up.square.fill"
            case .elevatorDown: "arrow.down.square.fill"
            }
        }
    }

    var verticalMotion: VerticalMotion {
        let stepping = (pedometerUpdated.map { Date.now.timeIntervalSince($0) < 4 } ?? false) && stepCadence > 0.6
        if verticalSpeed > 0.18 { return stepping ? .stairsUp : (verticalSpeed > 0.4 ? .elevatorUp : .none) }
        if verticalSpeed < -0.18 { return stepping ? .stairsDown : (verticalSpeed < -0.4 ? .elevatorDown : .none) }
        return .none
    }

    // MARK: - Verarbeitung

    private func ingest(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration
        ingestAcceleration(sqrt(a.x * a.x + a.y * a.y + a.z * a.z), at: motion.timestamp)

        // Gier-Rate = Drehrate projiziert auf die Schwerkraftrichtung
        let g = motion.gravity
        let gLen = max(sqrt(g.x * g.x + g.y * g.y + g.z * g.z), 0.001)
        let r = motion.rotationRate
        let yaw = abs((r.x * g.x + r.y * g.y + r.z * g.z) / gLen)
        yawRate = yawRate * 0.9 + yaw * 0.1
        let t = motion.timestamp
        yawPeaks.append((t, yawRate))
        if yawPeaks.count > 1, let first = yawPeaks.first, t - first.0 > 30 {
            yawPeaks.removeAll { t - $0.0 > 30 }
        }
        // Nur jede ~Sekunde das Maximum neu berechnen
        if t - lastYawMax > 1 {
            lastYawMax = t
            maxYawRate30s = yawPeaks.map(\.1).max() ?? 0
        }

        // Magnetfeld
        let field = motion.magneticField
        if field.accuracy != .uncalibrated {
            magnetometerCalibrated = true
            let f = field.field
            let m = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
            magneticField = m
            magSamples.append(m)
            if magSamples.count > 75 { magSamples.removeFirst(magSamples.count - 75) }
            let mean = magSamples.reduce(0, +) / Double(magSamples.count)
            let v = magSamples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(magSamples.count)
            magneticVariance = sqrt(v)
        }
    }

    private func ingestAcceleration(_ magnitude: Double, at time: TimeInterval) {
        gForce = gForce * 0.8 + magnitude * 0.2
        peakGForce = max(peakGForce, gForce)

        samples.append(magnitude)
        sampleTimes.append(time)
        while let first = sampleTimes.first, time - first > 3 {
            sampleTimes.removeFirst()
            samples.removeFirst()
        }
        guard samples.count > 20 else { return }

        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)
        vibration = sqrt(variance)

        var crossings = 0
        for i in 1..<samples.count where (samples[i - 1] - mean) < 0 && (samples[i] - mean) >= 0 {
            crossings += 1
        }
        let span = (sampleTimes.last ?? time) - (sampleTimes.first ?? time)
        cadence = span > 0 ? Double(crossings) / span : 0
    }

    private func trackVertical(_ altitude: Double) {
        let now = Date.now
        altSamples.append((now, altitude))
        altSamples.removeAll { now.timeIntervalSince($0.0) > 4 }
        guard let first = altSamples.first, altSamples.count > 2 else { return }
        let dt = now.timeIntervalSince(first.0)
        guard dt > 1.5 else { return }
        let v = (altitude - first.1) / dt
        verticalSpeed = verticalSpeed * 0.5 + v * 0.5
    }
}
