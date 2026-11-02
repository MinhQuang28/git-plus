import AppKit
import Observation
import SwiftUI

/// User-selectable accent colors (Settings → General → Appearance).
enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, system, windows, indigo, purple, pink, orange, green, teal, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "GitHub Blue"
        case .system: "macOS Accent"
        case .windows: "Windows Cyan"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .orange: "Orange"
        case .green: "Green"
        case .teal: "Teal"
        case .graphite: "Graphite"
        }
    }

    /// Fill / text accent (light, dark). Dark values are tuned to stay readable on #202020.
    var color: Color {
        switch self {
        case .system: Color(nsColor: .controlAccentColor)
        case .blue: Self.pair(0x0969DA, 0x2F81F7)
        case .windows: Self.pair(0x005FB8, 0x60CDFF)
        case .indigo: Self.pair(0x4F46E5, 0x6E6AF2)
        case .purple: Self.pair(0x8250DF, 0x9A6AF0)
        case .pink: Self.pair(0xBF3989, 0xD25B9B)
        case .orange: Self.pair(0xBC4C00, 0xD9692C)
        case .green: Self.pair(0x1A7F37, 0x2EA043)
        case .teal: Self.pair(0x0E7C86, 0x1C9A9A)
        case .graphite: Self.pair(0x57606A, 0x6E7681)
        }
    }

    /// Text drawn on an accent fill: white, except on the pale Windows cyan in dark mode.
    var onColor: Color { self == .windows ? Self.pair(0xFFFFFF, 0x000000) : .white }

    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        return Theme.dynamic(light: ns(light), dark: ns(dark))
    }
}

/// The current accent. Observable, so every view body that reads `Fluent.accent` redraws when it changes.
@Observable
final class AccentSettings: @unchecked Sendable {
    static let shared = AccentSettings()
    private static let key = "accentColor"

    var choice: AccentChoice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: Self.key) }
    }

    private init() {
        choice = UserDefaults.standard.string(forKey: Self.key).flatMap(AccentChoice.init) ?? .blue
    }
}

/// Row of color swatches; the selected one gets a ring. Hover shows the name.
struct AccentPicker: View {
    @Bindable private var settings = AccentSettings.shared

    var body: some View {
        LabeledContent("Accent color") {
            HStack(spacing: 6) {
                ForEach(AccentChoice.allCases) { choice in
                    Button { settings.choice = choice } label: { swatch(choice) }
                        .buttonStyle(.plain)
                        .help(choice.title)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(settings.choice == choice ? .isSelected : [])
                }
            }
        }
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        let selected = settings.choice == choice
        return Circle()
            .fill(choice.color)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(.black.opacity(0.15)))
            .overlay {
                if choice == .system { Image(systemName: "apple.logo").font(.system(size: 9)).foregroundStyle(.white) }
            }
            .padding(2)
            .overlay(Circle().strokeBorder(selected ? choice.color : .clear, lineWidth: 2))
            .contentShape(Circle())
    }
}

extension View {
    /// Applies the user's accent as the tint (toggles, pickers, prominent controls).
    func fluentAccentTint() -> some View { modifier(AccentTint()) }
}

private struct AccentTint: ViewModifier {
    func body(content: Content) -> some View { content.tint(Fluent.accent) }
}
