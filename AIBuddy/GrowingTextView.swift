import SwiftUI

struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = .width
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 5

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
            }

            DispatchQueue.main.async {
                let fittingSize = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
                let newHeight = min(max(fittingSize.height + 16, 36), 120)
                if abs(height - newHeight) > 1 {
                    height = newHeight
                }
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(parent: GrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if !NSEvent.modifierFlags.contains(.shift) {
                    parent.onReturn()
                    return true
                }
            }
            return false
        }
    }
}
