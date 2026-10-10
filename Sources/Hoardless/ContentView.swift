import HoardlessCore
import SwiftUI

/// Window root: the sidebar, and the page it selects.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        NavigationSplitView {
            Sidebar(t: t)
                .navigationSplitViewColumnWidth(min: 264, ideal: 276, max: 320)
        } detail: {
            ZStack {
                PageBackground(screen: model.screen)
                Group {
                    if let error = model.loadError {
                        Text("\(t.loadFailed): \(error)").foregroundStyle(.red)
                    } else {
                        switch model.screen {
                        case .overview: OverviewView().readableColumn(maxHeight: 920)
                        case .category(let c): CategoryPage(category: c).readableColumn()
                        case .duplicates: DuplicatesView().readableColumn()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                            .help(t.goBack).accessibilityLabel(t.goBack)
                            .disabled(model.backStack.isEmpty)
                            .keyboardShortcut("[", modifiers: .command)
                        Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                            .help(t.goForward).accessibilityLabel(t.goForward)
                            .disabled(model.forwardStack.isEmpty)
                            .keyboardShortcut("]", modifiers: .command)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if model.phase == .done, model.screen != .overview {
                        Button(t.rescan) { model.toggleScan() }.disabled(model.working)
                    }
                }
            }
            .navigationTitle(title)
            // No grey bar: the page's own background runs up behind the title and the Back / Forward buttons.
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .preferredColorScheme(.dark)
    }

    private var title: String {
        switch model.screen {
        case .overview: return t.overview
        case .category(let c): return t.category(c)
        case .duplicates: return t.dupTitle
        }
    }
}

/// The overview keeps the drifting aurora; other pages get a calm wash of their own color at the top.
extension View {
    /// Keeps a page at a comfortable width (and the overview at a comfortable height) in a big window, centred,
    /// while the background still fills the window.
    func readableColumn(maxHeight: CGFloat = .infinity) -> some View {
        frame(maxWidth: 1160, maxHeight: maxHeight).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PageBackground: View {
    let screen: AppModel.Screen

    var body: some View {
        switch screen {
        case .overview:
            AuroraBackground()
        case .category(let c):
            tinted(Theme.tint(c))
        case .duplicates:
            tinted(Theme.duplicates)
        }
    }

    private func tinted(_ color: Color) -> some View {
        LinearGradient(colors: [color.opacity(0.22), Theme.ink.opacity(0.0)], startPoint: .top, endPoint: .center)
            .background(Color(hex: 0x0e100c))
            .ignoresSafeArea()
    }
}

// MARK: sidebar

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        List {
            row(.overview, label: t.overview, trailing: model.phase == .done ? Bytes.text(model.totalBytes) : nil) {
                Image(systemName: "sparkles").foregroundStyle(Theme.lime).font(.system(size: 15, weight: .semibold))
            }
            Section(t.sectionSpace) {
                ForEach([Rule.Category.videoEditors, .aiModels, .packageCache, .devTools], id: \.self) { c in
                    row(.category(c), label: t.category(c), trailing: trailing(c)) {
                        Art.image(Theme.icon(c)).resizable().scaledToFit()
                    }
                }
            }
            Section(t.sectionTools) {
                row(.duplicates, label: t.dupTitle, trailing: dups.phase == .done ? Bytes.text(dups.totalWasted) : nil) {
                    Art.image("icon-duplicates").resizable().scaledToFit()
                }
            }
        }
        .listStyle(.sidebar)
        // The mockup's dark green-black instead of the system's grey sidebar.
        .scrollContentBackground(.hidden)
        .background(Color(hex: 0x171c12).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 22)
                    Text(t.settings)
                    Spacer()
                    Text("⌘,").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(SidebarRowStyle(selected: false))
            .foregroundStyle(Theme.paper.opacity(0.85))
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
    }

    private func trailing(_ c: Rule.Category) -> String? {
        guard model.phase != .idle, let s = model.summaries[c], s.isComplete else { return nil }
        if s.bytes == 0, s.waitingForPermission { return t.notChecked }
        return Bytes.text(s.bytes)
    }

    /// A row drawn by hand so the selection uses the brand's green, not the system accent color.
    private func row(_ screen: AppModel.Screen, label: String, trailing: String?, @ViewBuilder icon: () -> some View) -> some View {
        let selected = model.screen == screen
        return Button { model.show(screen) } label: {
            HStack(spacing: 10) {
                icon().frame(width: 22, height: 22)
                Text(label).fontWeight(selected ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing).font(.caption).monospacedDigit()
                        .foregroundStyle(selected ? Theme.limeLight : Theme.paper.opacity(0.6))
                }
            }
        }
        .buttonStyle(SidebarRowStyle(selected: selected))
        .foregroundStyle(Theme.paper)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Sidebar row look: brand green when selected, a soft light wash on hover so it reads as clickable, a bit more
/// while pressed.
private struct SidebarRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var fill: Color {
            if selected { return Color(hex: 0x4f7a12).opacity(0.85) }
            if configuration.isPressed { return .white.opacity(0.14) }
            return hovering ? .white.opacity(0.08) : .clear
        }
    }
}

