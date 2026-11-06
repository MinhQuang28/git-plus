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
    /// Inset of controls inside a pane; matches the edge of the system's inset list selection.
    static let pane: CGFloat = 10
}

/// Motion that honors System Settings → Accessibility → Reduce motion.
enum Motion {
    private static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func safe(_ animation: Animation) -> Animation? { reduced ? nil : animation }
    /// Toasts and banners: slide up, or only fade when motion is reduced.
    static var slideUp: AnyTransition { reduced ? .opacity : .move(edge: .bottom).combined(with: .opacity) }
}

enum Radius {
    // Windows 11: 4 pt for controls, 8 pt for cards and overlays.
    static let s: CGFloat = 4
    static let m: CGFloat = 8
    static let l: CGFloat = 8
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
    static let barHover = Fluent.subtleHover
    static let barText = Color.primary
    static let barSecondaryText = Color.secondary
    static let barDivider = dynamic(light: hex(0xd0d7de), dark: hex(0x30363d))
    static let banner = dynamic(light: hex(0xfff8c5), dark: hex(0x3b2e0a))

    static let paneBackground = Color(nsColor: .windowBackgroundColor)
    static let headerBackground = Color.primary.opacity(0.045)
    static let separator = Color(nsColor: .separatorColor)

    // Diff colors match GitHub / GitHub Desktop: strong line tint, darker gutter, bright changed words.
    static let addedLine = dynamic(light: hex(0xe6ffec), dark: hex(0x2a3e2d))
    static let addedGutter = dynamic(light: hex(0xccffd8), dark: hex(0x2a4c30))
    static let addedWord = dynamic(light: hex(0xabf2bc), dark: hex(0x2b5e34))
    static let removedLine = dynamic(light: hex(0xffebe9), dark: hex(0x4d2f2e))
    static let removedGutter = dynamic(light: hex(0xffd7d5), dark: hex(0x663432))
    static let removedWord = dynamic(light: hex(0xffa8a8), dark: hex(0x863b37))
    static let hunkLine = dynamic(light: hex(0xeef5ff), dark: hex(0x2a3442))
    static let contextLine = dynamic(light: hex(0xffffff), dark: hex(0x282828))
    static let gutter = Color.primary.opacity(0.035)
    static let gutterText = Color.primary.opacity(0.65)   // AA on every diff tint, unlike .secondary
    static let emptySide = Color.primary.opacity(0.03)

    // Light values hold 4.5:1 on Mica and on a selected list row.
    static let modified = dynamic(light: hex(0x805500), dark: hex(0xd8b64a))
    static let added = dynamic(light: hex(0x116329), dark: hex(0x3fb950))
    static let deleted = dynamic(light: hex(0xb01c27), dark: hex(0xff7b72))
    static let renamed = dynamic(light: hex(0x0a58b8), dark: hex(0x58a6ff))
    static let conflict = dynamic(light: hex(0xa33f00), dark: hex(0xf0883e))
    static let ahead = dynamic(light: hex(0x0a58b8), dark: hex(0x58a6ff))
    static let behind = dynamic(light: hex(0xa33f00), dark: hex(0xf0883e))

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
