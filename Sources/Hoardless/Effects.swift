import SwiftUI

/// Slowly drifting lime and teal glows behind everything (the web prototype's "aurora").
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Blob {
        let color: Color
        let center: CGPoint   // unit coordinates
        let radius: CGFloat   // fraction of the window's larger side
        let drift: CGSize     // unit coordinates
        let period: Double    // seconds per full cycle
    }

    private let blobs = [
        Blob(color: Color(hex: 0x7fb51f), center: CGPoint(x: 0.25, y: 0.30), radius: 0.55, drift: CGSize(width: 0.12, height: 0.08), period: 9),
        Blob(color: Color(hex: 0x1a9a8f), center: CGPoint(x: 0.80, y: 0.45), radius: 0.50, drift: CGSize(width: -0.13, height: 0.06), period: 11),
        Blob(color: Color(hex: 0x5c8a14), center: CGPoint(x: 0.50, y: 0.95), radius: 0.45, drift: CGSize(width: 0.08, height: -0.09), period: 13),
        Blob(color: Color(hex: 0xbeeb50).opacity(0.7), center: CGPoint(x: 0.50, y: 0.45), radius: 0.28, drift: CGSize(width: 0.03, height: 0.03), period: 3.5),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let side = max(size.width, size.height)
                gc.blendMode = .screen
                for blob in blobs {
                    let phase = sin(t / blob.period * 2 * .pi)
                    let c = CGPoint(x: (blob.center.x + blob.drift.width * phase) * size.width,
                                    y: (blob.center.y + blob.drift.height * phase) * size.height)
                    let r = blob.radius * side * (1 + 0.12 * phase)
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    gc.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [blob.color, blob.color.opacity(0)]), center: c, startRadius: 0, endRadius: r))
                }
            }
            .blur(radius: 50)
        }
        .background(Theme.ink)
        .ignoresSafeArea()
    }
}

/// Frosted glass panel that tilts toward the pointer, with a soft highlight following it.
struct GlassCard: ViewModifier {
    var tint: Color?
    var lit = true
    @State private var hover: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let p = hover ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let dx = (p.x / max(geo.size.width, 1)) - 0.5
            let dy = (p.y / max(geo.size.height, 1)) - 0.5
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(
                        colors: [(lit ? tint : nil)?.opacity(0.55) ?? .white.opacity(0.16),
                                 (lit ? tint : nil)?.opacity(0.12) ?? .white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .animation(.easeOut(duration: 0.35), value: lit)
                    if hover != nil {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RadialGradient(
                            colors: [.white.opacity(0.14), .clear], center: UnitPoint(x: dx + 0.5, y: dy + 0.5),
                            startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.6))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                .rotation3DEffect(.degrees(reduceMotion || hover == nil ? 0 : Double(dx) * 10), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(reduceMotion || hover == nil ? 0 : Double(-dy) * 8), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .animation(.easeOut(duration: 0.18), value: hover)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hover = point
                    case .ended: hover = nil
                    }
                }
        }
    }
}

extension View {
    func glassCard(tint: Color? = nil, lit: Bool = true) -> some View { modifier(GlassCard(tint: tint, lit: lit)) }

    /// Gentle up-and-down bob; faster when `busy`.
    func floating(busy: Bool = false) -> some View { modifier(Floating(busy: busy)) }
}

struct Floating: ViewModifier {
    var busy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period = busy ? 0.7 : 3.0
            content
                .offset(y: reduceMotion ? 0 : -6 * sin(t / period * 2 * .pi))
                .rotationEffect(.degrees(reduceMotion || !busy ? 0 : 6 * sin(t / period * 2 * .pi + .pi / 2)))
        }
    }
}

/// A byte count that rolls up to its value instead of jumping.
struct CountingBytes: View, Animatable {
    var bytes: Double
    var animatableData: Double {
        get { bytes }
        set { bytes = newValue }
    }

    var body: some View {
        Text(Bytes.text(Int64(bytes))).monospacedDigit()
    }
}
