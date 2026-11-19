import SwiftUI
import SwiftData

struct SpeedometerScreen: View {
    @Environment(TachoEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh
    @AppStorage(Pref.gaugeStyle) private var style: GaugeStyle = .analog
    @AppStorage(Pref.speedLimit) private var limitKmh: Double = 0
    @AppStorage(Pref.theme) private var theme: Theme = .activity
    @AppStorage(Pref.haptics) private var haptics = true

    @State private var showStopDialog = false
    @State private var showSprint = false
    @State private var showHUD = false
    @State private var showIndoor = false
    @State private var savedTrip: Trip?
    @Namespace private var glassNS

    private var colors: [Color] { theme.colors(for: engine.activity) }
    private var display: Double { unit.convert(engine.speed) }
    private var limit: Double? { limitKmh > 0 ? unit.fromKmh(limitKmh) : nil }
    private var overLimit: Bool { limit.map { display > $0 } ?? false }

    private var gaugeMax: Double {
        let needed = max(engine.activity.gaugeMaxKmh, engine.sessionMax * 3.6 * 1.1, engine.speed * 3.6 * 1.1)
        let steps: [Double] = [20, 30, 40, 60, 80, 120, 160, 200, 240, 280, 320, 400, 600, 1000, 1200]
        let kmh = steps.first { $0 >= needed } ?? 1200
        return (unit.fromKmh(kmh) / 10).rounded(.up) * 10
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    styleSwitcher
                    speedDisplay
                    sparkline
                    controls
                    statsGrid
                    indoorCard
                    environmentCard
                    detectionCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(AmbientBackground(color: overLimit ? .red : colors[1]))
            .navigationTitle("Tacho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { engine.resetSession() }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Spitzenwert zurücksetzen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSprint = true } label: {
                        Label("Sprint", systemImage: "stopwatch.fill")
                    }
                }
            }
            .sensoryFeedback(.warning, trigger: overLimit) { old, new in haptics && new && !old }
            .sensoryFeedback(.impact(weight: .medium), trigger: engine.state)
            .confirmationDialog("Aufzeichnung beenden?", isPresented: $showStopDialog, titleVisibility: .visible) {
                Button("Fahrt speichern") {
                    savedTrip = engine.stopRecording(context: context)
                }
                Button("Verwerfen", role: .destructive) { engine.discardRecording() }
                Button("Weiter aufzeichnen", role: .cancel) {}
            }
            .sheet(isPresented: $showSprint) {
                SprintSheet().presentationDetents([.medium, .large])
            }
            .sheet(item: $savedTrip) { trip in
                NavigationStack { TripDetailView(trip: trip) }
            }
            .fullScreenCover(isPresented: $showIndoor) {
                IndoorScanScreen()
            }
            .fullScreenCover(isPresented: $showHUD) {
                HUDScreen(color: overLimit ? .red : colors[1])
            }
        }
    }

    // MARK: - Abschnitte

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Label(engine.place.shortDescription, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Label(engine.place.surroundings.title, systemImage: engine.place.surroundings.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    engine.manualActivity = nil
                } label: {
                    Label("Automatisch erkennen", systemImage: "sparkles")
                }
                Divider()
                ForEach(ActivityType.selectable) { a in
                    Button {
                        engine.manualActivity = a
                    } label: {
                        Label(a.title, systemImage: a.symbol)
                    }
                }
            } label: {
                ActivityBadge(activity: engine.activity,
                              confidence: engine.detected.confidence,
                              manual: engine.manualActivity != nil)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var styleSwitcher: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(GaugeStyle.allCases) { s in
                    Button {
                        if s == .hud {
                            showHUD = true
                        } else {
                            withAnimation(.bouncy) { style = s }
                        }
                    } label: {
                        Label(s.title, systemImage: s.symbol)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(style == s ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(style == s ? .regular.tint(colors[1].opacity(0.5)).interactive() : .regular.interactive(),
                                 in: .capsule)
                    .glassEffectID(s.rawValue, in: glassNS)
                }
            }
        }
    }

    @ViewBuilder
    private var speedDisplay: some View {
        switch style {
        case .analog, .hud:
            GaugeView(value: display,
                      maxValue: gaugeMax,
                      peak: unit.convert(engine.sessionMax),
                      limit: limit,
                      unitLabel: unit.label,
                      colors: overLimit ? [.orange, .red, .red] : colors,
                      subtitle: "Max \(String(format: "%.0f", unit.convert(engine.sessionMax))) · \(engine.speedSource.title)")
                .padding(.horizontal, 4)
                .transition(.scale.combined(with: .opacity))
        case .digital:
            DigitalSpeedView(value: display,
                             maxValue: gaugeMax,
                             limit: limit,
                             unitLabel: unit.label,
                             colors: colors)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Letzte 2 Minuten").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Spitze \(unit.formatSpeed(engine.sessionMax, decimals: 0))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            Sparkline(values: engine.speedHistory.map { unit.convert($0) }, color: colors[1])
                .frame(height: 54)
                .animation(.linear(duration: 1), value: engine.speedHistory.count)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                switch engine.state {
                case .idle:
                    Button {
                        withAnimation(.bouncy) { engine.startRecording() }
                    } label: {
                        Label("Aufzeichnung starten", systemImage: "record.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .glassEffectID("main", in: glassNS)
                case .recording, .paused:
                    Button {
                        withAnimation(.bouncy) {
                            engine.state == .paused ? engine.resumeRecording() : engine.pauseRecording()
                        }
                    } label: {
                        Label(engine.state == .paused ? "Weiter" : "Pause",
                              systemImage: engine.state == .paused ? "play.fill" : "pause.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(engine.state == .paused ? .green : .orange)
                    .glassEffectID("main", in: glassNS)

                    Button {
                        showStopDialog = true
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("stop", in: glassNS)
                }
            }
        }
    }

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let recording = engine.isRecording
        let avg = engine.movingTime > 0 ? engine.distance / engine.movingTime : 0
        return LazyVGrid(columns: columns, spacing: 12) {
            if recording {
                StatTile(title: engine.autoPaused ? "Zeit · Auto-Pause" : "Zeit",
                         value: Fmt.duration(engine.elapsed), symbol: "timer", tint: colors[1])
                StatTile(title: "Strecke", value: unit.formatDistance(engine.distance),
                         symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: colors[1])
                StatTile(title: "Ø Geschwindigkeit", value: unit.formatSpeed(avg), symbol: "speedometer", tint: colors[1])
                StatTile(title: "Max (Fahrt)", value: unit.formatSpeed(engine.maxSpeed), symbol: "flame.fill", tint: .orange)
                if engine.activity == .running || engine.activity == .walking {
                    StatTile(title: "Pace", value: unit.formatPace(engine.speed), symbol: "figure.run", tint: colors[1])
                }
                StatTile(title: "Höhenmeter", value: "↑\(Int(engine.elevationGain)) ↓\(Int(engine.elevationLoss))",
                         symbol: "mountain.2.fill", tint: colors[1])
            }
            StatTile(title: "Spitze (Sitzung)", value: unit.formatSpeed(engine.sessionMax), symbol: "bolt.fill", tint: .yellow)
            StatTile(title: "Höhe", value: Fmt.altitude(engine.location.altitude), symbol: "arrow.up.and.down", tint: .cyan)
            StatTile(title: "Richtung", value: Fmt.heading(engine.location.course >= 0 && engine.speed > 1 ? engine.location.course : engine.location.heading),
                     symbol: "location.north.line.fill", tint: .mint)
            StatTile(title: "G-Kraft", value: String(format: "%.2f g", engine.motion.gForce), symbol: "waveform.path.ecg", tint: .pink)
        }
    }

    private var indoorCard: some View {
        let v = engine.visual
        let src = engine.speedSource
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Messquelle", systemImage: "scope")
                    .font(.headline)
                Spacer()
                Label(src.title, systemImage: src.symbol)
                    .font(.footnote.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassEffect(.regular.tint((src.isIndoor ? Color.cyan : Color.green).opacity(0.35)), in: .capsule)
                    .contentTransition(.symbolEffect(.replace))
            }
            HStack(spacing: 8) {
                sourcePill(.gps, active: src == .gps, detail: engine.gpsIsGood ? "gut" : "schwach")
                sourcePill(VisualOdometry.hasLiDAR ? .lidar : .visual,
                           active: src == .visual || src == .lidar,
                           detail: v.isRunning ? v.trackingText : "bereit")
                sourcePill(.pedometer, active: src == .pedometer,
                           detail: engine.motion.stepCadence > 0 ? String(format: "%.0f Schr./min", engine.motion.stepCadence * 60) : "\(engine.motion.steps) Schritte")
            }
            if v.isRunning {
                HStack(spacing: 16) {
                    metric("Kamera-Tempo", unit.formatSpeed(v.speed))
                    metric("Kamera-Strecke", unit.formatDistance(v.distance))
                    if let d = v.distanceAhead { metric("Abstand vorn", String(format: "%.2f m", d)) }
                }
                if !v.room.isEmpty {
                    Text(roomSummary(v.room))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(VisualOdometry.isSupported
                     ? "Drinnen schaltet Tacho automatisch auf Kamera\(VisualOdometry.hasLiDAR ? " + LiDAR" : "")-Tracking bzw. Schrittzähler um. Halte die Kamera frei für beste Genauigkeit."
                     : "Drinnen nutzt Tacho den Schrittzähler.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if VisualOdometry.isSupported {
                Button {
                    showIndoor = true
                } label: {
                    Label(VisualOdometry.hasLiDAR ? "Kamera- & LiDAR-Ansicht" : "Kamera-Ansicht", systemImage: "camera.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .animation(.smooth, value: src)
    }

    private func sourcePill(_ s: SpeedSource, active: Bool, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: s.symbol).font(.headline)
            Text(s == .lidar ? "LiDAR" : s.title).font(.caption2.weight(.bold)).lineLimit(1)
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundStyle(active ? Color.white : Color.secondary)
        .glassEffect(active ? .regular.tint(colors[1].opacity(0.45)) : .regular, in: .rect(cornerRadius: 16))
    }

    private func roomSummary(_ r: VisualOdometry.RoomInfo) -> String {
        var parts = RoomItem.items(for: r).map { "\($0.count) \($0.title)" }
        if r.floorArea > 0 { parts.append(String(format: "≈ %.0f m² Boden", r.floorArea)) }
        if let h = r.roomHeight { parts.append(String(format: "%.1f m hoch", h)) }
        if r.meshSegments > 0 { parts.append("\(r.meshSegments) Scan-Segmente") }
        return "Raum erkannt: " + parts.joined(separator: " · ")
    }

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Umgebung & Raum", systemImage: "building.columns.fill")
                .font(.headline)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GPS-Signal").font(.caption).foregroundStyle(.secondary)
                    SignalBars(quality: engine.place.signalQuality, color: colors[1])
                    Text(engine.location.horizontalAccuracy >= 0
                         ? String(format: "± %.0f m", engine.location.horizontalAccuracy) : "–")
                        .font(.caption.monospacedDigit())
                }
                Divider().frame(height: 50)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Etage").font(.caption).foregroundStyle(.secondary)
                    Text(engine.motion.barometerAvailable ? floorText : "–")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                    Text(String(format: "%+.1f m", engine.motion.relativeAltitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 50)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Luftdruck").font(.caption).foregroundStyle(.secondary)
                    Text(engine.motion.pressureKPa.map { String(format: "%.0f", $0 * 10) } ?? "–")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("hPa").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Image(systemName: engine.place.surroundings.symbol)
                Text(surroundingsHint).font(.footnote)
                Spacer()
                Button("Etage 0") { engine.motion.recalibrateFloor() }
                    .buttonStyle(.glass)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var floorText: String {
        let f = engine.floor
        return f == 0 ? "EG" : (f > 0 ? "\(f). OG" : "\(-f). UG")
    }

    private var surroundingsHint: String {
        switch engine.place.surroundings {
        case .openSky: "Beste Messgenauigkeit draußen."
        case .partial: "Gebäude oder Bäume schirmen teilweise ab."
        case .indoor: "Du bist vermutlich drinnen, in einem Zug oder Tunnel."
        case .noSignal: "Kein Fix – geh nach draußen oder ans Fenster."
        }
    }

    private var detectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bewegungserkennung", systemImage: "sparkles")
                .font(.headline)
            Text(engine.manualActivity != nil ? "Manuell festgelegt: \(engine.activity.title)" : engine.detected.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                metric("Erschütterung", String(format: "%.3f g", engine.motion.vibration))
                metric("Rhythmus", String(format: "%.1f Hz", engine.motion.cadence))
                metric("Sicherheit", "\(Int(engine.detected.confidence * 100)) %")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
        }
    }
}

struct SignalBars: View {
    var quality: Double
    var color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Double(i) < quality * 5 ? color : Color.white.opacity(0.15))
                    .frame(width: 6, height: 6 + Double(i) * 4)
            }
        }
        .animation(.smooth, value: quality)
    }
}

/// Vollbild-HUD für die Windschutzscheibe.
struct HUDScreen: View {
    @Environment(TachoEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh
    @State private var mirrored = true
    var color: Color

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            HUDView(value: unit.convert(engine.speed), unitLabel: unit.label, color: color, mirrored: mirrored)
            HStack {
                Button { mirrored.toggle() } label: {
                    Label("Spiegeln", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .buttonStyle(.glass)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
            }
            .padding()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
