import Foundation
import CoreLocation
import Observation
import SwiftData
import UIKit

/// Zentrale Steuerung: verbindet Sensoren, Erkennung, Aufzeichnung und Sprintmessung.
@Observable
final class TachoEngine {
    enum RecordingState { case idle, recording, paused }

    let location = LocationService()
    let motion = MotionService()
    let place = PlaceService()

    @ObservationIgnored private var classifier = ActivityClassifier()
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var lastClassify = Date.distantPast

    // Erkennung
    var detected: ActivityClassifier.Result = .init(activity: .stationary, confidence: 0.3, reason: "Warte auf GPS …")
    /// Manuelle Auswahl überschreibt die Automatik.
    var manualActivity: ActivityType?
    var activity: ActivityType { manualActivity ?? detected.activity }

    // Sitzungswerte (seit App-Start / Reset)
    var sessionMax: Double = 0
    var speedHistory: [Double] = []          // letzte ~120 s, m/s

    // Aufzeichnung
    var state: RecordingState = .idle
    var points: [TrackPoint] = []
    var distance: Double = 0
    var maxSpeed: Double = 0
    var movingTime: TimeInterval = 0
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    var startDate: Date?
    var elapsed: TimeInterval = 0
    var autoPaused = false
    @ObservationIgnored private var lastRecorded: CLLocation?
    @ObservationIgnored private var lastAltitude: Double?
    @ObservationIgnored private var pausedAccum: TimeInterval = 0
    @ObservationIgnored private var pauseStart: Date?
    @ObservationIgnored private var lastMovingTick: Date?

    // Sprint / Beschleunigungsmessung
    enum SprintPhase: Equatable { case off, armed, running(start: Date), done(TimeInterval) }
    var sprintPhase: SprintPhase = .off
    var sprintTargetKmh: Double = 100
    var sprintDistance: Double = 0
    var sprintLive: TimeInterval = 0
    @ObservationIgnored private var sprintLast: CLLocation?
    @ObservationIgnored var onSprintFinished: ((TimeInterval, Double) -> Void)?

    // Einstellungen (werden aus den Views gespiegelt)
    var autoPauseEnabled = true

    var speed: Double { location.speed }
    var isRecording: Bool { state != .idle }

    var floor: Int { Int((motion.relativeAltitude / 3.2).rounded()) }

    init() {
        location.onLocation = { [weak self] loc, v in self?.handle(loc, speed: v) }
    }

