import AppKit
import SwiftUI

/// Spacing scale (4-pt grid) used by new and redesigned views.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
}

/// GitHub Desktop–style palette; every color adapts to light/dark appearance.
enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }

    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
    }

    static let barBackground = dynamic(light: hex(0xf6f8fa), dark: hex(0x1c2128))
    static let barHover = Color.primary.opacity(0.07)
    static let barText = Color.primary
    static let barSecondaryText = Color.secondary
    static let barDivider = dynamic(light: hex(0xd0d7de), dark: hex(0x30363d))
    static let rowHover = Color.primary.opacity(0.05)
    static let banner = dynamic(light: hex(0xfff8c5), dark: hex(0x3b2e0a))
    static let bannerBorder = dynamic(light: hex(0xd4a72c), dark: hex(0x9e6a03))

    // System colors so panes match the native (Liquid Glass) window chrome.
    static let paneBackground = Color(nsColor: .windowBackgroundColor)
    static let headerBackground = Color.primary.opacity(0.045)
    static let separator = Color(nsColor: .separatorColor)

    // Diff colors match GitHub / GitHub Desktop: strong line tint, darker gutter, bright changed words.
    static let addedLine = dynamic(light: hex(0xe6ffec), dark: hex(0x0f3b1d))
    static let addedGutter = dynamic(light: hex(0xccffd8), dark: hex(0x0b2e16))
    static let addedWord = dynamic(light: hex(0xabf2bc), dark: hex(0x1f7d39))
    static let removedLine = dynamic(light: hex(0xffebe9), dark: hex(0x4a1215))
    static let removedGutter = dynamic(light: hex(0xffd7d5), dark: hex(0x3a0d10))
    static let removedWord = dynamic(light: hex(0xffa8a8), dark: hex(0xb3232d))
    static let hunkLine = dynamic(light: hex(0xeef5ff), dark: hex(0x1d2633))
    static let contextLine = Color(nsColor: .textBackgroundColor)
    static let gutter = Color.primary.opacity(0.035)
    static let gutterText = Color.secondary
    static let emptySide = Color.primary.opacity(0.03)

    static let modified = dynamic(light: hex(0xb08800), dark: hex(0xd8b64a))
    static let added = dynamic(light: hex(0x28a745), dark: hex(0x3fb950))
    static let deleted = dynamic(light: hex(0xcb2431), dark: hex(0xf85149))
    static let renamed = dynamic(light: hex(0x0366d6), dark: hex(0x58a6ff))
    static let conflict = dynamic(light: hex(0xbc4c00), dark: hex(0xf0883e))
    static let ahead = dynamic(light: hex(0x0969da), dark: hex(0x58a6ff))
    static let behind = dynamic(light: hex(0xbc4c00), dark: hex(0xf0883e))

    /// Commit graph lane colors.
    static let lanes: [Color] = [
        dynamic(light: hex(0x0969da), dark: hex(0x58a6ff)),
        dynamic(light: hex(0x8250df), dark: hex(0xbc8cff)),
        dynamic(light: hex(0x1a7f37), dark: hex(0x3fb950)),
        dynamic(light: hex(0xbc4c00), dark: hex(0xf0883e)),
        dynamic(light: hex(0xbf3989), dark: hex(0xf778ba)),
        dynamic(light: hex(0x0a7c86), dark: hex(0x39c5cf)),
    ]
    static func lane(_ index: Int) -> Color { lanes[index % lanes.count] }
}
