import AppKit
import SwiftUI

/// Windows 11 (Fluent) design tokens: Mica window base, translucent layers and cards,
/// 4-pt control corners, 8-pt overlay corners, a single accent color. Values follow WinUI 3's theme resources.
enum Fluent {
    static let controlRadius: CGFloat = 4
    static let overlayRadius: CGFloat = 8

    private static func c(_ light: UInt32, _ la: CGFloat = 1, dark: UInt32, _ da: CGFloat = 1) -> Color {
        func ns(_ v: UInt32, _ a: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
        }
        return Theme.dynamic(light: ns(light, la), dark: ns(dark, da))
    }

    // Accent: user-selectable (see `AccentSettings`); reading it in a view body tracks changes.
    static var accent: Color { AccentSettings.shared.color }
    static var onAccent: Color { AccentSettings.shared.onColor }

    // Surfaces.
    // Base (navigation, commands) is darker; the content layer is lighter, so the working area reads first.
    static let mica = c(0xEEEEEE, dark: 0x1C1C1C)
    static let layer = c(0xFBFBFB, dark: 0x282828)
    static let card = c(0xFFFFFF, 0.7, dark: 0xFFFFFF, 0.05)
    static let cardStroke = c(0x000000, 0.08, dark: 0xFFFFFF, 0.07)
    static let flyoutStroke = c(0x000000, 0.06, dark: 0x000000, 0.2)
    static let acrylicTint = c(0xFCFCFC, 0.85, dark: 0x2C2C2C, 0.96)
    static let shadow = c(0x000000, 0.14, dark: 0x000000, 0.26)

    // Controls (ControlFillColor* / ControlStrokeColor*).
    static let controlFill = c(0xFFFFFF, 0.7, dark: 0xFFFFFF, 0.06)
    static let controlFillHover = c(0xF9F9F9, 0.5, dark: 0xFFFFFF, 0.08)
    static let controlFillPressed = c(0xF9F9F9, 0.3, dark: 0xFFFFFF, 0.03)
    static let controlStroke = c(0x000000, 0.06, dark: 0xFFFFFF, 0.07)
    static let controlStrokeBottom = c(0x000000, 0.16, dark: 0xFFFFFF, 0.09)
    static let controlStrongStroke = c(0x000000, 0.45, dark: 0xFFFFFF, 0.54)
    static let subtleHover = c(0x000000, 0.04, dark: 0xFFFFFF, 0.06)
    static let subtlePressed = c(0x000000, 0.02, dark: 0xFFFFFF, 0.04)
    /// Selected segment: neutral, because accent is reserved for primary actions and selection pills.
    static let segmentFill = c(0x6E6E73, dark: 0x636366)

    // InfoBar backgrounds and glyph colors.
    enum Severity { case success, warning, error }

    /// Critical text and glyphs; also readable on the tinted InfoBars and control fills.
    static let critical = c(0xC42B1C, dark: 0xFF99A4)
    /// The mark inside a severity glyph: the dark-theme glyphs are pale, so it flips to black.
    static let onSeverity = c(0xFFFFFF, dark: 0x000000)

    static func background(_ s: Severity) -> Color {
        switch s {
        case .success: c(0xDFF6DD, dark: 0x393D1B)
        case .warning: c(0xFFF4CE, dark: 0x433519)
        case .error: c(0xFDE7E9, dark: 0x442726)
        }
    }

    static func glyph(_ s: Severity) -> (symbol: String, color: Color) {
        switch s {
        case .success: ("checkmark.circle.fill", c(0x0F7B0F, dark: 0x6CCB5F))
        case .warning: ("exclamationmark.circle.fill", c(0x9D5D00, dark: 0xFCE100))
        case .error: ("xmark.circle.fill", critical)
        }
    }
}

/// Windows 11 button: `.standard` (light fill, 1-pt stroke with darker bottom edge), `.accent`
/// (filled accent) or `.subtle` (transparent until hovered — command bars, toolbars).
struct FluentButtonStyle: ButtonStyle {
    enum Kind { case standard, accent, subtle }
    var kind: Kind
    /// Overrides the side padding (the arrow half of a split button).
    var sidePadding: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        FluentButtonBody(configuration: configuration, kind: kind, sidePadding: sidePadding)
    }
}

