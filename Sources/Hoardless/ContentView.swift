import HoardlessCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.loadError {
                Text("\(t.loadFailed): \(error)").foregroundStyle(.red).padding()
                Spacer()
            } else {
                list
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isScanning ? t.scanning : t.found(Self.size(model.totalBytes)))
                    .font(.title2.weight(.semibold))
                Text(t.readOnlyNotice).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
            Button(t.rescan) { Task { await model.rescan() } }
                .disabled(model.isScanning)
        }
        .padding(16)
    }

    private var list: some View {
        let present = model.results.filter { $0.isPresent }
        let absent = model.results.filter { !$0.isPresent }
        return List {
            ForEach(Rule.Category.allCases, id: \.self) { category in
                let rows = present.filter { $0.rule.category == category }.sorted { $0.bytes > $1.bytes }
                if !rows.isEmpty {
                    Section(t.category(category)) {
                        ForEach(rows) { RuleRow(result: $0, t: t) }
                    }
                }
            }
            if !absent.isEmpty && !model.isScanning {
                Section(t.notFound) {
                    Text(absent.map(\.rule.app).uniqued().joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var model: AppModel
    let result: RuleResult
    let t: Strings
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(result.rule.explain.text(chinese: t.chinese))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(result.locations) { LocationRow(location: $0, ruleID: result.id, state: result.states[$0.id] ?? .notScanned, t: t) }
                ForEach(result.rejected, id: \.self) { r in
                    Text("\(r.display) — \(t.notUsed): \(r.reason)").font(.caption).foregroundStyle(.secondary)
                }
                if let cleanup = result.rule.officialCleanup { CleanupBox(cleanup: cleanup, t: t) }
            }
            .padding(.vertical, 6)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.rule.title.text(chinese: t.chinese)).font(.body.weight(.medium))
                    Text(result.rule.app).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ContentView.size(result.bytes)).monospacedDigit()
                SafetyBadge(rule: result.rule, t: t)
            }
        }
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
            Text(location.display).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(t.state(state)).font(.caption).foregroundStyle(.secondary)
            switch state {
            case .needsPermission:
                Button(t.checkHere) { Task { await model.measure(location, ruleID: ruleID) } }
                    .help(t.permissionHelp)
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
            Text(t.cleanupTitle).font(.caption.weight(.semibold))
            HStack {
                Text(cleanup.command).font(.callout.monospaced()).textSelection(.enabled)
                Spacer()
                Button(t.copy) { model.copy(cleanup.command) }
            }
            Text(t.cleanupWarning).font(.caption).foregroundStyle(.orange)
            if let url = URL(string: cleanup.source) { Link(t.cleanupSource, destination: url).font(.caption) }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SafetyBadge: View {
    let rule: Rule
    let t: Strings

    var body: some View {
        let (label, color): (String, Color) = switch rule.safety {
        case .safe: (t.safe, .green)
        case .review: (rule.commandOnly == true ? t.commandOnly : t.review, .orange)
        case .protected: (t.protected, .secondary)
        }
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
            .frame(minWidth: 72)
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
