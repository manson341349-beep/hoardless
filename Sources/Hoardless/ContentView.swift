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
            } else if model.showingDuplicates {
                DuplicatesView()
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            } else if let category = model.openCategory {
                CategoryDetail(category: category)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            } else {
                OverviewView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.35), value: model.openCategory)
        .animation(.spring(duration: 0.35), value: model.showingDuplicates)
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
            ActionBanner(t: t)
        }
        .padding(24)
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
                            titleVisibility: .visible, presenting: model.pending) { action in
            switch action {
            case .trash: Button(t.trashButton, role: .destructive) { model.confirmPending() }
            case .move: Button(t.chooseFolder) { model.confirmPending() }
            }
            Button(t.cancel, role: .cancel) { model.pending = nil }
        } message: { action in
            let explain = action.result.rule.explain.text(chinese: t.chinese)
            switch action {
            case .trash(let loc, _): Text(t.confirmTrashBody(path: loc.url.path, explain: explain))
            case .move(let loc, _, let dest):
                Text(t.confirmMoveBody(path: loc.url.path, destination: (model.plannedTarget(action) ?? dest).path, explain: explain))
            }
        }
    }

    private var dialogTitle: String {
        guard let action = model.pending else { return "" }
        let name = action.result.rule.title.text(chinese: t.chinese)
        let size = Bytes.text(action.result.states[action.location.id]?.bytes ?? 0)
        switch action {
        case .trash: return t.confirmTrashTitle(name, size)
        case .move: return t.confirmMoveTitle(name, size)
        }
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
                    ForEach(result.locations) { LocationRow(location: $0, result: result, state: result.states[$0.id] ?? .notScanned, t: t) }
                    ForEach(result.rejected, id: \.self) { r in
                        Text(t.rejected(r)).font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
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
    let result: RuleResult
    let state: LocationState
    let t: Strings
    private var ruleID: String { result.id }

    private var originNote: String? {
        switch location.origin {
        case .rulePath: return nil
        case .environment: return t.fromEnvironment
        case .appSetting: return t.fromAppSetting
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.display).font(.callout.monospaced()).foregroundStyle(Theme.paper.opacity(0.8))
                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                if let originNote { Text(originNote).font(.caption2).foregroundStyle(Theme.info) }
            }
            Spacer()
            Text(t.state(state)).font(.caption).foregroundStyle(Theme.dim)
            switch state {
            case .needsPermission:
                Button(t.checkHere) { Task { await model.measure(location, ruleID: ruleID) } }.help(t.permissionHelp)
            case .measured:
                Button(t.reveal) { model.reveal(location) }
                if model.working == location.id {
                    ProgressView().controlSize(.small)
                    Text(t.working).font(.caption).foregroundStyle(Theme.dim)
                } else if model.canAct(location, in: result) {
                    Button(t.moveButton) { model.askMove(location, in: result) }
                    Button(t.trashButton, role: .destructive) { model.askTrash(location, in: result) }
                }
            default:
                EmptyView()
            }
        }
    }
}

/// Bottom note after an action, with Undo; or an error.
private struct ActionBanner: View {
    @EnvironmentObject private var model: AppModel
    let t: Strings

    var body: some View {
        if let error = model.actionError {
            note(error, color: Color(hex: 0xff6b5e)) { Button(t.gotIt) { model.actionError = nil } }
        } else if let record = model.lastRecord {
            let size = Bytes.text(record.bytes)
            let name = model.results.first(where: { $0.id == record.ruleID })?.rule.title.text(chinese: t.chinese) ?? record.title
            let text = record.kind == .trashed
                ? t.trashed(name, size)
                : t.moved(name, size, record.now.deletingLastPathComponent().path)
            note(text, color: Theme.paper) {
                Button(t.undo) { model.undoLast() }.disabled(model.working != nil)
                Button(t.gotIt) { model.dismissRecord() }
            }
        }
    }

    private func note(_ text: String, color: Color, @ViewBuilder buttons: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(text).foregroundStyle(color).lineLimit(2)
            Spacer()
            buttons()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
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
