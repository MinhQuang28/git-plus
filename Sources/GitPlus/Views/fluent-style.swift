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

    // Accent (AccentFillColorDefault / TextOnAccentFillColorPrimary).
    static let accent = c(0x005FB8, dark: 0x60CDFF)
    static let onAccent = c(0xFFFFFF, dark: 0x000000)
    static let accentText = c(0x003E92, dark: 0x99EBFF)

    // Surfaces.
    static let mica = c(0xF3F3F3, dark: 0x202020)
    static let layer = c(0xFFFFFF, 0.5, dark: 0x3A3A3A, 0.3)
    static let card = c(0xFFFFFF, 0.7, dark: 0xFFFFFF, 0.05)
    static let cardStroke = c(0x000000, 0.06, dark: 0x000000, 0.1)
    static let flyoutStroke = c(0x000000, 0.06, dark: 0x000000, 0.2)
    static let acrylicTint = c(0xFCFCFC, 0.85, dark: 0x2C2C2C, 0.96)
    static let shadow = c(0x000000, 0.14, dark: 0x000000, 0.26)
    static let divider = c(0x000000, 0.08, dark: 0xFFFFFF, 0.08)

    // Controls (ControlFillColor* / ControlStrokeColor*).
    static let controlFill = c(0xFFFFFF, 0.7, dark: 0xFFFFFF, 0.06)
    static let controlFillHover = c(0xF9F9F9, 0.5, dark: 0xFFFFFF, 0.08)
    static let controlFillPressed = c(0xF9F9F9, 0.3, dark: 0xFFFFFF, 0.03)
    static let controlStroke = c(0x000000, 0.06, dark: 0xFFFFFF, 0.07)
    static let controlStrokeBottom = c(0x000000, 0.16, dark: 0xFFFFFF, 0.09)
    static let subtleHover = c(0x000000, 0.04, dark: 0xFFFFFF, 0.06)
    static let subtlePressed = c(0x000000, 0.02, dark: 0xFFFFFF, 0.04)

    // InfoBar backgrounds and glyph colors.
    enum Severity { case info, success, warning, error }

    static func background(_ s: Severity) -> Color {
        switch s {
        case .info: c(0xF6F6F6, 0.5, dark: 0xFFFFFF, 0.03)
        case .success: c(0xDFF6DD, dark: 0x393D1B)
        case .warning: c(0xFFF4CE, dark: 0x433519)
        case .error: c(0xFDE7E9, dark: 0x442726)
        }
    }

    static func glyph(_ s: Severity) -> (symbol: String, color: Color) {
        switch s {
        case .info: ("info.circle.fill", accent)
        case .success: ("checkmark.circle.fill", c(0x0F7B0F, dark: 0x6CCB5F))
        case .warning: ("exclamationmark.circle.fill", c(0x9D5D00, dark: 0xFCE100))
        case .error: ("xmark.circle.fill", c(0xC42B1C, dark: 0xFF99A4))
        }
    }
}

/// Windows 11 button: `.standard` (light fill, 1-pt stroke with darker bottom edge), `.accent`
/// (filled accent) or `.subtle` (transparent until hovered — command bars, toolbars).
struct FluentButtonStyle: ButtonStyle {
    enum Kind { case standard, accent, subtle }
    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        FluentButtonBody(configuration: configuration, kind: kind)
    }
}

private struct FluentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: FluentButtonStyle.Kind
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
            .padding(.horizontal, (compact ? 8 : 11) * scale)
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
        case .accent: Fluent.accent.opacity(pressed ? 0.8 : hovering ? 0.9 : 1)
        case .standard: pressed ? Fluent.controlFillPressed : hovering ? Fluent.controlFillHover : Fluent.controlFill
        case .subtle: pressed ? Fluent.subtlePressed : hovering ? Fluent.subtleHover : .clear
        }
    }

    private func foreground(_ pressed: Bool) -> AnyShapeStyle {
        if kind == .accent { return AnyShapeStyle(Fluent.onAccent.opacity(pressed ? 0.8 : 1)) }
        if configuration.role == .destructive { return AnyShapeStyle(Theme.deleted) }
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

    /// TextBox surface: control fill, hairline stroke and the darker bottom edge.
    func fluentTextField() -> some View {
        let shape = RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
        return background(shape.fill(Fluent.controlFill))
            .overlay(shape.strokeBorder(Fluent.controlStroke))
            .overlay(alignment: .bottom) { Rectangle().fill(Fluent.controlStrokeBottom).frame(height: 1).padding(.horizontal, 1) }
            .clipShape(shape)
    }

    /// InfoBar surface: severity-tinted fill with a hairline stroke.
    func fluentInfoBar(_ severity: Fluent.Severity) -> some View {
        let shape = RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
        return background(shape.fill(Fluent.background(severity))).overlay(shape.strokeBorder(Fluent.cardStroke))
    }
}
