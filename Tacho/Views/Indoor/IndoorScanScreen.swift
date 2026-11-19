import SwiftUI

/// Vollbild-Kameraansicht: Geschwindigkeit per Kamera/LiDAR und Raumerkennung live.
struct IndoorScanScreen: View {
    @Environment(TachoEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.unit) private var unit: SpeedUnit = .kmh
    @State private var showMesh = true
    @State private var wasRunning = false

    private var visual: VisualOdometry { engine.visual }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if VisualOdometry.isSupported {
                ARPreview(session: visual.session, showMesh: showMesh)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("Nicht unterstützt",
                                       systemImage: "camera.badge.ellipsis",
                                       description: Text("Dieses Gerät unterstützt kein Kamera-Tracking."))
            }

            // Fadenkreuz für den LiDAR-Abstand
            if let d = visual.distanceAhead {
                VStack(spacing: 6) {
                    Image(systemName: "plus.viewfinder")
                        .font(.system(size: 44, weight: .light))
                    Text(String(format: "%.2f m", d))
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                }
                .foregroundStyle(.white)
                .allowsHitTesting(false)
            }

            VStack(spacing: 12) {
                topBar
                Spacer()
                roomChips
                bottomPanel
            }
            .padding(16)
        }
        .statusBarHidden()
        .onAppear {
            wasRunning = visual.isRunning
            engine.setVisualTracking(true)
        }
        .onDisappear {
            // Nur stoppen, wenn wir es selbst gestartet haben; die Automatik übernimmt sonst wieder
            if !wasRunning { engine.setVisualTracking(false) } else { visual.startedManually = false }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Label(visual.trackingText, systemImage: visual.trackingOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(visual.trackingOK ? .green : .yellow)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
            Spacer()
            if VisualOdometry.hasLiDAR {
                Button {
                    withAnimation { showMesh.toggle() }
                } label: {
                    Image(systemName: showMesh ? "cube.transparent.fill" : "cube.transparent")
                        .font(.title3)
                        .padding(12)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .padding(12)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var roomChips: some View {
        let r = visual.room
        let items = RoomItem.items(for: r)
        if !items.isEmpty {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Label("\(item.count) \(item.title)", systemImage: item.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(.white)
        }
    }

    private var bottomPanel: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: visual.speed * 3.6 < 10 ? "%.1f" : "%.0f", unit.convert(visual.speed)))
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: visual.speed))
                Text(unit.label).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .animation(.snappy, value: visual.speed)

            Divider().frame(height: 70)

            VStack(alignment: .leading, spacing: 6) {
                row("ruler", "Strecke", unit.formatDistance(visual.distance))
                row("square.dashed", "Bodenfläche", visual.room.floorArea > 0 ? String(format: "%.1f m²", visual.room.floorArea) : "–")
                row("arrow.up.and.down", "Raumhöhe", visual.room.roomHeight.map { String(format: "%.2f m", $0) } ?? "–")
                row("building.2", "Etage", floorText)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private var floorText: String {
        FloorFormat.text(engine.floor)
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().fontWeight(.semibold)
        }
        .font(.caption)
    }
}

struct RoomItem: Identifiable {
    let title: String
    let symbol: String
    let count: Int
    var id: String { title }

    static func items(for r: VisualOdometry.RoomInfo) -> [RoomItem] {
        [
            RoomItem(title: "Wände", symbol: "rectangle.portrait.fill", count: r.walls),
            RoomItem(title: "Boden", symbol: "square.fill", count: r.floors),
            RoomItem(title: "Decke", symbol: "square.tophalf.filled", count: r.ceilings),
            RoomItem(title: "Türen", symbol: "door.left.hand.open", count: r.doors),
            RoomItem(title: "Fenster", symbol: "window.vertical.closed", count: r.windows),
            RoomItem(title: "Tische", symbol: "table.furniture.fill", count: r.tables),
            RoomItem(title: "Sitze", symbol: "chair.fill", count: r.seats)
        ].filter { $0.count > 0 }
    }
}
