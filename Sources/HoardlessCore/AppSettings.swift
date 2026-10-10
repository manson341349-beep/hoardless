import Foundation
import SQLite3

/// Reads the folder locations an app recorded in its own settings (rules' `app_settings`).
/// Read-only: settings files are opened for reading, databases with SQLITE_OPEN_READONLY.
public enum AppSettings {
    /// Settings files larger than this are not read (they would not be settings).
    static let maxTextSize = 1_000_000

    /// Every path the settings entry names, with `subpath` added. Empty if the file is missing or unreadable.
    public static func paths(for setting: Rule.AppSetting, policy: PathPolicy, withSubpath: Bool = true) -> [URL] {
        guard let file = policy.expand(setting.file),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              attrs[.type] as? FileAttributeType == .typeRegular else { return [] }
        let values: [String]
        switch setting.format {
        case .pointer: values = text(file).map { [$0.trimmingCharacters(in: .whitespacesAndNewlines)] } ?? []
        case .ini: values = text(file).flatMap { ini($0, key: setting.key) }.map { [$0] } ?? []
        case .json: values = json(file, key: setting.key)
        case .sqlite: values = sqlite(file, key: setting.key).map { [$0] } ?? []
        }
        return values.compactMap { value in
            let expanded = (value as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { return nil }
            var url = URL(fileURLWithPath: expanded)
            if withSubpath, let sub = setting.subpath { url.appendPathComponent(sub) }
            return url
        }
    }

    private static func text(_ file: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
              size <= maxTextSize, let data = try? Data(contentsOf: file) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `Section.key` in an INI file; the value with surrounding quotes removed.
    static func ini(_ text: String, key: String?) -> String? {
        guard let key, let dot = key.firstIndex(of: ".") else { return nil }
        let section = String(key[..<dot]), name = String(key[key.index(after: dot)...])
        var current = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            } else if current == section, let eq = line.firstIndex(where: { $0 == "=" || $0 == ":" }),
                      line[..<eq].trimmingCharacters(in: .whitespaces) == name {
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// A top-level key holding a path or a list of paths.
    private static func json(_ file: URL, key: String?) -> [String] {
        guard let key, let text = text(file), let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        switch object[key] {
        case let value as String: return value.isEmpty ? [] : [value]
        case let values as [Any]: return values.compactMap { $0 as? String }.filter { !$0.isEmpty }
        default: return []
        }
    }

    /// `table.column` of the first row, read-only. Names are checked so a rule cannot inject SQL.
    static func sqlite(_ file: URL, key: String?) -> String? {
        guard let key, key.range(of: #"^[a-z_]+\.[a-z_]+$"#, options: .regularExpression) != nil else { return nil }
        let parts = key.split(separator: ".")
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 500)
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT \(parts[1]) FROM \(parts[0]) LIMIT 1", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) else { return nil }
        let value = String(cString: raw)
        return value.isEmpty ? nil : value
    }
}
