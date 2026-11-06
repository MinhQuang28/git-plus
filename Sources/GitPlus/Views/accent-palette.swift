import AppKit
import Observation
import SwiftUI

/// The user's accent color (Settings → General → Appearance). `nil` = default indigo,
/// which adapts to light/dark; a custom color is used as-is in both appearances.
/// Observable, so every view body that reads `Fluent.accent` redraws when it changes.
@Observable
final class AccentSettings: @unchecked Sendable {
    static let shared = AccentSettings()
    private static let key = "accentRGB"

    /// Default accent: indigo (#4F46E5 light / #6559FF dark). White text holds 4.5:1 on both, the selection pill
    /// holds 3:1 on Mica and on the content layer, and its hue stays clear of every status color.
    static let defaultColor = Theme.dynamic(light: NSColor(srgbRed: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255, alpha: 1),
                                            dark: NSColor(srgbRed: 0x65 / 255, green: 0x59 / 255, blue: 0xFF / 255, alpha: 1))

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

    var color: Color { custom.map { Color(nsColor: $0) } ?? Self.defaultColor }

    /// Text on an accent fill: whichever of black or white contrasts more (they tie at luminance 0.179).
    var onColor: Color {
        guard let rgb = custom?.usingColorSpace(.sRGB) else { return .white }
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * lin(rgb.redComponent) + 0.7152 * lin(rgb.greenComponent) + 0.0722 * lin(rgb.blueComponent)
        return luminance > 0.179 ? .black : .white
    }

    private init() {
        let parts = UserDefaults.standard.string(forKey: Self.key)?.split(separator: ",").compactMap { Double($0) } ?? []
        if parts.count == 3, parts.allSatisfy({ (0...1).contains($0) }) {
            custom = NSColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: 1)
        }
    }
}

/// System color well for the accent, plus a reset to the default.
struct AccentPicker: View {
    @Bindable private var settings = AccentSettings.shared

    private var selection: Binding<Color> {
        Binding(get: { settings.color },
                set: { settings.custom = NSColor($0).usingColorSpace(.sRGB) })
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text("Accent color")
            Spacer()
            if settings.custom != nil {
                Button("Reset") { settings.custom = nil }
                    .controlSize(.small)
                    .help("Back to the default indigo")
            }
            ColorPicker("Accent color", selection: selection, supportsOpacity: false)
                .labelsHidden()
        }
    }
}

extension View {
    /// Applies the user's accent as the tint (toggles, pickers, prominent controls).
    func fluentRootStyle() -> some View { modifier(FluentRootStyle()) }
}

/// Switch that keeps the accent when on, for forms whose tint is neutral (Windows: ComboBox text stays neutral).
struct FluentSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(Fluent.accent)
    }
}

extension ToggleStyle where Self == FluentSwitchStyle {
    static var fluentSwitch: FluentSwitchStyle { FluentSwitchStyle() }
}

private struct FluentRootStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(Fluent.accent).foregroundStyle(.primary, AppSecondaryStyle(), .tertiary)
    }
}
