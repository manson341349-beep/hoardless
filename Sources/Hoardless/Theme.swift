import AppKit
import HoardlessCore
import SwiftUI

/// Colors follow XinYuAi's palette (ink, warm paper, lime used sparingly). Same values as the web prototype.
enum Theme {
    static let ink = Color(hex: 0x0a0a0a)
    static let paper = Color(hex: 0xECEAE2)
    static let dim = Color(hex: 0x928f86)
    static let lime = Color(hex: 0xa3d233)
    static let limeLight = Color(hex: 0xd6f58a)
    static let warn = Color(hex: 0xffc95e)
    static let info = Color(hex: 0x5eb0ff)

    static func tint(_ category: Rule.Category) -> Color {
        switch category {
        case .videoEditors: return Color(hex: 0xffaa5a)
        case .aiModels: return Color(hex: 0xbeeb50)
        case .packageCache: return Color(hex: 0x5eb0ff)
        case .devTools: return Color(hex: 0x9687eb)
        }
    }

    static func icon(_ category: Rule.Category) -> String {
        switch category {
        case .videoEditors: return "icon-video-editors"
        case .aiModels: return "icon-ai-models"
        case .packageCache: return "icon-package-cache"
        case .devTools: return "icon-dev-tools"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// Artwork in Resources/Art (see the LICENSE.md there): Contents/Resources/Art in a built .app, else the package bundle.
enum Art {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> Image {
        if let cached = cache[name] { return Image(nsImage: cached) }
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Art")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Art")
        guard let url, let image = NSImage(contentsOf: url) else { return Image(systemName: "questionmark.square.dashed") }
        cache[name] = image
        return Image(nsImage: image)
    }
}

enum Bytes {
    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
