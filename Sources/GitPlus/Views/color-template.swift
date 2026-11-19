import AppKit
import SwiftUI

/// A color template (Settings → General → Appearance): window surfaces plus the accent, each with a light and a dark
/// variant. Surfaces are near-neutral with a slight tint of the accent's hue, so long sessions stay easy on the eyes.
/// Every accent holds 4.5:1 under white text and 3:1 as a selection pill on its own surfaces, and stays clear of the
/// status hues (Sage is olive rather than the "added" green, Sand is earth brown rather than the "conflict" orange).
enum ColorTemplate: String, CaseIterable, Identifiable {
    case indigo, slate, ocean, sage, sand, rose

    static let key = "colorTemplate"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .indigo: "Indigo"
        case .slate: "Slate"
        case .ocean: "Ocean"
        case .sage: "Sage"
        case .sand: "Sand"
        case .rose: "Rose"
        }
    }

    /// Resolved colors; built once per template.
    struct Palette {
        /// Window base (navigation, commands).
        let mica: Color
        /// Content layer on top of the base.
        let layer: Color
        /// Tint over the blur of flyouts and popovers.
        let acrylicTint: Color
        /// Unchanged lines in a diff.
        let contextLine: Color
        let accent: Color
    }

    var palette: Palette { Self.palettes[self]! }

    private static let palettes: [ColorTemplate: Palette] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.makePalette()) })

    /// (light, dark) hex values: base, content layer, accent.
    private var hex: (mica: (UInt32, UInt32), layer: (UInt32, UInt32), accent: (UInt32, UInt32)) {
        switch self {
        case .indigo: ((0xEEEEEE, 0x1C1C1C), (0xFBFBFB, 0x282828), (0x4F46E5, 0x6559FF))
        case .slate: ((0xECEFF4, 0x171A20), (0xFAFBFD, 0x21252D), (0x2563EB, 0x2F6BEA))
        case .ocean: ((0xEAF1F2, 0x151B1D), (0xF9FCFC, 0x1F272A), (0x0F766E, 0x0E7F76))
        case .sage: ((0xEDF1EC, 0x171B18), (0xFAFCFA, 0x212724), (0x5A6E1E, 0x6A7D2C))
        case .sand: ((0xF3EFE8, 0x1D1A17), (0xFDFBF8, 0x292521), (0x855526, 0x9C6936))
        case .rose: ((0xF4EEF1, 0x1D191B), (0xFDFAFB, 0x292326), (0xBE2A6E, 0xCE3379))
        }
    }

    private func makePalette() -> Palette {
        func ns(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
        }
        let h = hex
        return Palette(mica: Theme.dynamic(light: ns(h.mica.0), dark: ns(h.mica.1)),
                       layer: Theme.dynamic(light: ns(h.layer.0), dark: ns(h.layer.1)),
                       acrylicTint: Theme.dynamic(light: ns(h.layer.0, 0.85), dark: ns(h.layer.1, 0.96)),
                       contextLine: Theme.dynamic(light: ns(0xFFFFFF), dark: ns(h.layer.1)),
                       accent: Theme.dynamic(light: ns(h.accent.0), dark: ns(h.accent.1)))
    }
}

/// Template swatches: a miniature of the window (base, content layer, accent) under the template's name.
struct ColorTemplatePicker: View {
    @Bindable private var settings = AccentSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Color template")
            HStack(spacing: Spacing.s) {
                ForEach(ColorTemplate.allCases) { template in
                    swatch(template)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func swatch(_ template: ColorTemplate) -> some View {
        let palette = template.palette
        let isSelected = settings.template == template
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button {
            settings.template = template
            settings.custom = nil   // the template brings its own accent; the color well can still override it
        } label: {
            VStack(spacing: Spacing.xs) {
                ZStack(alignment: .bottomTrailing) {
                    palette.mica
                    UnevenRoundedRectangle(topLeadingRadius: 4, style: .continuous).fill(palette.layer)
                        .padding(.leading, 18).padding(.top, 10)
                    Capsule().fill(palette.accent).frame(width: 22, height: 6).padding(6)
                }
                .frame(height: 40)
                .clipShape(shape)
                .overlay(shape.strokeBorder(isSelected ? palette.accent : Fluent.controlStrongStroke.opacity(0.35), lineWidth: isSelected ? 2 : 1))
                Text(template.title)
                    .appFont(.caption, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(template.title) surfaces and accent")
        .accessibilityLabel("\(template.title) color template")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
