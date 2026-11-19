import SwiftUI
import SwiftData

/// Beschleunigungsmessung: 0–30, 0–50, 0–100 … mit Bestenliste.
struct SprintSheet: View {
    @Environment(TachoEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh
    @Query(sort: \SprintResult.time) private var results: [SprintResult]
    @State private var target: Double = 100

    private let presets: [Double] = [20, 30, 50, 80, 100, 130, 200]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Ziel", selection: $target) {
                        ForEach(presets, id: \.self) { p in
                            Text("0–\(Int(p))").tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    timerDisplay

                    GlassEffectContainer {
                        HStack(spacing: 12) {
                            if engine.sprintPhase == .off || isDone {
                                Button {
                                    engine.armSprint(target: target)
                                } label: {
                                    Label("Scharf schalten", systemImage: "flag.checkered")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(.green)
                            } else {
                                Button(role: .cancel) {
                                    engine.cancelSprint()
                                } label: {
                                    Label("Abbrechen", systemImage: "xmark")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }

                    leaderboard
                }
                .padding(20)
            }
            .navigationTitle("Sprint-Messung")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            engine.onSprintFinished = { [context, target] time, dist in
                context.insert(SprintResult(date: .now, targetKmh: target, time: time,
                                            distance: dist, activity: engine.activity))
                try? context.save()
            }
        }
        .onChange(of: target) { _, t in
            if engine.sprintPhase != .off { engine.armSprint(target: t) }
            engine.onSprintFinished = { time, dist in
                context.insert(SprintResult(date: .now, targetKmh: t, time: time,
                                            distance: dist, activity: engine.activity))
                try? context.save()
            }
        }
    }

    private var isDone: Bool {
        if case .done = engine.sprintPhase { return true }
        return false
    }

    private var timerDisplay: some View {
        let (title, time, color): (String, TimeInterval, Color) = {
            switch engine.sprintPhase {
            case .off: return ("Bereit", 0, .secondary)
            case .armed: return ("Steh still – los geht's beim Anfahren", 0, .yellow)
            case .running: return ("Läuft …", engine.sprintLive, .orange)
            case .done(let t): return ("Geschafft! 🏁", t, .green)
            }
        }()
        return VStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(String(format: "%.2f s", time))
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: time))
            HStack(spacing: 24) {
                Label(unit.formatSpeed(engine.speed, decimals: 0), systemImage: "speedometer")
                Label(String(format: "%.0f m", engine.sprintDistance), systemImage: "ruler")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            Text("Ziel: 0–\(Int(target)) km/h · GPS misst ca. 1× pro Sekunde, Werte sind ±0,5 s genau.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassEffect(.regular.tint(color.opacity(0.15)), in: .rect(cornerRadius: 32))
        .animation(.snappy, value: time)
    }

    private var leaderboard: some View {
        let filtered = results.filter { $0.targetKmh == target }
        return VStack(alignment: .leading, spacing: 10) {
            Label("Bestenliste 0–\(Int(target))", systemImage: "trophy.fill")
                .font(.headline)
            if filtered.isEmpty {
                Text("Noch keine Messungen.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ForEach(Array(filtered.prefix(10).enumerated()), id: \.element.id) { idx, r in
                HStack {
                    Text("\(idx + 1).")
                        .font(.headline.monospacedDigit())
                        .frame(width: 30, alignment: .leading)
                        .foregroundStyle(idx == 0 ? Color.yellow : Color.secondary)
                    Image(systemName: r.activity.symbol).foregroundStyle(r.activity.color)
                    Text(String(format: "%.2f s", r.time)).font(.headline.monospacedDigit())
                    Spacer()
                    Text(r.date, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .contextMenu {
                    Button("Löschen", role: .destructive) { context.delete(r) }
                }
            }
        }
    }
}
