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

                Section("Live-Sensoren") {
                    LabeledContent("GPS-Genauigkeit", value: engine.location.horizontalAccuracy >= 0 ? String(format: "± %.0f m", engine.location.horizontalAccuracy) : "–")
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
