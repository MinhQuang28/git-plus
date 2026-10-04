import SwiftUI

/// VS Code–style file-type glyph: a short colored label for common languages ("TS", "JS", "{}"),
/// otherwise a tinted SF Symbol. Purely by file name/extension, no disk access.
struct FileTypeIcon: View {
    let path: String
    /// `.increased` inside a selected List row: tint colors would vanish on the accent highlight.
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.uiTextScale) private var scale

    var body: some View {
        let style = FileTypeStyle.for(path)
        Group {
            switch style.glyph {
            case .label(let text):
                Text(text)
                    .appFont(size: text.count > 2 ? 8 : 10, weight: .heavy, design: .rounded)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            case .symbol(let name):
                Image(systemName: name).appFont(size: 12, weight: .medium)
            }
        }
        .foregroundStyle(prominence == .increased ? .white : style.color)
        .frame(width: 18 * scale, height: 16 * scale)
        .accessibilityHidden(true)
    }
}

private struct FileTypeStyle {
    enum Glyph { case label(String), symbol(String) }
    let glyph: Glyph
    let color: Color

    private static func label(_ text: String, _ hex: UInt32) -> FileTypeStyle { .init(glyph: .label(text), color: rgb(hex)) }
    private static func symbol(_ name: String, _ hex: UInt32) -> FileTypeStyle { .init(glyph: .symbol(name), color: rgb(hex)) }
    /// Brand hue, adjusted per appearance so icons keep ~3:1 contrast: deep colors (LESS navy, C# purple)
    /// are lifted toward white on dark backgrounds, pale ones (JS yellow) darkened on light backgrounds.
    private static func rgb(_ hex: UInt32) -> Color {
        let c = [CGFloat((hex >> 16) & 0xff), CGFloat((hex >> 8) & 0xff), CGFloat(hex & 0xff)].map { $0 / 255 }
        let luminance = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        let lift = max(0, 0.5 - luminance), shade = max(0, luminance - 0.45)
        func color(_ f: (CGFloat) -> CGFloat) -> NSColor { NSColor(srgbRed: f(c[0]), green: f(c[1]), blue: f(c[2]), alpha: 1) }
        return Theme.dynamic(light: color { $0 * (1 - shade) }, dark: color { $0 + (1 - $0) * lift })
    }

    /// Exact file names win over extensions (`package.json`, `Dockerfile`, `.env.example`, …).
    private static let names: [String: FileTypeStyle] = [
        "package.json": label("npm", 0xcb3837), "package-lock.json": label("npm", 0xcb3837),
        "pnpm-lock.yaml": label("pn", 0xf9ad00), "yarn.lock": label("yarn", 0x2c8ebb),
        "dockerfile": symbol("shippingbox.fill", 0x2496ed), "makefile": symbol("hammer.fill", 0x8a8a8a),
        ".gitignore": symbol("arrow.triangle.branch", 0xf05032), ".gitattributes": symbol("arrow.triangle.branch", 0xf05032),
        ".gitlab-ci.yml": symbol("flame.fill", 0xfc6d26), "license": symbol("checkmark.seal.fill", 0xd8b64a),
        "package.swift": symbol("swift", 0xf05138), "podfile": symbol("shippingbox.fill", 0xe0464b),
    ]

    private static let extensions: [String: FileTypeStyle] = [
        "ts": label("TS", 0x3178c6), "tsx": label("TSX", 0x3178c6), "mts": label("TS", 0x3178c6), "cts": label("TS", 0x3178c6),
        "js": label("JS", 0xd8b64a), "jsx": label("JSX", 0x61dafb), "mjs": label("JS", 0xd8b64a), "cjs": label("JS", 0xd8b64a),
        "json": label("{}", 0xd8b64a), "jsonc": label("{}", 0xd8b64a),
        "swift": symbol("swift", 0xf05138), "py": label("PY", 0x3776ab), "rb": label("RB", 0xcc342d),
        "go": label("GO", 0x00add8), "rs": label("RS", 0xdea584), "java": label("J", 0xb07219), "kt": label("KT", 0xa97bff),
        "c": label("C", 0x5c6bc0), "h": label("H", 0x8a63d2), "cpp": label("C++", 0xf34b7d), "m": label("M", 0x438eff),
        "cs": label("C#", 0x68217a), "php": label("PHP", 0x777bb4), "dart": label("DT", 0x0175c2),
        "html": label("<>", 0xe34c26), "htm": label("<>", 0xe34c26), "vue": label("V", 0x41b883), "svelte": label("S", 0xff3e00),
        "liquid": label("{%", 0x7ab55c), "erb": label("<%", 0xcc342d),
        "css": label("#", 0x563d7c), "scss": label("#", 0xc6538c), "sass": label("#", 0xc6538c), "less": label("#", 0x1d365d),
        "md": label("M↓", 0x519aba), "mdx": label("M↓", 0xf9ac00), "txt": symbol("doc.plaintext", 0x8a8a8a),
        "yml": label("YML", 0xcb171e), "yaml": label("YML", 0xcb171e), "toml": label("TML", 0x9c4221),
        "xml": label("<>", 0xe37933), "plist": label("<>", 0xe37933), "graphql": symbol("hexagon", 0xe10098), "gql": symbol("hexagon", 0xe10098),
        "sql": symbol("cylinder.fill", 0xe38c00), "prisma": symbol("triangle.fill", 0x5a67d8),
        "sh": label("$_", 0x89e051), "zsh": label("$_", 0x89e051), "bash": label("$_", 0x89e051),
        "env": symbol("key.fill", 0xd8b64a), "lock": symbol("lock.fill", 0x8a8a8a),
        "png": symbol("photo", 0xa074c4), "jpg": symbol("photo", 0xa074c4), "jpeg": symbol("photo", 0xa074c4),
        "gif": symbol("photo", 0xa074c4), "webp": symbol("photo", 0xa074c4), "ico": symbol("photo", 0xa074c4),
        "svg": symbol("square.on.circle", 0xffb13b), "pdf": symbol("doc.richtext.fill", 0xe0464b),
        "ttf": symbol("textformat", 0x8a8a8a), "woff": symbol("textformat", 0x8a8a8a), "woff2": symbol("textformat", 0x8a8a8a),
        "zip": symbol("doc.zipper", 0x8a8a8a), "gz": symbol("doc.zipper", 0x8a8a8a),
        "mp4": symbol("film", 0xa074c4), "mov": symbol("film", 0xa074c4), "mp3": symbol("waveform", 0xa074c4),
    ]

    private static let fallback = symbol("doc", 0x8a8a8a)

    static func `for`(_ path: String) -> FileTypeStyle {
        let name = (path as NSString).lastPathComponent.lowercased()
        if let style = names[name] { return style }
        if name.hasPrefix(".env") { return extensions["env"]! }
        let style = extensions[(name as NSString).pathExtension] ?? fallback
        // Tests get a flask, tinted like their language (VS Code's "TS test" look).
        if name.contains(".test.") || name.contains(".spec.") { return .init(glyph: .symbol("testtube.2"), color: style.color) }
        return style
    }
}
