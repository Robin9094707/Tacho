import SwiftUI
import SwiftData
import MapKit
import Charts

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh

    @State private var points: [TrackPoint] = []
    @State private var chartPoints: [TrackPoint] = []
    @State private var segments: [SpeedSegment] = []
    @State private var selectedDate: Date?
    @State private var position: MapCameraPosition = .automatic
    @State private var gpxURL: URL?
    @State private var confirmDelete = false
    @State private var mapExpanded = false

    private var selectedPoint: TrackPoint? {
        guard let d = selectedDate else { return nil }
        return chartPoints.min { abs($0.t.timeIntervalSince(d)) < abs($1.t.timeIntervalSince(d)) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                map
                titleCard
                statsGrid
                if chartPoints.count > 2 {
                    speedChart
                    altitudeChart
                }
                breakdownCard
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AmbientBackground(color: trip.activity.color, intensity: 0.7))
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let gpxURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: gpxURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: trip.id) { load() }
        .confirmationDialog("Fahrt löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(trip)
                try? context.save()
                dismiss()
            }
        }
    }

    private func load() {
        let pts = trip.points
        points = pts
        let stride = max(1, pts.count / 400)
        chartPoints = pts.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
        segments = SpeedSegment.build(from: pts)
        gpxURL = GPXExporter.write(trip: trip, points: pts)
    }

    // MARK: - Karte

    private var map: some View {
        Map(position: $position) {
            ForEach(segments) { seg in
                MapPolyline(coordinates: seg.coordinates)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let f = points.first {
                Annotation("Start", coordinate: f.coordinate) {
                    Image(systemName: "flag.fill").font(.caption)
                        .padding(6)
                        .glassEffect(.regular.tint(.green.opacity(0.6)), in: .circle)
                }
            }
            if let l = points.last, points.count > 1 {
                Annotation("Ziel", coordinate: l.coordinate) {
                    Image(systemName: "flag.checkered").font(.caption)
                        .padding(6)
                        .glassEffect(.regular.tint(.red.opacity(0.6)), in: .circle)
                }
            }
            if let p = selectedPoint {
                Annotation(unit.formatSpeed(p.speed, decimals: 0), coordinate: p.coordinate) {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(trip.activity.color, lineWidth: 4))
                        .shadow(radius: 4)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .frame(height: mapExpanded ? 520 : 300)
        .clipShape(.rect(cornerRadius: 28))
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.smooth) { mapExpanded.toggle() }
            } label: {
                Image(systemName: mapExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .padding(10)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                Text("langsam").font(.caption2)
                LinearGradient(colors: (0...4).map { speedColor(Double($0) / 4) }, startPoint: .leading, endPoint: .trailing)
                    .frame(width: 80, height: 6)
                    .clipShape(Capsule())
                Text("schnell").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .padding(10)
        }
    }

    // MARK: - Karten-Inhalte

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $trip.name)
                .font(.title3.weight(.bold))
            HStack {
                Menu {
                    ForEach(ActivityType.selectable) { a in
                        Button {
                            trip.activity = a
                        } label: {
                            Label(a.title, systemImage: a.symbol)
                        }
                    }
                } label: {
                    ActivityBadge(activity: trip.activity, confidence: nil, manual: false)
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(trip.startDate, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    Text("\(trip.startDate.formatted(date: .omitted, time: .shortened)) – \(trip.endDate.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if trip.startPlace != nil || trip.endPlace != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label(trip.startPlace ?? "–", systemImage: "circle.circle.fill")
                        .foregroundStyle(.green)
                    Label(trip.endPlace ?? "–", systemImage: "mappin.circle.fill")
                        .foregroundStyle(.red)
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var statsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let c = trip.activity.color
        return LazyVGrid(columns: cols, spacing: 12) {
            StatTile(title: "Strecke", value: unit.formatDistance(trip.distance), symbol: "ruler", tint: c)
            StatTile(title: "Dauer", value: Fmt.duration(trip.duration), symbol: "clock", tint: c)
            StatTile(title: "In Bewegung", value: Fmt.duration(trip.movingTime), symbol: "figure.walk.motion", tint: c)
            StatTile(title: "Max", value: unit.formatSpeed(trip.maxSpeed, decimals: 0), symbol: "bolt.fill", tint: .yellow)
            StatTile(title: "Ø", value: unit.formatSpeed(trip.averageSpeed, decimals: 1), symbol: "speedometer", tint: c)
            StatTile(title: "Pace", value: unit.formatPace(trip.averageSpeed), symbol: "figure.run", tint: c)
            StatTile(title: "Aufstieg", value: "\(Int(trip.elevationGain)) m", symbol: "arrow.up.right", tint: .green)
            StatTile(title: "Abstieg", value: "\(Int(trip.elevationLoss)) m", symbol: "arrow.down.right", tint: .orange)
            StatTile(title: "Punkte", value: "\(points.count)", symbol: "point.3.connected.trianglepath.dotted", tint: .secondary)
        }
    }

    private var speedChart: some View {
        let maxV = unit.convert(chartPoints.map(\.speed).max() ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Geschwindigkeit", systemImage: "chart.xyaxis.line").font(.headline)
                Spacer()
                if let p = selectedPoint {
                    Text("\(unit.formatSpeed(p.speed)) · \(p.t.formatted(date: .omitted, time: .standard))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(chartPoints) { p in
                    AreaMark(x: .value("Zeit", p.t), y: .value(unit.label, unit.convert(p.speed)))
                        .foregroundStyle(LinearGradient(colors: [trip.activity.color.opacity(0.5), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Zeit", p.t), y: .value(unit.label, unit.convert(p.speed)))
                        .foregroundStyle(trip.activity.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("Max", maxV))
                    .foregroundStyle(.yellow.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Max \(Int(maxV))").font(.caption2).foregroundStyle(.yellow)
                    }
                if let p = selectedPoint {
                    RuleMark(x: .value("Auswahl", p.t))
                        .foregroundStyle(.white.opacity(0.6))
                    PointMark(x: .value("Zeit", p.t), y: .value(unit.label, unit.convert(p.speed)))
                        .foregroundStyle(.white)
                        .symbolSize(60)
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxisLabel(unit.label)
            .frame(height: 200)
            Text("Tippe & ziehe im Diagramm, um die Stelle auf der Karte zu sehen.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var altitudeChart: some View {
        let alts = chartPoints.map(\.alt)
        let lo = (alts.min() ?? 0) - 5
        let hi = (alts.max() ?? 10) + 5
        return VStack(alignment: .leading, spacing: 10) {
            Label("Höhenprofil", systemImage: "mountain.2.fill").font(.headline)
            Chart(chartPoints) { p in
                AreaMark(x: .value("Zeit", p.t), yStart: .value("Basis", lo), yEnd: .value("Höhe", p.alt))
                    .foregroundStyle(LinearGradient(colors: [.green.opacity(0.5), .green.opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Zeit", p.t), y: .value("Höhe", p.alt))
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: lo...hi)
            .chartYAxisLabel("m")
            .frame(height: 140)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var breakdownCard: some View {
        let parts = trip.activityBreakdown(from: points).filter { $0.activity != .unknown }
        return VStack(alignment: .leading, spacing: 12) {
            Label("Erkannte Fortbewegung", systemImage: "sparkles").font(.headline)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(part.activity.color)
                            .frame(width: max(2, Double(geo.size.width) * part.share - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            ForEach(parts) { part in
                HStack {
                    Image(systemName: part.activity.symbol).foregroundStyle(part.activity.color).frame(width: 24)
                    Text(part.activity.title)
                    Spacer()
                    Text("\(Int((part.share * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if let gpxURL {
                    ShareLink(item: gpxURL) {
                        Label("GPX exportieren", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .tint(.red)
            }
        }
    }
}
