import HoardlessCore
import SwiftUI

/// Pick folders, search, then tick copies to move to the Trash. Nothing is ticked until the user does it.
struct DuplicatesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dups: DuplicateModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button { model.showingDuplicates = false } label: {
                    Label(t.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                DuplicatesIcon(size: 44)
                Text(t.dupTitle).font(.title2.weight(.semibold)).foregroundStyle(Theme.paper)
                Spacer()
                if dups.phase == .done {
                    Text(Bytes.text(dups.totalWasted)).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.paper)
                }
            }
            switch dups.phase {
            case .setup: SetupPanel(t: t)
            case .searching: SearchingPanel(t: t)
            case .done: ResultsPanel(t: t)
            }
            if let problem = dups.problem {
                HStack(alignment: .top) {
                    Text(problem).foregroundStyle(Color(hex: 0xff6b5e)).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(t.gotIt) { dups.problem = nil }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(24)
    }
}

struct DuplicatesIcon: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "square.on.square")
            .font(.system(size: size * 0.62, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [Theme.limeLight, Theme.lime], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
    }
}

private struct SetupPanel: View {
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t.dupSearchIn).font(.headline).foregroundStyle(Theme.paper)
            VStack(alignment: .leading, spacing: 8) {
                ForEach($dups.folders) { $folder in
                    HStack(spacing: 10) {
                        Toggle(isOn: $folder.on) {
                            Text(dups.display(folder.url)).font(.callout.monospaced()).foregroundStyle(Theme.paper.opacity(0.9))
                        }
                        .toggleStyle(.checkbox)
                        if folder.suggested { Tag(text: t.dupSuggested, color: Theme.dim, fill: Theme.paper.opacity(0.08)) }
                        Spacer()
                        if !folder.suggested { Button(t.dupRemove) { dups.removeFolder(folder) }.buttonStyle(.borderless) }
                    }
                }
                Button(t.dupAdd) { dups.addFolders(t) }.padding(.top, 4)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
            Text(t.dupHowItWorks).font(.callout).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Spacer()
                Button(t.dupStart) { dups.start(chinese: t.chinese) }
                    .buttonStyle(.borderedProminent).tint(Theme.lime).foregroundStyle(Theme.ink)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!dups.canStart)
                Spacer()
            }
        }
    }
}

private struct SearchingPanel: View {
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Art.image("mascot-searching").resizable().scaledToFit().frame(width: 150, height: 150).floating(busy: true)
            if dups.bytesTotal > 0 {
                ProgressView(value: Double(dups.bytesDone), total: Double(max(dups.bytesTotal, 1))).frame(maxWidth: 420).tint(Theme.lime)
                Text(t.dupComparing(dups.bytesDone, dups.bytesTotal)).foregroundStyle(Theme.paper.opacity(0.85)).monospacedDigit()
            } else {
                ProgressView().controlSize(.small)
                Text(t.dupListing(dups.filesSeen)).foregroundStyle(Theme.paper.opacity(0.85)).monospacedDigit()
            }
            Button(t.stop) { dups.stop() }.buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ResultsPanel: View {
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        let groups = dups.visibleGroups
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(groups.isEmpty ? t.dupNone : t.dupSummary(groups.count, dups.totalWasted))
                    .font(.headline).foregroundStyle(Theme.paper)
                Spacer()
                Button(t.dupKeepOneAll) { dups.keepOneEverywhere() }.disabled(dups.working || groups.isEmpty)
                Button(t.dupClear) { dups.clearSelection() }.disabled(dups.working || dups.selection.isEmpty)
                Button(t.dupNewSearch) { dups.backToSetup() }.disabled(dups.working)
            }
            HStack(spacing: 14) {
                if dups.viewOnlyGroupCount > 0 {
                    Toggle(t.dupShowViewOnly(dups.viewOnlyGroupCount), isOn: $dups.showViewOnlyGroups).toggleStyle(.checkbox)
                        .foregroundStyle(Theme.dim)
                }
                if let note = t.dupSkipped(dups.skipped) { Text(note).font(.caption).foregroundStyle(Theme.dim) }
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(groups) { GroupCard(group: $0, t: t) }
                }
            }
            .scrollContentBackground(.hidden)
            BottomBar(t: t)
        }
        .sheet(isPresented: $dups.confirming) { ConfirmSheet(t: t) }
    }
}

