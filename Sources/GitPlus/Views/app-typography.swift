import SwiftUI

/// Interface text size (Settings → General → Text size, ⌃⌘= / ⌃⌘-). macOS has no Dynamic Type,
/// so every view takes its font from `appFont`, which multiplies the base size by this scale.
enum UITextScale: Double, CaseIterable, Identifiable {
    case small = 0.9, standard = 1.0, large = 1.12, larger = 1.25, largest = 1.4

    static let key = "uiTextScale"
    var id: Double { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }

    /// One step up/down from a stored raw value (menu shortcuts).
    static func step(from raw: Double, by delta: Int) -> UITextScale {
        let all = allCases
        let index = all.firstIndex { $0.rawValue >= raw - 0.001 } ?? 1
        return all[min(max(index + delta, 0), all.count - 1)]
    }
}

struct UITextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var uiTextScale: CGFloat {
        get { self[UITextScaleKey.self] }
        set { self[UITextScaleKey.self] = newValue }
    }
}

/// macOS point sizes of the system text styles, scaled together.
enum AppTextStyle {
    case largeTitle, title2, title3, headline, body, callout, subheadline, caption, caption2, footnote

    var size: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .caption, .caption2, .footnote: 10
        }
    }

    var weight: Font.Weight { self == .headline ? .bold : .regular }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.uiTextScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let monospacedDigit: Bool

    func body(content: Content) -> some View {
        let font = Font.system(size: size * scale, weight: weight, design: design)
        content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

/// Window/Settings root: publishes the stored scale and makes scaled body text the default font.
private struct UITextScaleRoot: ViewModifier {
    @AppStorage(UITextScale.key) private var scale = UITextScale.standard.rawValue

    func body(content: Content) -> some View {
        content.appFont(.body).environment(\.uiTextScale, scale)
    }
}

extension View {
    func scaledInterfaceText() -> some View { modifier(UITextScaleRoot()) }

    func appFont(_ style: AppTextStyle, weight: Font.Weight? = nil, design: Font.Design = .default, monospacedDigit: Bool = false) -> some View {
        modifier(AppFontModifier(size: style.size, weight: weight ?? style.weight, design: design, monospacedDigit: monospacedDigit))
    }

    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, monospacedDigit: Bool = false) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, design: design, monospacedDigit: monospacedDigit))
    }
}
