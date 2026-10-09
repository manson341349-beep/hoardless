import AppKit
import SwiftUI

/// The Settings window (⌘,): General, Finding, About.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dups: DuplicateModel
    private var t: Strings { Strings(chinese: model.chinese) }

    var body: some View {
        TabView {
            GeneralPane(t: t).tabItem { Label(t.general, systemImage: "gearshape") }
            FindingPane(t: t).tabItem { Label(t.searchTab, systemImage: "magnifyingglass") }
            AboutPane(t: t).tabItem { Label(t.about, systemImage: "info.circle") }
        }
        .frame(width: 560)
        .preferredColorScheme(.dark)
    }
}

private struct GeneralPane: View {
    @EnvironmentObject private var model: AppModel
    let t: Strings

    var body: some View {
        Form {
            Section {
                Picker(t.language, selection: $model.language) {
                    Text(t.languageAuto).tag(AppModel.Language.system)
                    Text("中文").tag(AppModel.Language.chinese)
                    Text("English").tag(AppModel.Language.english)
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $model.autoScan) {
                    Text(t.autoScan)
                    Text(t.autoScanNote)
                }
            }
            Section {
                // Shown so the promise is visible; it is not a setting and can't be switched off.
                Toggle(isOn: .constant(true)) {
                    Text(t.askFirst)
                    Text(t.askFirstNote)
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct FindingPane: View {
    @EnvironmentObject private var dups: DuplicateModel
    let t: Strings

    var body: some View {
        Form {
            Section {
                Picker(selection: $dups.minimumSize) {
                    ForEach(DuplicateModel.minimumSizeChoices, id: \.self) { Text(Bytes.text($0)).tag($0) }
                } label: {
                    Text(t.dupMinimum)
                    Text(t.dupMinimumNote)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 160)
    }
}

private struct AboutPane: View {
    let t: Strings

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Hoardless").font(.title2.weight(.bold))
            Text("\(t.version) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .foregroundStyle(.secondary)
            Text(t.licenseNote).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
            if let url = URL(string: "https://github.com/manson341349-beep/hoardless") {
                Link(t.sourceCode, destination: url)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }
}