/// Names every picked path and the total before anything moves (CLAUDE.md rule 1).
private struct ConfirmSheet: View {
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        let files = dups.selectedFiles
        VStack(alignment: .leading, spacing: 12) {
            Text(t.dupConfirmTitle(files.count, dups.selectedBytes)).font(.headline)
            Text(t.dupConfirmKeep).font(.callout)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(files) { f in
                        Text(dups.display(f.url)).font(.callout.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 80, maxHeight: 260)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            let inICloud = files.filter(\.inICloud).count
            if inICloud > 0 { Text(t.dupICloudWarning(inICloud)).font(.callout).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true) }
            Text(t.dupConfirmTrashNote).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(t.cancel, role: .cancel) { dups.confirming = false }.keyboardShortcut(.cancelAction)
                Button(t.trashButton, role: .destructive) { dups.confirmTrash(t) }
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

private struct GroupCard: View {
    @EnvironmentObject private var dups: DuplicateModel
    let group: DuplicateGroup
    let t: Strings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(group.files.first?.url.lastPathComponent ?? "").font(.body.weight(.medium)).foregroundStyle(Theme.paper)
                    .lineLimit(1).truncationMode(.middle)
                Text(t.dupCopies(group.size, group.files.count)).font(.caption).foregroundStyle(Theme.dim)
                Spacer()
                if group.wasted > 0 { Text(t.dupGroupWasted(group.wasted)).font(.callout).monospacedDigit().foregroundStyle(Theme.paper) }
                if group.files.contains(where: { $0.viewOnly == nil }) {
                    Button(t.dupKeepOne) { dups.keepOne(group) }.buttonStyle(.borderless).disabled(dups.working)
                }
            }
            ForEach(group.files) { FileRow(file: $0, group: group, t: t) }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

private struct FileRow: View {
    @EnvironmentObject private var dups: DuplicateModel
    let file: DuplicateFile
    let group: DuplicateGroup
    let t: Strings

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { dups.isSelected(file) }, set: { _ in dups.toggle(file, in: group) })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!dups.canToggle(file, in: group))
                .help(file.viewOnly.map(t.dupViewOnlyHelp) ?? (dups.canToggle(file, in: group) ? "" : t.dupLastCopy))
            VStack(alignment: .leading, spacing: 2) {
                Text(dups.display(file.url)).font(.callout.monospaced()).foregroundStyle(Theme.paper.opacity(file.viewOnly == nil ? 0.85 : 0.55))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(file.modified.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: t.chinese ? "zh_CN" : "en_US")))).font(.caption2).foregroundStyle(Theme.dim)
                    if file.viewOnly == nil, file.freeable < file.size / 2 {
                        Text(t.dupShares(file.freeable)).font(.caption2).foregroundStyle(Theme.info)
                    }
                }
            }
            Spacer()
            if let reason = file.viewOnly {
                Tag(text: t.dupViewOnlyTag(reason), color: Theme.paper.opacity(0.8), fill: Theme.paper.opacity(0.1)).help(t.dupViewOnlyHelp(reason))
            }
            Button(t.reveal) { dups.reveal(file) }.buttonStyle(.borderless).font(.caption)
        }
    }
}

private struct BottomBar: View {
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        HStack(spacing: 10) {
            if dups.working {
                ProgressView().controlSize(.small)
                Text(t.working).foregroundStyle(Theme.dim)
                Spacer()
            } else if !dups.lastRecords.isEmpty, dups.selection.isEmpty {
                Text(t.dupTrashed(dups.lastRecords.count, dups.lastRecords.reduce(0) { $0 + $1.bytes })).foregroundStyle(Theme.paper)
                Spacer()
                Button(t.undo) { dups.undo(t) }
                Button(t.gotIt) { dups.dismissRecords() }
            } else {
                Text(dups.selection.isEmpty ? t.dupNoneSelected : t.dupSelected(dups.selection.count, dups.selectedBytes))
                    .foregroundStyle(dups.selection.isEmpty ? Theme.dim : Theme.paper)
                Spacer()
                Button(t.trashButton, role: .destructive) { dups.confirming = true }
                    .disabled(dups.selection.isEmpty)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }
}