// MARK: shared page header

/// Big icon, title, size and one line about the page, as on every module page.
struct PageHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let bytes: Int64?
    let about: String

    var body: some View {
        HStack(spacing: 24) {
            Art.image(icon).resizable().scaledToFit().frame(width: 104, height: 104)
                .shadow(color: tint.opacity(0.4), radius: 22, y: 12)
                .floating()
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.paper)
                if let bytes {
                    CountingBytes(bytes: Double(bytes)).font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.paper)
                        .animation(.easeOut(duration: 0.5), value: bytes)
                }
                Text(about).font(.callout).foregroundStyle(Theme.paper.opacity(0.78))
                    .lineLimit(3).frame(maxWidth: 560, alignment: .leading)
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
    }
}

// MARK: category page

private struct CategoryPage: View {
    @EnvironmentObject private var model: AppModel
    let category: Rule.Category
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        let mine = model.results.filter { $0.rule.category == category }
        let present = mine.filter { $0.isPresent && !waitsForPermission($0) }.sorted { $0.bytes > $1.bytes }
        let waiting = mine.filter(waitsForPermission)
        let absent = mine.filter { !$0.isPresent }
        let largest = max(present.map(\.bytes).max() ?? 1, 1)
        let summary = model.summaries[category]

        VStack(alignment: .leading, spacing: 0) {
            PageHeader(icon: Theme.icon(category), tint: Theme.tint(category), title: t.category(category),
                       bytes: model.phase == .idle ? nil : summary?.bytes, about: t.categoryAbout(category))
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(present) { RuleCard(result: $0, largest: largest, tint: Theme.tint(category), t: t) }
                    if !waiting.isEmpty { PermissionRow(results: waiting, t: t) }
                    if !absent.isEmpty {
                        Text("\(t.notFound): \(absent.map(\.rule.app).joined(separator: " · "))")
                            .font(.caption).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    if mine.isEmpty || (present.isEmpty && model.phase == .idle) {
                        Text(t.scanFirst).foregroundStyle(Theme.dim).padding(.top, 20)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollContentBackground(.hidden)
            ActionBar(category: category, t: t)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
        .sheet(item: $model.pending) { ConfirmSheet(action: $0, t: t) }
    }

    private func waitsForPermission(_ r: RuleResult) -> Bool {
        r.bytes == 0 && r.locations.contains { r.states[$0.id] == .needsPermission }
    }
}

private struct RuleCard: View {
    @EnvironmentObject private var model: AppModel
    let result: RuleResult
    let largest: Int64
    let tint: Color
    let t: Strings
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if model.couldAct(result) {
                    Toggle(isOn: Binding(get: { model.isSelected(result) }, set: { _ in model.toggle(result) })) { EmptyView() }
                        .toggleStyle(.checkbox).labelsHidden()
                        .disabled(model.busy)
                        .accessibilityLabel(result.rule.title.text(chinese: t.chinese))
                } else {
                    Image(systemName: result.rule.commandOnly == true ? "terminal" : "lock")
                        .foregroundStyle(result.rule.commandOnly == true ? Theme.info : Theme.dim)
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(result.rule.title.text(chinese: t.chinese)).font(.body.weight(.semibold)).foregroundStyle(Theme.paper)
                            .lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(barColor)
                                .frame(width: max(4, geo.size.width * CGFloat(Double(result.bytes) / Double(largest))))
                        }
                    }
                    .frame(height: 6)
                }
                SafetyBadge(rule: result.rule, t: t)
                Text(Bytes.text(result.bytes)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.paper)
                    .frame(minWidth: 76, alignment: .trailing)
                Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(Theme.dim)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.whatTheyAre)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(result.rule.explain.text(chinese: t.chinese))
                        .foregroundStyle(Theme.paper.opacity(0.85))
                    ForEach(result.locations) { LocationRow(location: $0, result: result, state: result.states[$0.id] ?? .notScanned, t: t) }
                    ForEach(result.rejected, id: \.self) { r in
                        Text(t.rejected(r)).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.leading, 30)
                .transition(.opacity)
            }
            if let cleanup = result.rule.officialCleanup { CleanupBox(cleanup: cleanup, t: t).padding(.leading, 30) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(hex: 0x191d14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }

    private var subtitle: String {
        result.locations.count == 1 ? result.locations[0].display : t.locationsCount(result.locations.count)
    }

    private var barColor: Color {
        switch result.rule.safety {
        case .protected: return Theme.paper.opacity(0.35)
        default: return result.rule.commandOnly == true ? Theme.info : tint
        }
    }
}