    func start() {
        location.start()
        motion.start()
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.onTick()
        }
    }

    func resetSession() {
        sessionMax = 0
        motion.resetPeak()
    }

    // MARK: - Aufzeichnung

    func startRecording() {
        points = []
        distance = 0; maxSpeed = 0; movingTime = 0
        elevationGain = 0; elevationLoss = 0
        startDate = .now; elapsed = 0
        pausedAccum = 0; pauseStart = nil
        lastRecorded = nil; lastAltitude = nil
        autoPaused = false
        state = .recording
        location.setBackgroundRecording(true)
    }

    func pauseRecording() {
        guard state == .recording else { return }
        state = .paused
        pauseStart = .now
    }

    func resumeRecording() {
        guard state == .paused else { return }
        if let p = pauseStart { pausedAccum += Date.now.timeIntervalSince(p) }
        pauseStart = nil
        lastRecorded = nil
        state = .recording
    }

    /// Beendet die Aufzeichnung und speichert die Fahrt.
    @discardableResult
    func stopRecording(context: ModelContext) -> Trip? {
        defer {
            state = .idle
            location.setBackgroundRecording(false)
        }
        guard let start = startDate, points.count >= 2 else { return nil }
        let breakdown = Dictionary(grouping: points, by: \.activity)
            .filter { $0.key != .stationary && $0.key != .unknown }
            .mapValues(\.count)
        let main = breakdown.max { $0.value < $1.value }?.key ?? activity
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE HH:mm"
        let trip = Trip(name: "\(main.title) · \(formatter.string(from: start))",
                        startDate: start,
                        endDate: .now,
                        distance: distance,
                        movingTime: movingTime,
                        maxSpeed: maxSpeed,
                        elevationGain: elevationGain,
                        elevationLoss: elevationLoss,
                        activity: main,
                        points: points)
        context.insert(trip)
        try? context.save()

        let first = points.first!.location
        let last = points.last!.location
        Task { @MainActor in
            trip.startPlace = await PlaceService.placeName(for: first)
            trip.endPlace = await PlaceService.placeName(for: last)
            try? context.save()
        }
        return trip
    }

    func discardRecording() {
        state = .idle
        points = []
        location.setBackgroundRecording(false)
    }

    // MARK: - Sprint

    func armSprint(target: Double) {
        sprintTargetKmh = target
        sprintDistance = 0
        sprintLive = 0
        sprintLast = nil
        sprintPhase = .armed
    }

    func cancelSprint() { sprintPhase = .off }

    // MARK: - Intern

    private func onTick() {
        place.update(location: location.location, lastFix: location.lastFix)

        // Wenn keine GPS-Updates mehr kommen (Tunnel), Geschwindigkeit langsam abklingen lassen
        if let fix = location.lastFix, Date.now.timeIntervalSince(fix) > 4 {
            classify(speed: location.speed)
        }

        speedHistory.append(location.speed)
        if speedHistory.count > 120 { speedHistory.removeFirst(speedHistory.count - 120) }

        if let start = startDate, state != .idle {
            let pausedNow = pauseStart.map { Date.now.timeIntervalSince($0) } ?? 0
            elapsed = Date.now.timeIntervalSince(start) - pausedAccum - pausedNow
        }

        if case .running(let s) = sprintPhase {
            sprintLive = Date.now.timeIntervalSince(s)
            if sprintLive > 120 { sprintPhase = .off }
        }
    }

    private func classify(speed: Double) {
        guard Date.now.timeIntervalSince(lastClassify) > 0.9 else { return }
        lastClassify = .now
        detected = classifier.update(speed: speed,
                                     accuracy: location.horizontalAccuracy,
                                     altitude: location.altitude,
                                     vibration: motion.vibration,
                                     cadence: motion.cadence,
                                     system: motion.systemActivity)
    }

    private func handle(_ loc: CLLocation, speed v: Double) {
        sessionMax = max(sessionMax, v)
        classify(speed: v)
        handleSprint(loc, speed: v)

        guard state == .recording else { return }

        let moving = v > 0.6
        if autoPauseEnabled {
            autoPaused = !moving
        } else {
            autoPaused = false
        }

        // Bewegungszeit
        if let lm = lastMovingTick {
            let dt = loc.timestamp.timeIntervalSince(lm)
            if dt > 0, dt < 10, moving || !autoPauseEnabled { movingTime += dt }
        }
        lastMovingTick = loc.timestamp

        if let prev = lastRecorded {
            let d = loc.distance(from: prev)
            // Sprünge durch schlechten Empfang ignorieren
            let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
            let plausible = dt > 0 && d / dt < 350
            guard plausible else { return }
            if d < max(2, loc.horizontalAccuracy * 0.5) && !moving { return }
            if moving { distance += d }
        }

        if loc.verticalAccuracy >= 0, loc.verticalAccuracy < 15 {
            if let la = lastAltitude {
                let dh = loc.altitude - la
                if abs(dh) >= 2 {
                    if dh > 0 { elevationGain += dh } else { elevationLoss += -dh }
                    lastAltitude = loc.altitude
                }
            } else {
                lastAltitude = loc.altitude
            }
        }

        maxSpeed = max(maxSpeed, v)
        lastRecorded = loc
        points.append(TrackPoint(t: loc.timestamp,
                                 lat: loc.coordinate.latitude,
                                 lon: loc.coordinate.longitude,
                                 alt: loc.altitude,
                                 speed: v,
                                 accuracy: loc.horizontalAccuracy,
                                 activity: activity))
    }

    private func handleSprint(_ loc: CLLocation, speed v: Double) {
        let kmh = v * 3.6
        switch sprintPhase {
        case .armed:
            if kmh > 1.5 {
                sprintPhase = .running(start: loc.timestamp.addingTimeInterval(-0.5))
                sprintLast = loc
                sprintDistance = 0
            }
        case .running(let start):
            if let last = sprintLast { sprintDistance += loc.distance(from: last) }
            sprintLast = loc
            sprintLive = loc.timestamp.timeIntervalSince(start)
            if kmh >= sprintTargetKmh {
                let t = sprintLive
                sprintPhase = .done(t)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSprintFinished?(t, sprintDistance)
            } else if kmh < 0.5 && sprintLive > 2 {
                sprintPhase = .armed   // abgebrochen, neu scharf schalten
            }
        default:
            break
        }
    }
}
