import SwiftUI

/// Startanimation im Stil eines Auto-Kombiinstruments: Der Leuchtbogen zündet,
/// die Nadel schnellt zum Anschlag und fällt zurück – dann öffnet sich die App.
struct SplashView: View {
    var onFinished: () -> Void

    @State private var arc: Double = 0          // 0…1 Leuchtbogen
    @State private var needle: Double = 0       // 0…1 Nadelstellung
    @State private var ticksOn = false
    @State private var titleOn = false
    @State private var glow = false
    @State private var exiting = false
    @State private var bump = 0

    private let colors: [Color] = [
        Color(red: 0.16, green: 0.94, blue: 0.67),
        Color(red: 0.24, green: 0.59, blue: 1.0),
        Color(red: 1.0, green: 0.24, blue: 0.55)
    ]
    private let start = 135.0
    private let sweep = 270.0

    var body: some View {
        ZStack {
            background

            VStack(spacing: 34) {
                dial
                    .frame(width: 250, height: 250)

                VStack(spacing: 8) {
                    Text("TACHO")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .tracking(titleOn ? 14 : 2)
                        .foregroundStyle(LinearGradient(colors: [.white, colors[1]], startPoint: .top, endPoint: .bottom))
                    Text("Jede Bewegung. Jede Geschwindigkeit.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .opacity(titleOn ? 1 : 0)
                .offset(y: titleOn ? 0 : 16)
                .blur(radius: titleOn ? 0 : 8)
            }
            .scaleEffect(exiting ? 1.5 : 1)
            .opacity(exiting ? 0 : 1)
            .blur(radius: exiting ? 24 : 0)
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: bump)
        .task { await run() }
    }

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [colors[1].opacity(glow ? 0.45 : 0.0), .clear],
                           center: .center, startRadius: 10, endRadius: glow ? 520 : 120)
            RadialGradient(colors: [colors[2].opacity(glow ? 0.25 : 0.0), .clear],
                           center: .init(x: 0.8, y: 0.2), startRadius: 0, endRadius: 400)
        }
        .ignoresSafeArea()
        .opacity(exiting ? 0 : 1)
    }

    private var dial: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .circle)
                    .opacity(ticksOn ? 1 : 0)

                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(start))
                    .padding(16)

                Circle()
                    .trim(from: 0, to: sweep / 360 * arc)
                    .stroke(AngularGradient(colors: colors, center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(sweep)),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(start))
                    .padding(16)
                    .shadow(color: colors[1].opacity(0.9), radius: glow ? 22 : 0)

                ForEach(0...10, id: \.self) { i in
                    let a = start + sweep * Double(i) / 10
                    Capsule()
                        .fill(.white.opacity(i % 5 == 0 ? 0.95 : 0.5))
                        .frame(width: i % 5 == 0 ? 4 : 2.5, height: i % 5 == 0 ? 16 : 10)
                        .offset(y: -(r - 42))
                        .rotationEffect(.degrees(a + 90))
                        .opacity(ticksOn ? 1 : 0)
                        .scaleEffect(ticksOn ? 1 : 0.6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(i) * 0.03), value: ticksOn)
                }

                // Nadel
                Capsule()
                    .fill(LinearGradient(colors: [colors[2], .white], startPoint: .bottom, endPoint: .top))
                    .frame(width: 5, height: r * 0.78)
                    .offset(y: -r * 0.33)
                    .shadow(color: colors[2], radius: 10)
                    .rotationEffect(.degrees(start + sweep * needle + 90))

                Circle()
                    .fill(Color(red: 0.08, green: 0.07, blue: 0.16))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))

                CountingText(value: needle * 300)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: r * 0.5)
                    .opacity(ticksOn ? 1 : 0)
            }
            .frame(width: size, height: size)
        }
    }

    @MainActor
    private func run() async {
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeOut(duration: 0.35)) { ticksOn = true }
        withAnimation(.easeInOut(duration: 0.8)) { glow = true }

        // Hochdrehen bis zum Anschlag
        withAnimation(.easeIn(duration: 0.55)) { arc = 1 }
        withAnimation(.timingCurve(0.5, 0, 0.3, 1, duration: 0.6)) { needle = 1 }
        try? await Task.sleep(for: .milliseconds(620))
        bump += 1

        // Zurückfallen mit leichtem Nachfedern
        withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) { needle = 0 }
        withAnimation(.easeInOut(duration: 0.6)) { arc = 0.0 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.15)) { titleOn = true }
        try? await Task.sleep(for: .milliseconds(1050))

        withAnimation(.easeIn(duration: 0.45)) { exiting = true }
        try? await Task.sleep(for: .milliseconds(420))
        onFinished()
    }
}

/// Zählt die Zahl während der Animation mit (statt nur Start- und Endwert zu zeigen).
private struct CountingText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(max(0, value).rounded()))")
            .monospacedDigit()
    }
}