private struct LocationRow: View {
    @EnvironmentObject private var model: AppModel
    let location: Location
    let result: RuleResult
    let state: LocationState
    let t: Strings

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
                Button(t.checkHere) { Task { await model.measure(location, ruleID: result.id) } }.help(t.permissionHelp)
            case .measured:
                Button(t.reveal) { model.reveal(location) }.buttonStyle(.borderless)
            default:
                EmptyView()
            }
        }
    }
}

/// Rules whose only locations wait for the user's permission: one quiet row, one button.
private struct PermissionRow: View {
    @EnvironmentObject private var model: AppModel
    let results: [RuleResult]
    let t: Strings

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock").foregroundStyle(Theme.dim).frame(width: 16)
            Text(results.map { $0.rule.title.text(chinese: t.chinese) }.joined(separator: " · ") + t.colon + t.permissionRow)
                .font(.callout).foregroundStyle(Theme.paper.opacity(0.75)).lineLimit(3)
            Spacer()
            Button(t.allowAndCheck) {
                Task {
                    for r in results {
                        for loc in r.locations where r.states[loc.id] == .needsPermission { await model.measure(loc, ruleID: r.id) }
                    }
                }
            }
            .help(t.permissionHelp)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// Bottom bar of a category page: what is ticked and the two actions, or the result with Undo.
private struct ActionBar: View {
    @EnvironmentObject private var model: AppModel
    let category: Rule.Category
    let t: Strings

