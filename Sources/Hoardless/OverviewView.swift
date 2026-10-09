import HoardlessCore
import SwiftUI

/// Overview: the squirrel, the total, how it splits by category, and where to go next.
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dups: DuplicateModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            ZStack {
                Art.image(mascot)
                    .resizable().scaledToFit()
                    .frame(width: 168, height: 168)
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 16)
                    .floating(busy: model.phase == .scanning)
                    .id(mascot)
                    .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity),
                                            removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            .animation(.spring(duration: 0.4, bounce: 0.35), value: mascot)

            Group {
                switch model.phase {
                case .idle:
                    Text(t.idleTitle).font(.system(size: 40, weight: .bold))
                    Text(t.idleHint).font(.callout).foregroundStyle(Theme.paper.opacity(0.78)).padding(.top, 8)
                case .scanning:
                    Text(model.currentApp.map(t.lookingAt) ?? t.scanning).font(.callout.weight(.semibold)).foregroundStyle(Theme.limeLight)
                    CountingBytes(bytes: Double(model.totalBytes)).font(.system(size: 60, weight: .bold))
                        .animation(.easeOut(duration: 0.3), value: model.totalBytes)
                case .done:
                    Text(t.scanDone).font(.callout.weight(.semibold)).foregroundStyle(Theme.limeLight)
                    CountingBytes(bytes: Double(model.totalBytes)).font(.system(size: 60, weight: .bold))
                        .animation(.easeOut(duration: 0.65), value: model.totalBytes)
                    Text(t.doneParagraph(actionable: Bytes.text(model.actionableBytes), protected: Bytes.text(model.protectedBytes)))
                        .font(.callout).foregroundStyle(Theme.paper.opacity(0.82))
                        .multilineTextAlignment(.center).frame(maxWidth: 560).padding(.top, 8)
                }
            }
            .foregroundStyle(Theme.paper)
            .multilineTextAlignment(.center)
            .transaction { $0.animation = nil }

            if model.phase == .done {
                SpaceBar(t: t).padding(.top, 24)
            }

            Group {
                if model.phase == .done {
                    HStack(spacing: 12) {
                        if let target = bestCategory {
                            Button(t.reviewAction(Bytes.text(model.actionableBytes))) { model.show(.category(target)) }
                                .buttonStyle(PillButton(prominent: true)).controlSize(.large)
                        }
                        Button(t.rescan) { model.toggleScan() }.buttonStyle(PillButton(prominent: false))
                            .disabled(model.working)
                    }
                } else {
                    ScanOrb()
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 16)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(cardCategories, id: \.self) { CategoryCard(category: $0, t: t) }
                DuplicatesCard(t: t)
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 28)
    }

    private var mascot: String {
        switch model.phase {
        case .idle: return "mascot-idle"
        case .scanning: return "mascot-searching"
        case .done: return "mascot-done"
        }
    }

    /// The three categories using the most space (all four before a scan finishes, minus developer tools).
    private var cardCategories: [Rule.Category] {
        let all: [Rule.Category] = [.videoEditors, .aiModels, .packageCache, .devTools]
        guard model.phase == .done else { return Array(all.prefix(3)) }
        return Array(all.sorted { (model.summaries[$0]?.bytes ?? 0) > (model.summaries[$1]?.bytes ?? 0) }.prefix(3))
    }

    /// Where "review what you can act on" goes: the category with the most space to act on.
    private var bestCategory: Rule.Category? {
        model.summaries.filter { $0.value.actionableBytes > 0 }.max { $0.value.actionableBytes < $1.value.actionableBytes }?.key
    }
}

/// One bar split by category, with a legend under it.
private struct SpaceBar: View {
    @EnvironmentObject private var model: AppModel
    let t: Strings

