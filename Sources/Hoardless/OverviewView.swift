import HoardlessCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        let summaries = model.summaries
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                HeroCard()
                CategoryTile(category: .videoEditors, summary: summaries[.videoEditors], wide: false)
                CategoryTile(category: .aiModels, summary: summaries[.aiModels], wide: false)
            }
            .frame(height: 320)
            GridRow {
                CategoryTile(category: .packageCache, summary: summaries[.packageCache], wide: true)
                CategoryTile(category: .devTools, summary: summaries[.devTools], wide: true)
                DuplicatesTile()
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 112)
        .overlay(alignment: .bottom) {
            ScanOrb().padding(.bottom, 14)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(t.readOnlyNotice).font(.caption).foregroundStyle(Theme.dim).padding(.trailing, 26).padding(.bottom, 16)
        }
    }
}

private struct HeroCard: View {
    @EnvironmentObject private var model: AppModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                switch model.phase {
                case .idle: Text(t.heroIdle)
                case .scanning: Text(t.heroScanning)
                case .done: CountingBytes(bytes: Double(model.totalBytes)).animation(.easeOut(duration: 0.65), value: model.totalBytes)
                }
            }
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(Theme.paper)
            .multilineTextAlignment(.center)
            .transaction { $0.animation = nil }

            ZStack {
                Art.image(mascot)
                    .resizable().scaledToFit()
                    .frame(width: 150, height: 150)
                    .floating(busy: model.phase == .scanning)
                    .id(mascot)
                    .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity),
                                            removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            .animation(.spring(duration: 0.4, bounce: 0.35), value: mascot)

            statusLine
                .font(.callout)
                .foregroundStyle(Theme.paper.opacity(0.78))
                .multilineTextAlignment(.center)
                .frame(minHeight: 36)
                .transaction { $0.animation = nil }
        }
        .padding(18)
        .glassCard(tint: Theme.lime, lit: model.phase == .done)
    }

    private var mascot: String {
        switch model.phase {
        case .idle: return "mascot-idle"
        case .scanning: return "mascot-searching"
        case .done: return "mascot-done"
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.phase {
        case .idle:
            Text(t.idleHint)
        case .scanning:
            Text(model.currentApp.map(t.lookingAt) ?? t.scanning)
        case .done:
            Text(t.doneSummary(actionable: Bytes.text(model.actionableBytes), protected: Bytes.text(model.protectedBytes)))
        }
    }
}

private struct CategoryTile: View {
    @EnvironmentObject private var model: AppModel
    let category: Rule.Category
    let summary: CategorySummary?
    let wide: Bool
    private var t: Strings { Strings(chinese: model.chinese) }

    private var lit: Bool {
        guard model.phase != .idle, let summary else { return false }
        return summary.isComplete
    }

    var body: some View {
        Button { model.openCategory = category } label: {
            Group {
                if wide {
                    HStack(spacing: 22) { icon(120); details }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t.category(category)).font(.headline).foregroundStyle(Theme.paper.opacity(0.88))
                        icon(130).frame(maxWidth: .infinity)
                        details
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(lit || model.phase == .idle ? 1 : 0.5)
        .glassCard(tint: Theme.tint(category), lit: lit)
        .disabled(model.phase == .scanning)
    }

    private func icon(_ size: CGFloat) -> some View {
        Art.image(Theme.icon(category))
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Theme.tint(category).opacity(0.45), radius: 18, y: 10)
            .floating()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if wide { Text(t.category(category)).font(.headline).foregroundStyle(Theme.paper.opacity(0.88)) }
            sizeLine.font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.paper)
            tags
        }
    }

    @ViewBuilder private var sizeLine: some View {
        if model.phase == .idle || !(summary?.isComplete ?? false) {
            Text("—").foregroundStyle(Theme.dim)
        } else if let summary, summary.bytes == 0, summary.waitingForPermission {
            Text(t.notChecked).foregroundStyle(Theme.dim)
        } else {
            CountingBytes(bytes: Double(summary?.bytes ?? 0)).animation(.easeOut(duration: 0.55), value: summary?.bytes)
        }
    }

    @ViewBuilder private var tags: some View {
        if lit, let s = summary {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { tagList(s) }
                VStack(alignment: .leading, spacing: 6) { tagList(s) }
            }
        }
    }

    @ViewBuilder private func tagList(_ s: CategorySummary) -> some View {
                if s.protectedBytes > 0 { Tag(text: "\(t.protected) \(Bytes.text(s.protectedBytes))", color: Theme.paper, fill: Theme.paper.opacity(0.14)) }
                if s.reviewBytes + s.safeBytes > 0 { Tag(text: "\(t.review) \(Bytes.text(s.reviewBytes + s.safeBytes))", color: Theme.warn, fill: Theme.warn.opacity(0.18)) }
                if s.commandOnlyBytes > 0 { Tag(text: "\(t.commandOnly) \(Bytes.text(s.commandOnlyBytes))", color: Theme.info, fill: Theme.info.opacity(0.18)) }
                if s.waitingForPermission && s.bytes == 0 { Tag(text: t.tapToCheck, color: Theme.paper.opacity(0.85), fill: Theme.paper.opacity(0.14)) }
    }
}

/// Entry to the duplicates screen. Works on its own, before or without a scan.
private struct DuplicatesTile: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dups: DuplicateModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        Button { model.showingDuplicates = true } label: {
            HStack(spacing: 22) {
                DuplicatesIcon(size: 96).shadow(color: Theme.lime.opacity(0.4), radius: 18, y: 10).floating()
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.dupTitle).font(.headline).foregroundStyle(Theme.paper.opacity(0.88))
                    if dups.phase == .done {
                        CountingBytes(bytes: Double(dups.totalWasted)).font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.paper)
                        Tag(text: t.dupTileFound(dups.visibleGroups.count), color: Theme.warn, fill: Theme.warn.opacity(0.18))
                    } else {
                        Text(t.dupTileHint).font(.callout).foregroundStyle(Theme.paper.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(tint: Theme.lime, lit: dups.phase == .done)
        .disabled(model.phase == .scanning)
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
                Text(scanning ? t.stop : (model.phase == .done ? t.rescan : t.scan))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 104, height: 104)
            .contentShape(Circle())
        }
        .buttonStyle(OrbPress())
        .keyboardShortcut(.defaultAction)
        .disabled(model.working != nil && model.phase != .scanning)
    }
}

private struct OrbPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}
