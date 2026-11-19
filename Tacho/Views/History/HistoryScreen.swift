import SwiftUI
import SwiftData

struct HistoryScreen: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var filter: ActivityType?
    @State private var search = ""

    private var filtered: [Trip] {
        trips.filter { t in
            (filter == nil || t.activity == filter) &&
            (search.isEmpty
             || t.name.localizedCaseInsensitiveContains(search)
             || (t.startPlace ?? "").localizedCaseInsensitiveContains(search)
             || (t.endPlace ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    struct MonthGroup: Identifiable {
        let id: String
        let trips: [Trip]
    }

    private var grouped: [MonthGroup] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMMM yyyy"
        var order: [String] = []
        var dict: [String: [Trip]] = [:]
        for t in filtered {
            let k = f.string(from: t.startDate)
            if dict[k] == nil { order.append(k) }
            dict[k, default: []].append(t)
        }
        return order.map { MonthGroup(id: $0, trips: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                    filterBar
                    if filtered.isEmpty {
                        ContentUnavailableView("Noch keine Fahrten",
                                               systemImage: "road.lanes",
                                               description: Text("Starte im Tacho eine Aufzeichnung – deine Routen landen dann hier."))
                            .padding(.top, 60)
                    }
                    ForEach(grouped) { group in
                        Text(group.id)
                            .font(.title3.weight(.bold))
                            .padding(.top, 8)
                        ForEach(group.trips) { trip in
                            NavigationLink(value: trip) {
                                TripRow(trip: trip, unit: unit)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Löschen", systemImage: "trash", role: .destructive) {
                                    withAnimation { context.delete(trip) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AmbientBackground(color: filter?.color ?? .blue, intensity: 0.6))
            .navigationTitle("Verlauf")
            .searchable(text: $search, prompt: "Fahrten oder Orte suchen")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(nil, title: "Alle", symbol: "square.grid.2x2")
                    ForEach(ActivityType.selectable) { a in
                        chip(a, title: a.title, symbol: a.symbol)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ a: ActivityType?, title: String, symbol: String) -> some View {
        let selected = filter == a
        let tint = a?.color ?? .white
        return Button {
            withAnimation(.snappy) { filter = a }
        } label: {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(tint.opacity(0.45)).interactive() : .regular.interactive(), in: .capsule)
    }
}

struct TripRow: View {
    let trip: Trip
    let unit: SpeedUnit
    @State private var points: [TrackPoint] = []

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(trip.activity.color.opacity(0.12))
                RouteShape(points: points)
                    .stroke(trip.activity.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .padding(10)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: trip.activity.symbol)
                        .foregroundStyle(trip.activity.color)
                    Text(trip.name)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                if let s = trip.startPlace {
                    Text(trip.endPlace.map { "\(s) → \($0)" } ?? s)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    Label(unit.formatDistance(trip.distance), systemImage: "ruler")
                    Label(Fmt.duration(trip.duration), systemImage: "timer")
                    Label(unit.formatSpeed(trip.maxSpeed, decimals: 0), systemImage: "bolt.fill")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .task(id: trip.id) { points = trip.points }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.caption2)
            configuration.title
        }
    }
}
