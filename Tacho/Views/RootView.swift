import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(TachoEngine.self) private var engine
    @AppStorage(Pref.keepAwake) private var keepAwake = true
    @AppStorage(Pref.autoPause) private var autoPause = true
    @AppStorage(Pref.indoorMode) private var indoorMode: IndoorMode = .auto
    @AppStorage(Pref.floorHeight) private var floorHeight: Double = 3.0
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Tacho", systemImage: "gauge.with.dots.needle.67percent", value: 0) {
                SpeedometerScreen()
            }
            Tab("Karte", systemImage: "map.fill", value: 1) {
                LiveMapScreen()
            }
            Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: 2) {
                HistoryScreen()
            }
            Tab("Rekorde", systemImage: "trophy.fill", value: 3) {
                RecordsScreen()
            }
            Tab("Mehr", systemImage: "slider.horizontal.3", value: 4) {
                SettingsScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            RecordingAccessory()
        }
        .tint(engine.activity.color)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            engine.autoPauseEnabled = autoPause
            engine.indoorMode = indoorMode
            engine.floorEstimator.floorHeight = floorHeight
        }
        .onChange(of: floorHeight) { _, v in engine.floorEstimator.floorHeight = v }
        .onChange(of: indoorMode) { _, v in engine.indoorMode = v }
        .onChange(of: keepAwake) { _, v in UIApplication.shared.isIdleTimerDisabled = v }
        .onChange(of: autoPause) { _, v in engine.autoPauseEnabled = v }
    }
}

/// Kompakte Statusleiste über der Tab-Bar (Liquid Glass Accessory).
struct RecordingAccessory: View {
    @Environment(TachoEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: engine.activity.symbol)
                .foregroundStyle(engine.activity.color)
                .contentTransition(.symbolEffect(.replace))
            if engine.speedSource != .gps {
                Image(systemName: engine.speedSource.symbol)
                    .foregroundStyle(.cyan)
                    .contentTransition(.symbolEffect(.replace))
            }
            if engine.isRecording {
                Circle()
                    .fill(engine.state == .paused ? .orange : .red)
                    .frame(width: 8, height: 8)
                    .symbolEffect(.pulse)
                Text(Fmt.duration(engine.elapsed))
                    .monospacedDigit()
                Text(unit.formatDistance(engine.distance))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(engine.place.shortDescription)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(String(format: "%.0f %@", unit.convert(engine.speed), unit.label))
                .monospacedDigit()
                .fontWeight(.semibold)
                .contentTransition(.numericText(value: engine.speed))
            if engine.isRecording {
                Button {
                    engine.state == .paused ? engine.resumeRecording() : engine.pauseRecording()
                } label: {
                    Image(systemName: engine.state == .paused ? "play.fill" : "pause.fill")
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .animation(.snappy, value: engine.speed)
    }
}
