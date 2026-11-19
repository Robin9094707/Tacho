import SwiftUI
import MapKit

struct LiveMapScreen: View {
    @Environment(TachoEngine.self) private var engine
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh
    @AppStorage(Pref.theme) private var theme: Theme = .activity
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var mapKind = 0
    @Namespace private var mapScope

    private var mapStyle: MapStyle {
        switch mapKind {
        case 1: .hybrid(elevation: .realistic, pointsOfInterest: .including([.publicTransport]))
        case 2: .imagery(elevation: .realistic)
        default: .standard(elevation: .realistic, pointsOfInterest: .including([.publicTransport]), showsTraffic: true)
        }
    }

    var body: some View {
        let accent = theme.accent(for: engine.activity)
        ZStack(alignment: .bottom) {
            Map(position: $position, scope: mapScope) {
                UserAnnotation()
                if engine.points.count > 1 {
                    ForEach(SpeedSegment.build(from: engine.points)) { seg in
                        MapPolyline(coordinates: seg.coordinates)
                            .stroke(seg.color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                    if let first = engine.points.first {
                        Annotation("Start", coordinate: first.coordinate) {
                            Image(systemName: "flag.fill")
                                .padding(6)
                                .glassEffect(.regular.tint(.green.opacity(0.5)), in: .circle)
                        }
                    }
                }
            }
            .mapStyle(mapStyle)
            .mapControls {
                MapCompass(scope: mapScope)
                MapScaleView(scope: mapScope)
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(spacing: 10) {
                        MapUserLocationButton(scope: mapScope)
                        MapPitchToggle(scope: mapScope)
                    }
                    .buttonBorderShape(.circle)
                    .padding(6)
                    .glassEffect(.regular, in: .capsule)
                    Spacer()
                    Menu {
                        Picker("Kartenstil", selection: $mapKind) {
                            Label("Standard", systemImage: "map").tag(0)
                            Label("Hybrid", systemImage: "map.fill").tag(1)
                            Label("Satellit", systemImage: "globe.europe.africa.fill").tag(2)
                        }
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.title3)
                            .padding(12)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)

                Spacer()

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%.0f", unit.convert(engine.speed)))
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: engine.speed))
                        Text(unit.label).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(accent)
                    Divider().frame(height: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(engine.activity.title, systemImage: engine.activity.symbol)
                            .font(.subheadline.weight(.semibold))
                        Label(engine.place.shortDescription, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if engine.isRecording {
                            Label("\(unit.formatDistance(engine.distance)) · \(Fmt.duration(engine.elapsed))",
                                  systemImage: "record.circle")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .animation(.snappy, value: engine.speed)
            }
        }
        .mapScope(mapScope)
    }
}

/// Teilt eine Route in farbige Abschnitte nach Geschwindigkeit.
struct SpeedSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let color: Color

    static func build(from points: [TrackPoint], buckets: Int = 8) -> [SpeedSegment] {
        guard points.count > 1 else { return [] }
        let maxV = max(points.map(\.speed).max() ?? 1, 0.5)
        var result: [SpeedSegment] = []
        var current: [CLLocationCoordinate2D] = [points[0].coordinate]
        var currentBucket = bucket(points[0].speed, maxV, buckets)
        for p in points.dropFirst() {
            let b = bucket(p.speed, maxV, buckets)
            current.append(p.coordinate)
            if b != currentBucket {
                result.append(SpeedSegment(id: result.count, coordinates: current,
                                           color: speedColor(Double(currentBucket) / Double(buckets - 1))))
                current = [p.coordinate]
                currentBucket = b
            }
        }
        if current.count > 1 {
            result.append(SpeedSegment(id: result.count, coordinates: current,
                                       color: speedColor(Double(currentBucket) / Double(buckets - 1))))
        }
        return result
    }

    private static func bucket(_ v: Double, _ maxV: Double, _ n: Int) -> Int {
        min(n - 1, Int(v / maxV * Double(n)))
    }
}
