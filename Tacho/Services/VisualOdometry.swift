import Foundation
import ARKit
import CoreLocation
import Observation
import simd

/// Visuell-inertiale Odometrie über ARKit (Kamera + Bewegungssensoren, optional LiDAR).
/// Liefert Geschwindigkeit und Strecke auch dort, wo GPS versagt – in Gebäuden,
/// Bahnhöfen, Tiefgaragen und Tunneln – und erkennt Raumelemente.
@Observable
final class VisualOdometry {
    struct RoomInfo: Equatable {
        var walls = 0
        var floors = 0
        var ceilings = 0
        var doors = 0
        var windows = 0
        var tables = 0
        var seats = 0
        var floorArea: Double = 0     // m²
        var roomHeight: Double?       // m
        var meshSegments = 0

        var isEmpty: Bool { walls + floors + ceilings + doors + windows + tables + seats == 0 && meshSegments == 0 }
    }

    @ObservationIgnored let session = ARSession()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var samples: [(t: TimeInterval, p: SIMD3<Float>)] = []
    @ObservationIgnored private var lastDistPos: SIMD3<Float>?
    @ObservationIgnored private var lastRoomUpdate: TimeInterval = 0
    @ObservationIgnored private var anchorLocation: CLLocation?
    @ObservationIgnored private var anchorPosition: SIMD3<Float>?

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    static var hasLiDAR: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }

    var isRunning = false
    /// Wurde manuell (z. B. über die Kamera-Ansicht) gestartet.
    var startedManually = false
    var trackingOK = false
    var trackingText = "Aus"
    /// Horizontale Geschwindigkeit in m/s.
    var speed: Double = 0
    var verticalSpeed: Double = 0
    /// Zurückgelegte Strecke seit Start in m.
    var distance: Double = 0
    var lastGoodUpdate: Date?
    /// Abstand zum Objekt in Bildmitte (LiDAR) in m.
    var distanceAhead: Double?
    var room = RoomInfo()
    var position: SIMD3<Float> = .zero

    var usesLiDAR: Bool { isRunning && Self.hasLiDAR }

    func start(anchor: CLLocation?, manual: Bool = false) {
        guard Self.isSupported else { return }
        if manual { startedManually = true }
        guard !isRunning else { return }

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal, .vertical]
        if Self.hasLiDAR {
            config.sceneReconstruction = .mesh
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                config.frameSemantics.insert(.smoothedSceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        samples = []
        lastDistPos = nil
        anchorPosition = nil
        anchorLocation = anchor
        distance = 0
        speed = 0
        room = RoomInfo()
        distanceAhead = nil
        isRunning = true
        trackingText = "Initialisiere …"

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        session.pause()
        isRunning = false
        startedManually = false
        trackingOK = false
        trackingText = "Aus"
        speed = 0
        samples = []
    }

    /// Geschätzte Position: GPS-Ankerpunkt + visuelle Verschiebung (x = Ost, z = Süd).
    var estimatedCoordinate: CLLocationCoordinate2D? {
        guard let loc = anchorLocation, let a = anchorPosition else { return nil }
        let east = Double(position.x - a.x)
        let north = Double(-(position.z - a.z))
        let lat0 = loc.coordinate.latitude
        let lat = lat0 + north / 111_320
        let lon = loc.coordinate.longitude + east / (111_320 * cos(lat0 * .pi / 180))
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Ankerpunkt neu setzen, sobald wieder ein gutes GPS-Signal da ist.
    func reanchor(_ location: CLLocation) {
        anchorLocation = location
        anchorPosition = position
    }

    // MARK: - Auswertung

    private func poll() {
        guard let frame = session.currentFrame else { return }
        let cam = frame.camera

        switch cam.trackingState {
        case .normal:
            trackingOK = true
            trackingText = Self.hasLiDAR ? "Kamera + LiDAR" : "Kamera"
        case .limited(let reason):
            trackingOK = false
            switch reason {
            case .initializing: trackingText = "Initialisiere …"
            case .excessiveMotion: trackingText = "Zu schnelle Bewegung"
            case .insufficientFeatures: trackingText = "Zu wenig sichtbar"
            case .relocalizing: trackingText = "Orientiere neu …"
            @unknown default: trackingText = "Eingeschränkt"
            }
        case .notAvailable:
            trackingOK = false
            trackingText = "Nicht verfügbar"
        }

        let c = cam.transform.columns.3
        let p = SIMD3<Float>(c.x, c.y, c.z)
        let t = frame.timestamp
        position = p

        guard trackingOK else {
            samples.removeAll()
            lastDistPos = nil
            speed *= 0.9
            if speed < 0.05 { speed = 0 }
            return
        }

        if anchorPosition == nil { anchorPosition = p }

        samples.append((t, p))
        while let first = samples.first, t - first.t > 1.0 { samples.removeFirst() }
        if let first = samples.first, samples.count > 3 {
            let dt = t - first.t
            if dt > 0.3 {
                let d = p - first.p
                let horizontal = Double(simd_length(SIMD2<Float>(d.x, d.z))) / dt
                let vertical = Double(d.y) / dt
                if horizontal < 70 { // Sprünge durch Relokalisierung verwerfen
                    speed = speed + 0.35 * (horizontal - speed)
                    if speed < 0.08 { speed = 0 }
                    verticalSpeed = verticalSpeed + 0.3 * (vertical - verticalSpeed)
                }
            }
        }
        lastGoodUpdate = .now

        // Strecke: nur Schritte > 15 cm zählen, damit Handzittern nicht aufsummiert wird
        if let last = lastDistPos {
            let step = Double(simd_length(SIMD2<Float>(p.x - last.x, p.z - last.z)))
            if step > 8 {
                lastDistPos = p
            } else if step > 0.15 {
                distance += step
                lastDistPos = p
            }
        } else {
            lastDistPos = p
        }

        // LiDAR-Tiefe in Bildmitte
        if let depth = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap {
            distanceAhead = Self.centerDepth(depth)
        }

        if t - lastRoomUpdate > 0.5 {
            lastRoomUpdate = t
            updateRoom(frame.anchors)
        }
    }

    private func updateRoom(_ anchors: [ARAnchor]) {
        var r = RoomInfo()
        var floorY: [Float] = []
        var ceilingY: [Float] = []
        for a in anchors {
            if a is ARMeshAnchor { r.meshSegments += 1; continue }
            guard let plane = a as? ARPlaneAnchor else { continue }
            let y = plane.transform.columns.3.y
            let area = Double(plane.planeExtent.width * plane.planeExtent.height)
            switch plane.classification {
            case .wall: r.walls += 1
            case .floor:
                r.floors += 1
                r.floorArea += area
                floorY.append(y)
            case .ceiling:
                r.ceilings += 1
                ceilingY.append(y)
            case .door: r.doors += 1
            case .window: r.windows += 1
            case .table: r.tables += 1
            case .seat: r.seats += 1
            default:
                // Ohne Klassifizierung: große horizontale Fläche unterhalb der Kamera = Boden
                if plane.alignment == .horizontal && y < position.y - 0.8 {
                    r.floorArea += area
                    floorY.append(y)
                }
            }
        }
        if let f = floorY.min(), let c = ceilingY.max(), c > f {
            r.roomHeight = Double(c - f)
        }
        if r != room { room = r }
    }

    private static func centerDepth(_ buffer: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        var sum: Float = 0
        var n: Float = 0
        for dy in -2...2 {
            let ptr = base.advanced(by: (h / 2 + dy) * row).assumingMemoryBound(to: Float32.self)
            for dx in -2...2 {
                let v = ptr[w / 2 + dx]
                if v.isFinite && v > 0 { sum += v; n += 1 }
            }
        }
        return n > 0 ? Double(sum / n) : nil
    }
}
