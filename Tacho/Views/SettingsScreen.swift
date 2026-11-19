import SwiftUI
import SwiftData
import CoreLocation
import CoreMotion

struct SettingsScreen: View {
    @Environment(TachoEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh
    @AppStorage(Pref.gaugeStyle) private var style: GaugeStyle = .analog
    @AppStorage(Pref.speedLimit) private var limitKmh: Double = 0
    @AppStorage(Pref.autoPause) private var autoPause = true
    @AppStorage(Pref.keepAwake) private var keepAwake = true
    @AppStorage(Pref.theme) private var theme: Theme = .activity
    @AppStorage(Pref.haptics) private var haptics = true
    @AppStorage(Pref.indoorMode) private var indoorMode: IndoorMode = .auto
    @AppStorage(Pref.floorHeight) private var floorHeight: Double = 3.0
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Anzeige") {
                    Picker("Einheit", selection: $unit) {
                        ForEach(SpeedUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Tacho-Stil", selection: $style) {
                        ForEach(GaugeStyle.allCases.filter { $0 != .hud }) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Farbschema", selection: $theme) {
                        ForEach(Theme.allCases) { t in
                            HStack {
                                Text(t.title)
                                Spacer()
                                ForEach(0..<3, id: \.self) { i in
                                    Circle().fill(t.colors(for: engine.activity)[i]).frame(width: 10, height: 10)
                                }
                            }
                            .tag(t)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Toggle("Bildschirm anlassen", isOn: $keepAwake)
                }

                Section {
                    Toggle("Geschwindigkeitswarnung", isOn: Binding(
                        get: { limitKmh > 0 },
                        set: { limitKmh = $0 ? 50 : 0 }))
                    if limitKmh > 0 {
                        Stepper(value: $limitKmh, in: 5...300, step: 5) {
                            HStack {
                                Text("Grenze")
                                Spacer()
                                Text(unit.formatSpeed(limitKmh / 3.6, decimals: 0)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    Toggle("Haptisches Feedback", isOn: $haptics)
                } header: {
                    Text("Warnungen")
                } footer: {
                    Text("Bei Überschreitung färbt sich das Tacho rot und das iPhone vibriert.")
                }

                Section {
                    Toggle("Auto-Pause im Stand", isOn: $autoPause)
                    Button("Hintergrund-Aufzeichnung erlauben") { engine.location.requestAlways() }
                    LabeledContent("Standortzugriff", value: authText)
                } header: {
                    Text("Aufzeichnung")
                } footer: {
                    Text("Mit „Immer“-Zugriff läuft die Aufzeichnung auch bei gesperrtem Bildschirm zuverlässig weiter.")
                }

                Section {
                    Picker("Kamera-Tracking", selection: $indoorMode) {
                        ForEach(IndoorMode.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Kamera-Tracking", value: VisualOdometry.isSupported ? "unterstützt" : "nicht unterstützt")
                    LabeledContent("LiDAR-Scanner", value: VisualOdometry.hasLiDAR ? "vorhanden" : "nicht vorhanden")
                    LabeledContent("Schrittzähler", value: engine.motion.pedometerAvailable ? "verfügbar" : "nicht verfügbar")
                    LabeledContent("Aktive Quelle", value: engine.speedSource.title)
                } header: {
                    Text("Innenräume")
                } footer: {
                    Text("Ist das GPS drinnen zu ungenau, misst Tacho über Kamera (und LiDAR) oder den Schrittzähler weiter und setzt deine Route auf der Karte fort. In Auto, Zug & Co. bleibt GPS maßgeblich, weil die Kamera dort nur das Fahrzeuginnere sieht. Kamera-Tracking braucht freie Sicht und etwas mehr Akku.")
                }

                Section {
                    Stepper(value: $floorHeight, in: 2.4...5.0, step: 0.1) {
                        LabeledContent("Etagenhöhe", value: String(format: "%.1f m", floorHeight))
                    }
                    LabeledContent("Aktuelle Etage", value: FloorFormat.text(engine.floor))
                    LabeledContent("Referenz", value: engine.floorEstimator.source.title)
                    LabeledContent("Gemerkte Orte", value: "\(engine.floorEstimator.savedPlaceCount)")
                    Button("Gemerkte Straßenhöhen löschen", role: .destructive) {
                        engine.floorEstimator.forgetSavedPlaces()
                    }
                } header: {
                    Text("Etagen")
                } footer: {
                    Text("Tacho lernt die Straßenhöhe automatisch, sobald du draußen bist, und merkt sie sich pro Ort. Altbauten haben oft 3,5 m, Neubauten etwa 2,8–3 m pro Etage.")
                }

                Section("Live-Sensoren") {
                    LabeledContent("Drinnen-Wahrscheinlichkeit", value: "\(Int(engine.indoor.probability * 100)) %")
                    LabeledContent("Satelliten-Fixes", value: engine.location.gnssRatio.map { "\(Int($0 * 100)) %" } ?? "–")
                    LabeledContent("Fix-Rate", value: String(format: "%.1f Hz", engine.location.fixRate))
                    LabeledContent("GPS-Genauigkeit", value: engine.location.horizontalAccuracy >= 0 ? String(format: "± %.0f m", engine.location.horizontalAccuracy) : "–")
                    LabeledContent("Höhengenauigkeit", value: engine.location.verticalAccuracy >= 0 ? String(format: "± %.0f m", engine.location.verticalAccuracy) : "–")
                    LabeledContent("Indoor-Karten-Etage", value: engine.location.floorLevel.map { "\($0)" } ?? "–")
                    LabeledContent("Barometer-Höhe", value: engine.motion.absoluteAltitude.map { String(format: "%.1f m NN", $0) } ?? String(format: "%+.1f m (relativ)", engine.motion.relativeAltitude))
                    LabeledContent("Vertikal", value: String(format: "%+.2f m/s", engine.motion.verticalSpeed))
                    LabeledContent("Stockwerke (Schrittzähler)", value: engine.motion.floorCountingAvailable ? "↑\(engine.motion.floorsAscended) ↓\(engine.motion.floorsDescended)" : "–")
                    LabeledContent("Magnetfeld", value: engine.motion.magneticField.map { String(format: "%.0f µT ± %.1f", $0, engine.motion.magneticVariance) } ?? "nicht kalibriert")
                    LabeledContent("Gier-Rate (30 s max)", value: String(format: "%.2f rad/s", engine.motion.maxYawRate30s))
                    LabeledContent("Kamera-Helligkeit", value: engine.visual.lightIntensity.map { String(format: "%.0f lm", $0) } ?? "–")
                    LabeledContent("Rohgeschwindigkeit", value: engine.location.rawSpeed >= 0 ? unit.formatSpeed(engine.location.rawSpeed) : "ungültig")
                    LabeledContent("Umgebung", value: engine.place.surroundings.title)
                    LabeledContent("Barometer", value: engine.motion.barometerAvailable ? "verfügbar" : "nicht verfügbar")
                    LabeledContent("Spitzen-G-Kraft", value: String(format: "%.2f g", engine.motion.peakGForce))
                    LabeledContent("iOS-Bewegung", value: systemActivityText)
                }

                Section {
                    Button("Alle Fahrten löschen", role: .destructive) { confirmWipe = true }
                } header: {
                    Text("Daten")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tacho").font(.headline)
                        Text("Geschwindigkeit, Routen und Bewegungserkennung – Gehen, Rennen, Fahrrad, E-Scooter, Auto, Zug und Flugzeug. Die Erkennung kombiniert iOS-Bewegungsdaten, GPS-Profil und Vibrationsanalyse; tippe im Tacho auf das Aktivitäts-Abzeichen, um sie manuell festzulegen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(color: engine.activity.color, intensity: 0.5))
            .navigationTitle("Einstellungen")
            .confirmationDialog("Wirklich alle Fahrten löschen?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Alles löschen", role: .destructive) {
                    try? context.delete(model: Trip.self)
                    try? context.delete(model: SprintResult.self)
                    try? context.save()
                }
            }
        }
    }

    private var authText: String {
        switch engine.location.authorization {
        case .authorizedAlways: "Immer"
        case .authorizedWhenInUse: "Beim Verwenden"
        case .denied: "Abgelehnt"
        case .restricted: "Eingeschränkt"
        default: "Nicht festgelegt"
        }
    }

    private var systemActivityText: String {
        guard let a = engine.motion.systemActivity else { return "–" }
        var parts: [String] = []
        if a.stationary { parts.append("Stand") }
        if a.walking { parts.append("Gehen") }
        if a.running { parts.append("Laufen") }
        if a.cycling { parts.append("Rad") }
        if a.automotive { parts.append("Fahrzeug") }
        if parts.isEmpty { parts.append("Unbekannt") }
        let conf = ["niedrig", "mittel", "hoch"][a.confidence.rawValue]
        return parts.joined(separator: ", ") + " (\(conf))"
    }
}
