import AppKit
import SwiftUI

/// GitHub Desktop–style palette; every color adapts to light/dark appearance.
enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }

    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
    }

    static let barBackground = dynamic(light: hex(0xf6f8fa), dark: hex(0x1c2128))
    static let barHover = dynamic(light: hex(0xeaeef2), dark: hex(0x262c33))
    static let barText = Color.primary
    static let barSecondaryText = Color.secondary
    static let barDivider = dynamic(light: hex(0xd0d7de), dark: hex(0x30363d))
    static let rowHover = dynamic(light: hex(0x000000, 0.04), dark: hex(0xffffff, 0.05))
    static let banner = dynamic(light: hex(0xfff8c5), dark: hex(0x3b2e0a))
    static let bannerBorder = dynamic(light: hex(0xd4a72c), dark: hex(0x9e6a03))

    static let paneBackground = dynamic(light: hex(0xffffff), dark: hex(0x22272e))
    static let headerBackground = dynamic(light: hex(0xf6f8fa), dark: hex(0x2d333b))
    static let separator = dynamic(light: hex(0xd8dee4), dark: hex(0x30363d))

    // Diff colors match GitHub / GitHub Desktop: strong line tint, darker gutter, bright changed words.
    static let addedLine = dynamic(light: hex(0xe6ffec), dark: hex(0x0f3b1d))
    static let addedGutter = dynamic(light: hex(0xccffd8), dark: hex(0x0b2e16))
    static let addedWord = dynamic(light: hex(0xabf2bc), dark: hex(0x1f7d39))
    static let removedLine = dynamic(light: hex(0xffebe9), dark: hex(0x4a1215))
    static let removedGutter = dynamic(light: hex(0xffd7d5), dark: hex(0x3a0d10))
    static let removedWord = dynamic(light: hex(0xffa8a8), dark: hex(0xb3232d))
    static let hunkLine = dynamic(light: hex(0xddf4ff), dark: hex(0x2a3038))
    static let contextLine = dynamic(light: hex(0xffffff), dark: hex(0x24292e))
    static let gutter = dynamic(light: hex(0xf6f8fa), dark: hex(0x2b3036))
    static let gutterText = dynamic(light: hex(0x6e7781), dark: hex(0x9da5b4))
    static let emptySide = dynamic(light: hex(0xf6f8fa), dark: hex(0x1f2328))

    static let modified = dynamic(light: hex(0xb08800), dark: hex(0xd8b64a))
    static let added = dynamic(light: hex(0x28a745), dark: hex(0x3fb950))
    static let deleted = dynamic(light: hex(0xcb2431), dark: hex(0xf85149))
    static let renamed = dynamic(light: hex(0x0366d6), dark: hex(0x58a6ff))
}
