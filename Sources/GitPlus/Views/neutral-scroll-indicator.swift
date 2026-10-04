import SwiftUI

/// Replaces the system scroller on colored content (diffs): the translucent macOS scroller picks up the
/// green/red line backgrounds, so this draws a neutral gray thumb instead. Draggable; widens on hover.
private struct NeutralScrollIndicator: ViewModifier {
    @State private var position = ScrollPosition(edge: .top)
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var hovering = false
    @State private var dragStartOffset: CGFloat?

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .onScrollGeometryChange(for: [CGFloat].self) { geo in
                [geo.contentOffset.y + geo.contentInsets.top, geo.contentSize.height, geo.containerSize.height]
            } action: { _, values in
                offset = values[0]; contentHeight = values[1]; viewportHeight = values[2]
            }
            .overlay(alignment: .topTrailing) { thumb }
    }

    @ViewBuilder private var thumb: some View {
        let scrollable = contentHeight - viewportHeight
        if scrollable > 1, viewportHeight > 0 {
            let inset: CGFloat = 2
            let track = viewportHeight - inset * 2
            let length = max(track * viewportHeight / contentHeight, 28)
            let progress = min(max(offset / scrollable, 0), 1)
            let active = hovering || dragStartOffset != nil
            Capsule()
                .fill(Color(nsColor: .secondaryLabelColor).opacity(active ? 0.9 : 0.6))
                .frame(width: active ? 9 : 6, height: length)
                .padding(.trailing, inset)
                .offset(y: inset + (track - length) * progress)
                .frame(width: 16, alignment: .trailing)   // wider hit area than the visible thumb
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let start = dragStartOffset ?? offset
                            if dragStartOffset == nil { dragStartOffset = start }
                            let perPoint = scrollable / max(track - length, 1)
                            position.scrollTo(y: min(max(start + drag.translation.height * perPoint, 0), scrollable))
                        }
                        .onEnded { _ in dragStartOffset = nil }
                )
                .animation(.easeOut(duration: 0.12), value: active)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// For vertical `ScrollView`s over colored rows (diff, blame, conflicts).
    func neutralScrollIndicator() -> some View { modifier(NeutralScrollIndicator()) }
}