    var body: some View {
        let parts = [Rule.Category.videoEditors, .aiModels, .packageCache, .devTools]
            .map { ($0, model.summaries[$0]?.bytes ?? 0) }.filter { $0.1 > 0 }
        let total = max(parts.reduce(Int64(0)) { $0 + $1.1 }, 1)
        VStack(spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { c, bytes in
                        Rectangle().fill(Theme.tint(c)).frame(width: max(3, geo.size.width * CGFloat(Double(bytes) / Double(total)) - 2))
                    }
                }
            }
            .frame(width: 600, height: 14)
            .background(.white.opacity(0.08))
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel(parts.map { "\(t.category($0.0)) \(Bytes.text($0.1))" }.joined(separator: ", "))
            HStack(spacing: 20) {
                ForEach(parts, id: \.0) { c, bytes in
                    HStack(spacing: 7) {
                        Circle().fill(Theme.tint(c)).frame(width: 9, height: 9)
                        Text("\(t.category(c)) \(Bytes.text(bytes))").font(.callout).foregroundStyle(Theme.paper.opacity(0.8))
                    }
                }
            }
        }
    }
}

private struct CategoryCard: View {
    @EnvironmentObject private var model: AppModel
    let category: Rule.Category
    let t: Strings

    var body: some View {
        let summary = model.summaries[category]
        Button { model.show(.category(category)) } label: {
            HStack(spacing: 12) {
                Art.image(Theme.icon(category)).resizable().scaledToFit().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.category(category)).font(.caption).foregroundStyle(Theme.paper.opacity(0.75)).lineLimit(1)
                    if model.phase == .done, let s = summary, s.isComplete {
                        Text(s.bytes == 0 && s.waitingForPermission ? t.notChecked : Bytes.text(s.bytes))
                            .font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(Theme.paper)
                        line(s).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Text("—").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.dim)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(tint: Theme.tint(category), lit: model.phase == .done)
        .frame(height: 78)
    }

    @ViewBuilder private func line(_ s: CategorySummary) -> some View {
        if s.reviewBytes + s.safeBytes > 0 {
            Text(t.canAct(Bytes.text(s.reviewBytes + s.safeBytes))).foregroundStyle(Theme.warn)
        } else if s.commandOnlyBytes > 0 {
            Text(t.commandOnlyAmount(Bytes.text(s.commandOnlyBytes))).foregroundStyle(Color(hex: 0x9fd0ff))
        } else {
            Text(t.viewOnlyAll).foregroundStyle(Theme.dim)
        }
    }
}

private struct DuplicatesCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        Button { model.show(.duplicates) } label: {
            HStack(spacing: 12) {
                Art.image("icon-duplicates").resizable().scaledToFit().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.dupTitle).font(.caption).foregroundStyle(Theme.paper.opacity(0.75))
                    Text(dups.phase == .done ? Bytes.text(dups.totalWasted) : t.dupCardAction)
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.paper)
                    Text(dups.phase == .done ? t.dupTileFound(dups.visibleGroups.count) : t.dupCardHint)
                        .font(.caption2).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(tint: Theme.duplicates, lit: dups.phase == .done)
        .frame(height: 78)
    }
}

struct Tag: View {
    let text: String
    let color: Color
    let fill: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// The big round Scan / Stop button shown before and during a scan.
private struct ScanOrb: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        let scanning = model.phase == .scanning
        Button(action: model.toggleScan) {
            ZStack {
                TimelineView(.animation(paused: !scanning || reduceMotion)) { context in
                    Circle()
                        .strokeBorder(AngularGradient(colors: [Theme.lime.opacity(0), Theme.lime, Theme.limeLight, Theme.lime.opacity(0)],
                                                      center: .center), lineWidth: 4)
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate / 0.7 * 360))
                        .opacity(scanning ? 1 : 0)
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xf4ffd6), Color(hex: 0xc7ef5a), Theme.lime, Color(hex: 0x5f8a12)],
                                         center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: 60))
                    .padding(9)
                    .shadow(color: Theme.lime.opacity(scanning ? 0.85 : 0.55), radius: scanning ? 30 : 20, y: 10)
                Text(scanning ? t.stop : t.scan)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 104, height: 104)
            .contentShape(Circle())
        }
        .buttonStyle(OrbPress())
        .keyboardShortcut(.defaultAction)
        .disabled(model.working && model.phase != .scanning)
    }
}

private struct OrbPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}