    var body: some View {
        let items = model.selectedItems(in: category)
        let bytes = items.reduce(Int64(0)) { $0 + $1.bytes }
        let ruleCount = Set(items.map(\.result.id)).count
        HStack(spacing: 12) {
            if model.working {
                ProgressView().controlSize(.small)
                Text(t.working).foregroundStyle(Theme.dim)
                Spacer()
            } else if let error = model.actionError {
                Text(error).foregroundStyle(Color(hex: 0xff6b5e)).font(.callout).lineLimit(3).textSelection(.enabled)
                Spacer()
                Button(t.gotIt) { model.actionError = nil }
            } else if !model.lastRecords.isEmpty, items.isEmpty {
                let records = model.lastRecords
                let size = Bytes.text(records.reduce(0) { $0 + $1.bytes })
                Text(records.first?.kind == .moved ? t.batchMoved(records.count, size) : t.batchTrashed(records.count, size))
                    .foregroundStyle(Theme.paper)
                Spacer()
                Button(t.undo) { model.undoLast() }.disabled(model.phase == .scanning)
                Button(t.gotIt) { model.dismissRecords() }
            } else {
                if items.isEmpty {
                    Text(t.pickHint).foregroundStyle(Theme.dim)
                } else {
                    Text(t.selectedSummary(ruleCount, Bytes.text(bytes))).foregroundStyle(Theme.paper)
                    Text(t.undoable).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Button(t.moveButton) { model.askMove(items) }
                    .buttonStyle(PillButton(prominent: false))
                    .disabled(items.isEmpty || model.phase == .scanning)
                Button(t.trashButton) { model.askTrash(items) }
                    .buttonStyle(PillButton(prominent: true))
                    .disabled(items.isEmpty || model.phase == .scanning)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color(hex: 0x1e2418).opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: -4)
    }
}

/// Names every path and the total before anything changes (CLAUDE.md rule 1).
private struct ConfirmSheet: View {
    @EnvironmentObject private var model: AppModel
    let action: AppModel.PendingAction
    let t: Strings

    var body: some View {
        let items = action.items
        let size = Bytes.text(items.reduce(0) { $0 + $1.bytes })
        let rules = items.reduce(into: [RuleResult]()) { acc, item in if !acc.contains(where: { $0.id == item.result.id }) { acc.append(item.result) } }
        VStack(alignment: .leading, spacing: 12) {
            switch action {
            case .trash: Text(t.batchTrashTitle(rules.count, items.count, size)).font(.headline)
            case .move: Text(t.batchMoveTitle(rules.count, items.count, size)).font(.headline)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.location.url.path).font(.callout.monospaced()).textSelection(.enabled)
                                if case .move(_, let folder) = action {
                                    Text("→ \(model.plannedTarget(item, in: folder)?.path ?? "—")")
                                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            Spacer()
                            Text(Bytes.text(item.bytes)).font(.callout).monospacedDigit()
                        }
                    }
                }
                .padding(10)
            }
            .frame(minHeight: 80, maxHeight: 220)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Text(t.whatTheyAre).font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rules) { r in
                        Text(r.rule.title.text(chinese: t.chinese) + t.colon + r.rule.explain.text(chinese: t.chinese))
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxHeight: 140)
            switch action {
            case .trash: Text(t.batchTrashNote).font(.callout).fixedSize(horizontal: false, vertical: true)
            case .move(_, let folder):
                Text(t.batchMoveNote).font(.callout).fixedSize(horizontal: false, vertical: true)
                if model.isInICloud(folder) {
                    Text(t.moveToICloudWarning(size)).font(.callout).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(t.cancel, role: .cancel) { model.pending = nil }.keyboardShortcut(.cancelAction)
                switch action {
                case .trash: Button(t.trashButton, role: .destructive) { model.confirmPending() }
                case .move: Button(t.chooseFolder) { model.confirmPending() }
                }
            }
        }
        .padding(20)
        .frame(width: 640)
    }
}

struct PillButton: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: prominent ? .bold : .semibold))
            .padding(.horizontal, prominent ? 22 : 18)
            .frame(height: 38)
            .foregroundStyle(prominent ? Theme.ink : Theme.paper)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0xc7ef5a), Color(hex: 0x8fbe22)], startPoint: .top, endPoint: .bottom))
                } else {
                    Capsule().fill(.white.opacity(0.08)).overlay(Capsule().strokeBorder(.white.opacity(0.2)))
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
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
                Text(cleanup.command).font(.callout.monospaced()).foregroundStyle(Color(hex: 0x9fd0ff)).textSelection(.enabled)
                Spacer()
                Button(t.copy) { model.copy(cleanup.command) }
            }
            Text(t.cleanupWarning).font(.caption).foregroundStyle(Theme.warn)
            if let url = URL(string: cleanup.source) { Link(t.cleanupSource, destination: url).font(.caption) }
        }
        .padding(10)
        .background(Theme.info.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
