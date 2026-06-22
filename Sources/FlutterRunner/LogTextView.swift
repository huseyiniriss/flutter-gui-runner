import SwiftUI
import AppKit

/// A read-only NSTextView-backed log view. NSTextView handles huge streaming
/// text, selection, and scrolling far more efficiently than a SwiftUI `Text`
/// inside a `ScrollView` (which re-lays out the entire string on every update).
struct LogTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 11

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 6, height: 6)
            tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            tv.string = text
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if tv.font != font { tv.font = font }
        guard tv.string != text else { return }
        // Only auto-scroll if the user is already near the bottom, so reading
        // back through the log isn't yanked away by new output.
        let atBottom = scroll.contentView.bounds.maxY
            >= (scroll.documentView?.bounds.height ?? 0) - 24
        tv.string = text
        if atBottom { tv.scrollToEndOfDocument(nil) }
    }
}
