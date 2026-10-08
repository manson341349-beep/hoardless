import HoardlessCore
import SwiftUI

/// Window root: drifting background, then the overview or one category's list.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        ZStack {
            AuroraBackground()
            if let error = model.loadError {
                Text("\(t.loadFailed): \(error)").foregroundStyle(.red)
            } else if let category = model.openCategory {
                CategoryDetail(category: category)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            } else {
                OverviewView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.35), value: model.openCategory)
        .overlay {
            Picker(t.language, selection: $model.language) {
                Text(t.languageAuto).tag(AppModel.Language.system)
                Text("中文").tag(AppModel.Language.chinese)
                Text("English").tag(AppModel.Language.english)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .help(t.language)
            .padding(.top, 5)
            .padding(.trailing, 16)
            // Sits in the hidden title bar, next to the window buttons, so it never covers a card.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }
}

private struct CategoryDetail: View {
    @EnvironmentObject private var model: AppModel
    let category: Rule.Category
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        let present = model.results.filter { $0.rule.category == category && $0.isPresent }.sorted { $0.bytes > $1.bytes }
        let absent = model.results.filter { $0.rule.category == category && !$0.isPresent }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button { model.openCategory = nil } label: {
                    Label(t.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                Art.image(Theme.icon(category)).resizable().scaledToFit().frame(width: 44, height: 44)
                Text(t.category(category)).font(.title2.weight(.semibold)).foregroundStyle(Theme.paper)
                Spacer()
                Text(Bytes.text(present.reduce(0) { $0 + $1.bytes })).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.paper)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(present) { RuleRow(result: $0, t: t) }
                    if !absent.isEmpty {
                        Text("\(t.notFound): \(absent.map(\.rule.app).joined(separator: " · "))")
                            .font(.callout).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    if present.isEmpty && model.phase == .idle {
                        Text(t.scanFirst).foregroundStyle(Theme.dim).padding(.top, 20)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            Text(t.readOnlyNotice).font(.caption).foregroundStyle(Theme.dim)
        }
        .padding(24)
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var model: AppModel
    let result: RuleResult
    let t: Strings
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(Theme.dim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.rule.title.text(chinese: t.chinese)).font(.body.weight(.medium)).foregroundStyle(Theme.paper)
                        Text(result.rule.app).font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    if result.bytes == 0, result.locations.contains(where: { result.states[$0.id] == .needsPermission }) {
                        Text(t.notChecked).foregroundStyle(Theme.dim)
                    } else {
                        Text(Bytes.text(result.bytes)).monospacedDigit().foregroundStyle(Theme.paper)
                    }
                    SafetyBadge(rule: result.rule, t: t)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(result.rule.explain.text(chinese: t.chinese))
                        .foregroundStyle(Theme.paper.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(result.locations) { LocationRow(location: $0, ruleID: result.id, state: result.states[$0.id] ?? .notScanned, t: t) }
                    ForEach(result.rejected, id: \.self) { r in
                        Text("\(r.display) — \(t.notUsed): \(r.reason)").font(.caption).foregroundStyle(Theme.dim)
                    }
                    if let cleanup = result.rule.officialCleanup { CleanupBox(cleanup: cleanup, t: t) }
                }
                .padding(.leading, 26)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

private struct LocationRow: View {
    @EnvironmentObject private var model: AppModel
    let location: Location
    let ruleID: String
    let state: LocationState
    let t: Strings

    var body: some View {
        HStack(spacing: 8) {
            Text(location.display).font(.callout.monospaced()).foregroundStyle(Theme.paper.opacity(0.8))
                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(t.state(state)).font(.caption).foregroundStyle(Theme.dim)
            switch state {
            case .needsPermission:
                Button(t.checkHere) { Task { await model.measure(location, ruleID: ruleID) } }.help(t.permissionHelp)
            case .measured:
                Button(t.reveal) { model.reveal(location) }
            default:
                EmptyView()
            }
        }
    }
}

private struct CleanupBox: View {
    @EnvironmentObject private var model: AppModel
    let cleanup: Rule.Cleanup
    let t: Strings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t.cleanupTitle).font(.caption.weight(.semibold)).foregroundStyle(Theme.paper)
            HStack {
                Text(cleanup.command).font(.callout.monospaced()).foregroundStyle(Theme.limeLight).textSelection(.enabled)
                Spacer()
                Button(t.copy) { model.copy(cleanup.command) }
            }
            Text(t.cleanupWarning).font(.caption).foregroundStyle(Theme.warn)
            if let url = URL(string: cleanup.source) { Link(t.cleanupSource, destination: url).font(.caption) }
        }
        .padding(10)
        .background(Theme.ink.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SafetyBadge: View {
    let rule: Rule
    let t: Strings

    var body: some View {
        let (label, color): (String, Color) = switch rule.safety {
        case .safe: (t.safe, Theme.lime)
        case .review: (rule.commandOnly == true ? t.commandOnly : t.review, rule.commandOnly == true ? Theme.info : Theme.warn)
        case .protected: (t.protected, Theme.paper)
        }
        Tag(text: label, color: color, fill: color.opacity(0.16)).frame(minWidth: 72)
    }
}
