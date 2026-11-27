import AppKit
import SwiftUI

final class DroppableTextView: NSTextView {
    var onFileDrop: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(in: sender) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = extractFileURLs(from: sender)
        if !urls.isEmpty {
            onFileDrop?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func hasFileURLs(in sender: NSDraggingInfo) -> Bool {
        !extractFileURLs(from: sender).isEmpty
    }

    private func extractFileURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let items = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }
        return items
    }

    override func insertTab(_ sender: Any?) {
        insertText("    ", replacementRange: selectedRange())
    }
}

struct DarkTextEditor: NSViewRepresentable {
    @Binding var text: String
    var formatAction: EditorFormatAction?
    var formatRequestID: UUID
    var onScroll: (Double) -> Void
    var onFileDrop: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.118, green: 0.118, blue: 0.125, alpha: 1.0) // #1E1E20

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = DroppableTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.onFileDrop = onFileDrop
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        textView.drawsBackground = true
        textView.backgroundColor = NSColor(red: 0.118, green: 0.118, blue: 0.125, alpha: 1.0)
        textView.insertionPointColor = NSColor(red: 0.478, green: 0.635, blue: 0.969, alpha: 1.0) // #7AA2F7
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(red: 0.180, green: 0.235, blue: 0.349, alpha: 1.0)
        ]

        textView.textContainerInset = NSSize(width: 26, height: 24)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.55
        paragraphStyle.paragraphSpacing = 4

        let typingAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
            .foregroundColor: NSColor(red: 0.84, green: 0.85, blue: 0.88, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        textView.typingAttributes = typingAttrs
        textView.string = text
        textView.textStorage?.setAttributes(typingAttrs, range: NSRange(location: 0, length: (text as NSString).length))

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.55
            paragraphStyle.paragraphSpacing = 4
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: NSColor(red: 0.84, green: 0.85, blue: 0.88, alpha: 1.0),
                .paragraphStyle: paragraphStyle
            ]
            textView.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (text as NSString).length))
            let safeLoc = min(selected.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
        }

        if let action = formatAction, context.coordinator.lastFormatID != formatRequestID {
            context.coordinator.lastFormatID = formatRequestID
            context.coordinator.applyFormat(action)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DarkTextEditor
        weak var textView: DroppableTextView?
        weak var scrollView: NSScrollView?
        var lastFormatID: UUID?

        init(_ parent: DarkTextEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard let scrollView = scrollView, let docView = scrollView.documentView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let totalHeight = docView.bounds.height
            let maxOffset = max(totalHeight - visibleHeight, 1)
            let currentOffset = scrollView.contentView.bounds.origin.y
            let fraction = min(max(currentOffset / maxOffset, 0.0), 1.0)
            parent.onScroll(fraction)
        }

        func applyFormat(_ action: EditorFormatAction) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            let nsText = textView.string as NSString
            let selected = nsText.substring(with: range)

            let replacement: String
            let cursorOffset: Int

            switch action {
            case .bold:
                replacement = "**\(selected.isEmpty ? "粗体" : selected)**"
                cursorOffset = selected.isEmpty ? 2 : replacement.count
            case .italic:
                replacement = "*\(selected.isEmpty ? "斜体" : selected)*"
                cursorOffset = selected.isEmpty ? 1 : replacement.count
            case .inlineCode:
                replacement = "`\(selected.isEmpty ? "code" : selected)`"
                cursorOffset = selected.isEmpty ? 1 : replacement.count
            case .link:
                replacement = "[\(selected.isEmpty ? "链接文本" : selected)](https://)"
                cursorOffset = replacement.count - 1
            case .heading:
                replacement = "## \(selected)"
                cursorOffset = replacement.count
            }

            if textView.shouldChangeText(in: range, replacementString: replacement) {
                textView.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: range.location + cursorOffset, length: 0))
                parent.text = textView.string
            }
        }
    }
}