private struct FluentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: FluentButtonStyle.Kind
    let sidePadding: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.uiTextScale) private var scale
    @State private var hovering = false

    private var compact: Bool { controlSize == .small || controlSize == .mini }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous) }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .lineLimit(1)
            .padding(.horizontal, (sidePadding ?? (compact ? 8 : 11)) * scale)
            .frame(minHeight: (compact ? 22 : 28) * scale)
            .foregroundStyle(foreground(pressed))
            .background(shape.fill(fill(pressed)))
            .overlay { border }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.08), value: hovering)
    }

    private func fill(_ pressed: Bool) -> Color {
        switch kind {
        case .accent: Fluent.accent.mix(with: Fluent.onAccent == .black ? .white : .black, by: pressed ? 0.16 : hovering ? 0.08 : 0)   // away from the text, so contrast only grows
        case .standard: pressed ? Fluent.controlFillPressed : hovering ? Fluent.controlFillHover : Fluent.controlFill
        case .subtle: pressed ? Fluent.subtlePressed : hovering ? Fluent.subtleHover : .clear
        }
    }

    private func foreground(_ pressed: Bool) -> AnyShapeStyle {
        if kind == .accent { return AnyShapeStyle(Fluent.onAccent) }
        if configuration.role == .destructive { return AnyShapeStyle(Fluent.critical) }
        return pressed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    @ViewBuilder private var border: some View {
        switch kind {
        case .subtle: EmptyView()
        case .standard:
            shape.strokeBorder(LinearGradient(stops: [.init(color: Fluent.controlStroke, location: 0.85),
                                                      .init(color: Fluent.controlStrokeBottom, location: 1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        case .accent:
            shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.08), location: 0.85),
                                                      .init(color: .black.opacity(0.3), location: 1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}

/// TextBox surface: control fill, hairline stroke and a stronger bottom edge that turns accent while focused.
struct FluentFieldSurface: View {
    var isFocused = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
        shape.fill(Fluent.controlFill)
            .overlay(shape.strokeBorder(Fluent.controlStroke))
            .overlay(alignment: .bottom) {
                Rectangle().fill(isFocused ? Fluent.accent : Fluent.controlStrongStroke).frame(height: isFocused ? 2 : 1).padding(.horizontal, 1)
            }
            .clipShape(shape)
    }
}

/// The app's `.secondary` level (set at the root): the system's is only 3.9:1 on light surfaces.
/// Darker under System Settings → Accessibility → Increase contrast, as the system's own level is.
struct AppSecondaryStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        let more = environment.colorSchemeContrast == .increased
        if environment.backgroundProminence == .increased { return .white.opacity(more ? 0.95 : 0.8) }
        return environment.colorScheme == .dark ? .white.opacity(more ? 0.8 : 0.6) : .black.opacity(more ? 0.78 : 0.58)
    }
}

extension ButtonStyle where Self == FluentButtonStyle {
    static var fluent: FluentButtonStyle { FluentButtonStyle(kind: .standard) }
    static var fluentAccent: FluentButtonStyle { FluentButtonStyle(kind: .accent) }
    static var fluentSubtle: FluentButtonStyle { FluentButtonStyle(kind: .subtle) }
}

extension View {
    /// Card on a layer: translucent fill + hairline stroke (Settings-style cards).
    func fluentCard(radius: CGFloat = Fluent.overlayRadius, hovering: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(hovering ? Fluent.controlFillHover : Fluent.card))
            .overlay(shape.strokeBorder(Fluent.cardStroke))
    }

    /// Acrylic flyout: blurred, tinted surface with stroke and soft shadow (menus, palette, toasts).
    func fluentFlyout(radius: CGFloat = Fluent.overlayRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background { shape.fill(.regularMaterial).overlay(shape.fill(Fluent.acrylicTint)) }
            .overlay(shape.strokeBorder(Fluent.flyoutStroke))
            .clipShape(shape)
            .shadow(color: Fluent.shadow, radius: 16, y: 8)
    }

    /// One-line TextBox: standard padding on the shared field surface.
    func fluentTextField(focused: Bool = false) -> some View {
        padding(.horizontal, Spacing.s).padding(.vertical, 5).background(FluentFieldSurface(isFocused: focused))
    }

    /// Native segmented control with the neutral selected segment.
    func fluentSegmented() -> some View { pickerStyle(.segmented).tint(Fluent.segmentFill) }

    /// InfoBar surface: severity-tinted fill with a hairline stroke.
    func fluentInfoBar(_ severity: Fluent.Severity) -> some View {
        let shape = RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
        return background(shape.fill(Fluent.background(severity))).overlay(shape.strokeBorder(Fluent.cardStroke))
    }
}
