import AppKit
import Observation
import SwiftUI

/// The user's accent color (Settings → General → Appearance). `nil` follows the macOS accent color;
/// a custom color is used as-is in both appearances.
/// Observable, so every view body that reads `Theme.accent` redraws when it changes.
@Observable
final class AccentSettings: @unchecked Sendable {
    static let shared = AccentSettings()
    private static let key = "accentRGB"

    /// Custom color as sRGB components, persisted as "r,g,b".
    var custom: NSColor? {
        didSet {
            if let rgb = custom?.usingColorSpace(.sRGB) {
                UserDefaults.standard.set("\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent)", forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }
    }

    var color: Color { custom.map { Color(nsColor: $0) } ?? .accentColor }

    private init() {
        let parts = UserDefaults.standard.string(forKey: Self.key)?.split(separator: ",").compactMap { Double($0) } ?? []
        if parts.count == 3, parts.allSatisfy({ (0...1).contains($0) }) {
            custom = NSColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: 1)
        }
    }
}

extension Theme {
    /// The app's accent: the user's custom color, or the macOS accent color.
    static var accent: Color { AccentSettings.shared.color }
}

/// System color well for the accent, plus a reset to the macOS accent color.
struct AccentPicker: View {
    @Bindable private var settings = AccentSettings.shared

    private var selection: Binding<Color> {
        Binding(get: { settings.color },
                set: { settings.custom = NSColor($0).usingColorSpace(.sRGB) })
    }

    var body: some View {
        LabeledContent("Accent color") {
            HStack(spacing: Spacing.s) {
                if settings.custom != nil {
                    Button("Use System") { settings.custom = nil }
                        .controlSize(.small)
                        .help("Follow the accent color in System Settings → Appearance")
                }
                ColorPicker("Accent color", selection: selection, supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }
}

extension View {
    /// Applies the user's accent as the tint (toggles, pickers, prominent and glass buttons).
    func appAccentTint() -> some View { modifier(AccentTint()) }
}

private struct AccentTint: ViewModifier {
    func body(content: Content) -> some View { content.tint(Theme.accent) }
}
