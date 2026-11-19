import AppKit
import SwiftUI

/// Overlay scroller whose knob is about half as thick as the system one, with no track.
/// Keeps the native behavior (appears while scrolling, draggable); only the drawing changes.
final class ThinScroller: NSScroller {
    private static let knobWidth: CGFloat = 4
    private static let inset: CGFloat = 2

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 0 else { return }
        let w = Self.knobWidth
        let r = NSRect(x: bounds.maxX - w - Self.inset, y: knob.minY + Self.inset,
                       width: w, height: max(knob.height - Self.inset * 2, w))
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: r, xRadius: w / 2, yRadius: w / 2).fill()
    }
}

/// Zero-size view placed inside a SwiftUI `List` row or `ScrollView` content: swaps the enclosing
/// NSScrollView's vertical scroller for a `ThinScroller` once.
private struct ThinScrollerInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { InstallerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class InstallerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.install() }
        }

        private func install() {
            guard let scrollView = enclosingScrollView, !(scrollView.verticalScroller is ThinScroller) else { return }
            let scroller = ThinScroller()
            scroller.scrollerStyle = scrollView.scrollerStyle
            scrollView.verticalScroller = scroller
        }
    }
}

extension View {
    /// Apply to content inside a `List` or `ScrollView` (a row, or the scrolled stack) to thin its scroller.
    func thinScroller() -> some View { background(ThinScrollerInstaller().frame(width: 0, height: 0)) }
}
