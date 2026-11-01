import AppKit
import SwiftUI

/// Windows 11 title bar drawn in the (hidden) system title bar area: app icon + name on Mica.
/// The macOS window buttons stay in place on the left; the whole bar drags the window.
struct FluentTitleBar: View {
    static let height: CGFloat = 32

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 16, height: 16)
            Text("Git Plus").appFont(size: 12).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 84)   // clears the window buttons
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .windowDragArea()
    }
}

/// Command bar under the title bar: page navigation on the left, subtle commands on the right.
struct FluentCommandBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.xs) {
            leading
            Spacer(minLength: Spacing.m)
            HStack(spacing: Spacing.xxs) { trailing }
                .buttonStyle(.fluentSubtle)
        }
        .padding(.horizontal, Spacing.s)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .windowDragArea()
    }
}

/// WinUI SelectorBar: text items with an accent pill under the selected one.
struct FluentSelectorBar<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, title: String)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(items, id: \.value) { item in
                SelectorItem(title: item.title, isSelected: item.value == selection, pill: pill) {
                    withAnimation(.spring(duration: 0.25)) { selection = item.value }
                }
            }
        }
    }

    private struct SelectorItem: View {
        let title: String
        let isSelected: Bool
        let pill: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text(title)
                    .appFont(size: 13, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, Spacing.m).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: Fluent.controlRadius).fill(hovering ? Fluent.subtleHover : .clear))
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Capsule().fill(Fluent.accent).frame(width: 16, height: 3)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { hovering = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// Leading 3×16 accent pill + subtle fill — the Windows 11 selected-list-item look.
struct FluentListItem: ViewModifier {
    var isSelected: Bool
    var isHighlighted = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
        content
            .background(shape.fill(isSelected || isHighlighted ? Fluent.subtleHover : hovering ? Fluent.subtlePressed : .clear))
            .overlay(alignment: .leading) {
                if isSelected { Capsule().fill(Fluent.accent).frame(width: 3, height: 16) }
            }
            .overlay { if isHighlighted { shape.strokeBorder(Fluent.accent, lineWidth: 1) } }
            .padding(.horizontal, Spacing.xs)
            .onHover { hovering = $0 }
    }
}

/// The Windows 11 content layer: lighter surface with a rounded top-leading corner over the Mica base.
private struct FluentContentLayer: ViewModifier {
    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Fluent.overlayRadius, style: .continuous)
        content
            .background(Fluent.layer)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Fluent.cardStroke))
    }
}

/// Severity glyph used by InfoBars and toasts.
struct FluentSeverityIcon: View {
    let severity: Fluent.Severity

    var body: some View {
        let glyph = Fluent.glyph(severity)
        Image(systemName: glyph.symbol).symbolRenderingMode(.palette).foregroundStyle(.white, glyph.color)
    }
}

extension View {
    func fluentListItem(selected: Bool, highlighted: Bool = false) -> some View {
        modifier(FluentListItem(isSelected: selected, isHighlighted: highlighted))
    }

    func fluentContentLayer() -> some View { modifier(FluentContentLayer()) }

    /// Empty parts of the bar move the window; double-click zooms, like a title bar.
    func windowDragArea() -> some View {
        background {
            Color.clear.contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .onTapGesture(count: 2) { NSApp.keyWindow?.zoom(nil) }
        }
    }
}
