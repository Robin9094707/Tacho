import SwiftUI
import SwiftData
import Charts

struct RecordsScreen: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \SprintResult.time) private var sprints: [SprintResult]
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh

    private struct WeekStat: Identifiable {
        let week: Date
        let activity: ActivityType
        let distance: Double
        var id: String { "\(week.timeIntervalSince1970)-\(activity.rawValue)" }
    }

    private var totalDistance: Double { trips.reduce(0) { $0 + $1.distance } }
    private var totalTime: TimeInterval { trips.reduce(0) { $0 + $1.movingTime } }
    private var topSpeed: Trip? { trips.max { $0.maxSpeed < $1.maxSpeed } }
    private var longest: Trip? { trips.max { $0.distance < $1.distance } }

    private var weekly: [WeekStat] {
        let cal = Calendar(identifier: .iso8601)
        guard let from = cal.date(byAdding: .weekOfYear, value: -11, to: .now) else { return [] }
        var acc: [Date: [ActivityType: Double]] = [:]
        for t in trips where t.startDate >= cal.startOfDay(for: from) {
            let week = cal.dateInterval(of: .weekOfYear, for: t.startDate)?.start ?? t.startDate
            acc[week, default: [:]][t.activity, default: 0] += t.distance
        }
        return acc.flatMap { week, dict in
            dict.map { WeekStat(week: week, activity: $0.key, distance: $0.value) }
        }
        .sorted { $0.week < $1.week }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    if !trips.isEmpty { weeklyChart }
                    perActivity
                    sprintCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(AmbientBackground(color: .yellow, intensity: 0.5))
            .navigationTitle("Rekorde")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
        }
    }

    private var hero: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            StatTile(title: "Gesamtstrecke", value: unit.formatDistance(totalDistance), symbol: "globe.europe.africa.fill", tint: .cyan)
            StatTile(title: "Unterwegs", value: Fmt.duration(totalTime), symbol: "hourglass", tint: .mint)
            StatTile(title: "Fahrten", value: "\(trips.count)", symbol: "list.number", tint: .purple)
            StatTile(title: "Höchstwert", value: unit.formatSpeed(topSpeed?.maxSpeed ?? 0, decimals: 0), symbol: "bolt.fill", tint: .yellow)
        }
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Strecke pro Woche", systemImage: "chart.bar.fill").font(.headline)
            Chart(weekly) { w in
                BarMark(x: .value("Woche", w.week, unit: .weekOfYear),
                        y: .value("Strecke", unit.usesMiles ? w.distance / 1609.344 : w.distance / 1000))
                    .foregroundStyle(w.activity.color)
                    .cornerRadius(4)
            }
            .chartYAxisLabel(unit.usesMiles ? "mi" : "km")
            .frame(height: 180)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var perActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bestwerte je Fortbewegung", systemImage: "medal.fill").font(.headline)
            ForEach(ActivityType.selectable) { a in
                let list = trips.filter { $0.activity == a }
                if let best = list.max(by: { $0.maxSpeed < $1.maxSpeed }) {
                    NavigationLink(value: best) {
                        HStack(spacing: 12) {
                            Image(systemName: a.symbol)
                                .font(.title3)
                                .foregroundStyle(a.color)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular.tint(a.color.opacity(0.3)), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).font(.subheadline.weight(.bold))
                                Text("\(list.count) Fahrten · \(unit.formatDistance(list.reduce(0) { $0 + $1.distance }))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(unit.formatSpeed(best.maxSpeed, decimals: 1))
                                    .font(.headline.monospacedDigit())
                                Text(best.startDate, format: .dateTime.day().month().year())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            if trips.isEmpty {
                Text("Zeichne Fahrten auf, um hier deine Bestwerte zu sehen – z. B. wie schnell die S-Bahn wirklich fährt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let longest {
                Divider()
                NavigationLink(value: longest) {
                    HStack {
                        Label("Längste Fahrt", systemImage: "road.lanes")
                        Spacer()
                        Text(unit.formatDistance(longest.distance)).monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var sprintCard: some View {
        let targets = Array(Set(sprints.map(\.targetKmh))).sorted()
        return VStack(alignment: .leading, spacing: 12) {
            Label("Beste Sprints", systemImage: "stopwatch.fill").font(.headline)
            if targets.isEmpty {
                Text("Noch keine Sprint-Messungen. Starte eine über das Stoppuhr-Symbol im Tacho.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(targets, id: \.self) { t in
                if let best = sprints.first(where: { $0.targetKmh == t }) {
                    HStack {
                        Text("0–\(Int(t)) km/h").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: best.activity.symbol).foregroundStyle(best.activity.color)
                        Text(String(format: "%.2f s", best.time)).font(.headline.monospacedDigit())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}
