import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NookEditorBridge: ObservableObject {
    weak var textView: NookTextView?

    @Published private(set) var errorMessage: String?
    @Published private(set) var hasUnsavedDraft = false
    fileprivate var retrySerialization: (() -> Void)?
    @Published private(set) var activeStyles: Set<NookTextStyle> = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    func attach(_ textView: NSTextView) {
        guard let textView = textView as? NookTextView else { return }
        guard self.textView !== textView else { return }
        self.textView = textView
        textView.onHistoryChange = { [weak self] in self?.refreshState() }
    }

    func focus() {
        textView?.window?.makeFirstResponder(textView)
    }

    func resignFocus() {
        textView?.window?.makeFirstResponder(nil)
    }

    func undo() {
        guard let manager = textView?.undoManager, manager.canUndo else { return }
        manager.undo()
        refreshState()
    }

    func redo() {
        guard let manager = textView?.undoManager, manager.canRedo else { return }
        manager.redo()
        refreshState()
    }

    func report(error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? (error as NSError).localizedDescription
    }

    func clearError() {
        if errorMessage != nil { errorMessage = nil }
    }

    /// Retry the native document, whose content can be newer than its bindings.
    @discardableResult
    func retrySave() -> Bool {
        guard textView != nil else { return !hasUnsavedDraft }
        retrySerialization?()
        return !hasUnsavedDraft
    }

    fileprivate func serializationDidFail(_ error: Error) {
        if !hasUnsavedDraft { hasUnsavedDraft = true }
        report(error: error)
    }

    fileprivate func serializationDidSucceed() {
        if hasUnsavedDraft { hasUnsavedDraft = false }
        clearError()
    }

    func refreshState() {
        let styles = textView?.formattingStyles ?? []
        let undo = textView?.undoManager?.canUndo ?? false
        let redo = textView?.undoManager?.canRedo ?? false
        if activeStyles != styles { activeStyles = styles }
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }

    func apply(_ style: NookTextStyle) {
        guard let textView, textView.isEditable, !textView.documentReadOnlyDueToError else { return }
        focus()
        let selection = textView.selectedRange()

        if style.isInline {
            if selection.length == 0 {
                textView.toggleTypingStyle(style)
                refreshState()
                return
            }

            let changed = textView.performDocumentMutation(
                in: selection,
                replacementString: nil,
                actionName: style.actionName
            ) {
                textView.applyInlineStyle(style, to: selection)
            }
            if changed {
                textView.setSelectedRange(selection)
                refreshState()
            }
            return
        }

        let paragraphRange = textView.paragraphRange(for: selection)
        guard paragraphRange.length > 0 else {
            textView.applyBlockTypingStyle(style)
            if style.isListStyle {
                let marker = NSAttributedString(string: style.listMarker(number: 1), attributes: textView.typingAttributes)
                if textView.performDocumentReplacement(in: paragraphRange, with: marker, actionName: style.actionName) {
                    textView.setSelectedRange(NSRange(location: paragraphRange.location + marker.length, length: 0))
                }
            }
            refreshState()
            return
        }

        var resultingSelection = paragraphRange
        let changed = textView.performDocumentMutation(
            in: paragraphRange,
            replacementString: nil,
            actionName: style.actionName
        ) {
            resultingSelection = textView.applyBlockStyle(style, to: paragraphRange)
        }
        if changed {
            textView.setSelectedRange(resultingSelection)
            refreshState()
        }
    }

    /// Inserts a real TextKit table into the document. Each cell is its own
    /// paragraph carrying an NSTextTableBlock, so borders are drawn by
    /// AppKit rather than being made from box-drawing characters. Every cell
    /// remains a normal editable text range.
    func insertTable(rows: Int = 3, columns: Int = 2) {
        guard let textView, textView.isEditable, !textView.documentReadOnlyDueToError else { return }
        let range = textView.selectedRange()
        let string = textView.string as NSString
        let rangeEnd = range.location + range.length
        let needsLeadingBreak = range.location > 0 && string.character(at: range.location - 1) != 10
        let needsTrailingBreak = rangeEnd < string.length && string.character(at: rangeEnd) != 10
        let attributed = makeTable(
            rows: rows,
            columns: columns,
            textColor: textView.defaultInk
        )

        if needsLeadingBreak {
            attributed.insert(
                NSAttributedString(
                    string: "\n",
                    attributes: NookTextView.bodyTypingAttributes(for: textView.defaultInk)
                ),
                at: 0
            )
        }
        if needsTrailingBreak {
            attributed.append(
                NSAttributedString(
                    string: "\n",
                    attributes: NookTextView.bodyTypingAttributes(for: textView.defaultInk)
                )
            )
        }

        guard textView.performDocumentReplacement(
            in: range,
            with: attributed,
            actionName: "Insert Table"
        ) else { return }

        let firstCellLocation = range.location + (needsLeadingBreak ? 1 : 0)
        textView.setSelectedRange(NSRange(location: firstCellLocation, length: 0))
        focus()
        refreshState()
    }

    /// Opens the photo/video picker. Images are rendered directly in the
    /// writing stream and are stored as file-backed attachments.
    func insertPhotoOrVideo() {
        chooseAttachment(allowedContentTypes: [.image, .movie], inlineImages: true)
    }

    /// Opens the general file picker. Image files selected here remain file
    /// attachments, keeping the paperclip action distinct from Photos.
    func insertFileAttachment() {
        chooseAttachment(allowedContentTypes: [.data], inlineImages: false)
    }

    private func chooseAttachment(allowedContentTypes: [UTType], inlineImages: Bool) {
        guard let textView, textView.isEditable, !textView.documentReadOnlyDueToError, attachmentPanel == nil else { return }
        guard textView.window?.attachedSheet == nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedContentTypes

        // Keep the panel alive through either a sheet or app-modal completion.
        attachmentPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { [self] response in
            defer { self.attachmentPanel = nil }
            guard response == .OK, let url = panel.url else { return }
            self.insertFile(url, inlineImage: inlineImages)
        }

        if let window = textView.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private var attachmentPanel: NSOpenPanel?

    private func insertFile(_ url: URL, inlineImage: Bool) {
        guard let textView, textView.isEditable, !textView.documentReadOnlyDueToError else { return }

        do {
            let attachment: NSTextAttachment
            let isImage = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
            if inlineImage, isImage {
                guard let image = NSImage(contentsOf: url) else { throw NookRichDocument.DocumentError.unreadableImage }
                attachment = try NookRichDocument.imageAttachment(
                    image,
                    filename: url.lastPathComponent,
                    maxWidth: 320
                )
            } else if let wrapper = try? FileWrapper(url: url, options: .immediate) {
                attachment = NSTextAttachment(fileWrapper: wrapper)
            } else {
                throw NookRichDocument.DocumentError.missingAttachment
            }

            if inlineImage, isImage {
                guard textView.insertBlockImage(attachment, actionName: "Insert Photo") else { return }
                focus()
                refreshState()
                return
            }
            let inserted = NSAttributedString(attachment: attachment)
            let range = textView.selectedRange()
            guard textView.performDocumentReplacement(
                in: range,
                with: inserted,
                actionName: "Insert Attachment"
            ) else { return }

            textView.setSelectedRange(NSRange(location: range.location + inserted.length, length: 0))
            focus()
            refreshState()
        } catch {
            report(error: error)
        }
    }

    private func makeTable(rows: Int, columns: Int, textColor: NSColor) -> NSMutableAttributedString {
        let rowCount = max(rows, 1)
        let columnCount = max(columns, 1)
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = NSTextTable.LayoutAlgorithm(rawValue: 1)!
        table.collapsesBorders = false
        table.hidesEmptyCells = false

        let borderColor = textColor.withAlphaComponent(0.28)
        let result = NSMutableAttributedString(string: "")

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: row,
                    rowSpan: 1,
                    startingColumn: column,
                    columnSpan: 1
                )
                block.setContentWidth(
                    100 / CGFloat(columnCount),
                    type: NSTextBlock.ValueType(rawValue: 1)!
                )
                block.setWidth(
                    1,
                    type: NSTextBlock.ValueType(rawValue: 0)!,
                    for: NSTextBlock.Layer(rawValue: 0)!
                )
                block.setWidth(
                    8,
                    type: NSTextBlock.ValueType(rawValue: 0)!,
                    for: NSTextBlock.Layer(rawValue: -1)!
                )
                block.setBorderColor(borderColor)
                block.verticalAlignment = NSTextBlock.VerticalAlignment(rawValue: 0)!

                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacing = 0
                paragraph.textBlocks = [block]
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph
                ]
                // Keep a real editable character in an empty cell. The
                // paragraph terminator remains the cell boundary.
                result.append(NSAttributedString(string: " \n", attributes: attributes))
            }
        }

        // A plain paragraph after the table gives the user an escape route
        // for continuing to type below it without creating another cell.
        result.append(NSAttributedString(
            string: "\n",
            attributes: NookTextView.bodyTypingAttributes(for: textColor)
        ))
        return result
    }
}

enum NookTextStyle: Hashable {
    case bold
    case italic
    case underline
    case strikethrough
    case code
    case title
    case heading
    case subheading
    case body
    case monospaced
    case bulleted
    case dashed
    case numbered
    case blockquote

    var isInline: Bool {
        switch self {
        case .bold, .italic, .underline, .strikethrough, .code: return true
        default: return false
        }
    }

    var actionName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .code: return "Code"
        case .title: return "Title"
        case .heading: return "Heading"
        case .subheading: return "Subheading"
        case .body: return "Body"
        case .monospaced: return "Monospaced"
        case .bulleted: return "Bulleted List"
        case .dashed: return "Dashed List"
        case .numbered: return "Numbered List"
        case .blockquote: return "Block Quote"
        }
    }
}

private enum NookEditorLoadError: LocalizedError {
    case invalidRichDocument
    case richDocumentDoesNotMatchText

    var errorDescription: String? {
        switch self {
        case .invalidRichDocument:
            return "The saved rich document could not be opened. The previous rich data was kept."
        case .richDocumentDoesNotMatchText:
            return "The saved rich document does not match this note's text. The previous rich data was kept."
        }
    }
}

struct NookRichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richData: Data?
    @Binding var selection: NSRange
    let isDark: Bool
    let placeholder: String
    let startsWithTitle: Bool
    let bridge: NookEditorBridge
    var onDocumentChange: (String, Data) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none

        let textView = NookTextView()
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.configureAppearance(isDark: isDark)
        textView.insertionPointColor = isDark ? NSColor.white : NSColor.black
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(calibratedRed: 0.99, green: 0.72, blue: 0.16, alpha: 0.75),
            .foregroundColor: isDark ? NSColor.black : NookPalette.cardInkNS
        ]
        textView.textContainerInset = NSSize(
            width: NookLayout.editorTextInset,
            height: NookLayout.editorTextVerticalInset
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        // TextKit must repaint behind the insertion caret. A transparent
        // NSTextView leaves caret trails across inline images on layer-backed windows.
        textView.drawsBackground = true
        textView.backgroundColor = NookPalette.editorCanvasNS(isDark: isDark)
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.startsWithTitle = startsWithTitle
        textView.importsGraphics = false
        textView.usesFontPanel = false

        context.coordinator.textView = textView
        context.coordinator.parent = self
        bridge.attach(textView)
        textView.onFormat = { [weak bridge] style in
            bridge?.apply(style)
        }
        textView.onPasteError = { [weak bridge] error in
            bridge?.report(error: error)
        }

        let loadError = context.coordinator.installDocument(
            in: textView,
            text: text,
            richData: richData,
            startsWithTitle: startsWithTitle
        )
        if let loadError {
            // Avoid publishing while SwiftUI is still constructing the view.
            DispatchQueue.main.async { [weak bridge] in
                bridge?.report(error: loadError)
            }
        }

        textView.delegate = context.coordinator
        DispatchQueue.main.async { [weak bridge] in bridge?.refreshState() }
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NookTextView else { return }
        context.coordinator.textView = textView
        bridge.attach(textView)
        // Changing textColor on every SwiftUI echo rewrites the default color
        // attribute and destroys per-run colors in a rich document.
        textView.configureAppearance(isDark: isDark)

        // The note ID owns this view's lifetime. Bindings only mirror successful
        // native saves; a stale render must never replace an unsaved document.
        textView.backgroundColor = NookPalette.editorCanvasNS(isDark: isDark)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NookRichTextEditor
        weak var textView: NookTextView?
        private var isSynchronizing = false

        init(_ parent: NookRichTextEditor) {
            self.parent = parent
            super.init()
            parent.bridge.retrySerialization = { [weak self] in self?.syncFromTextView() }
        }

        @discardableResult
        func installDocument(
            in textView: NookTextView,
            text: String,
            richData: Data?,
            startsWithTitle: Bool
        ) -> Error? {
            textView.documentReadOnlyDueToError = false
            textView.textStorage?.setAttributedString(NSAttributedString(string: text))

            if let richData {
                do {
                    let attributed = try NookRichDocument.decode(richData)
                    guard attributed.string == text else {
                        throw NookEditorLoadError.richDocumentDoesNotMatchText
                    }
                    textView.textStorage?.setAttributedString(attributed)
                    textView.isEditable = true
                    textView.normalizeDefaultInk()
                    textView.normalizeStandalonePhotoSpacing()
                    textView.updateTypingAttributesForCurrentPosition()
                    return nil
                } catch let error as NookEditorLoadError {
                    textView.documentReadOnlyDueToError = true
                    textView.isEditable = false
                    return error
                } catch {
                    textView.documentReadOnlyDueToError = true
                    textView.isEditable = false
                    return NookEditorLoadError.invalidRichDocument
                }
            }

            textView.isEditable = true
            if startsWithTitle {
                textView.applyDefaultDocumentStyle()
            } else {
                textView.applyDefaultBodyDocumentStyle()
            }
            textView.normalizeDefaultInk()
            textView.updateTypingAttributesForCurrentPosition()
            return nil
        }

        @MainActor
        func syncFromTextView() {
            guard let textView,
                  !textView.documentReadOnlyDueToError,
                  !isSynchronizing else { return }
            isSynchronizing = true
            defer { isSynchronizing = false }

            let attributed = textView.attributedString()
            do {
                let data = try NookRichDocument.encode(attributed)
                // Keep the text/data binding pair atomic. If serialization
                // fails, the controller's last recoverable pair is retained.
                parent.text = textView.string
                parent.richData = data
                parent.selection = textView.selectedRange()
                parent.onDocumentChange(textView.string, data)
                parent.bridge.serializationDidSucceed()
            } catch {
                parent.bridge.serializationDidFail(error)
                parent.selection = textView.selectedRange()
            }
            refreshState()
        }

        @MainActor
        func textDidChange(_ notification: Notification) {
            syncFromTextView()
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            parent.selection = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            textView?.sanitizeTypingAttributes()
            refreshState()
        }

        @MainActor
        func refreshState() {
            parent.bridge.refreshState()
        }
    }
}

final class NookTextView: NSTextView {
    private static let titleFont = NSFont.systemFont(ofSize: 25, weight: .bold)
    private static let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)

    var startsWithTitle = true
    var onFormat: ((NookTextStyle) -> Void)?
    var onPasteError: ((Error) -> Void)?
    var onHistoryChange: (() -> Void)?
    var documentReadOnlyDueToError = false

    private let documentUndoManager = UndoManager()
    override var undoManager: UndoManager? { documentUndoManager }
    override var acceptsFirstResponder: Bool { true }

    private var editorIsDark = false
    private var configuredAppearance = false
    var defaultInk: NSColor { editorIsDark ? .white : NookPalette.cardInkNS }

    func configureAppearance(isDark: Bool) {
        guard !configuredAppearance || editorIsDark != isDark else { return }
        configuredAppearance = true
        editorIsDark = isDark
        appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        insertionPointColor = isDark ? .white : .black
        backgroundColor = NookPalette.editorCanvasNS(isDark: isDark)
        normalizeDefaultInk()
        sanitizeTypingAttributes()
        needsDisplay = true
    }

    private static let knownDefaultInks: [NSColor] = {
        var values: [NSColor] = [.black, .white, NookPalette.cardInkNS]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                if let color = NSColor.textColor.usingColorSpace(.sRGB) { values.append(color) }
            }
        }
        return values
    }()

    private func readableInk(_ color: NSColor?) -> NSColor {
        guard let color else { return defaultInk }
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        let isDefault = Self.knownDefaultInks.contains { candidate in
            guard let value = candidate.usingColorSpace(.sRGB) else { return false }
            // RTF stores 8-bit components, so allow just one quantization step.
            return abs(rgb.redComponent - value.redComponent) <= 1.0 / 255 + 0.0001
                && abs(rgb.greenComponent - value.greenComponent) <= 1.0 / 255 + 0.0001
                && abs(rgb.blueComponent - value.blueComponent) <= 1.0 / 255 + 0.0001
                && abs(rgb.alphaComponent - value.alphaComponent) < 0.001
        }
        return isDefault ? defaultInk : color
    }

    func normalizeDefaultInk() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let runs = attributeRuns(in: NSRange(location: 0, length: storage.length))
        storage.beginEditing()
        for run in runs {
            let existing = run.attributes[.foregroundColor] as? NSColor
            let ink = readableInk(existing)
            if existing != ink { storage.addAttribute(.foregroundColor, value: ink, range: run.range) }
        }
        storage.endEditing()
    }

    func normalizeStandalonePhotoSpacing() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let paragraphs = paragraphRanges(in: NSRange(location: 0, length: storage.length))
        for range in paragraphs {
            let paragraphText = (storage.string as NSString).substring(with: range)
            guard paragraphText.trimmingCharacters(in: .newlines) == "\u{fffc}",
                  let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                  let bytes = attachment.fileWrapper?.regularFileContents,
                  NSImage(data: bytes) != nil else { continue }
            let paragraph = mutableParagraphStyle(from: storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
            let needsBefore = paragraph.paragraphSpacingBefore == 0
            let needsAfter = paragraph.paragraphSpacing == 0
            guard needsBefore || needsAfter else { continue }
            if needsBefore { paragraph.paragraphSpacingBefore = 10 }
            if needsAfter { paragraph.paragraphSpacing = 10 }
            storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
    }

    private func sanitizedTypingAttributes(_ value: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = value
        attributes.removeValue(forKey: .attachment)
        if attributes[.font] == nil { attributes[.font] = Self.bodyFont }
        attributes[.foregroundColor] = readableInk(attributes[.foregroundColor] as? NSColor)
        if attributes[.paragraphStyle] == nil { attributes[.paragraphStyle] = Self.bodyParagraphStyle() }
        return attributes
    }

    override var typingAttributes: [NSAttributedString.Key: Any] {
        get { super.typingAttributes }
        set { super.typingAttributes = sanitizedTypingAttributes(newValue) }
    }

    func sanitizeTypingAttributes() {
        typingAttributes = super.typingAttributes
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        sanitizeTypingAttributes()
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if flag {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: true)
        } else {
            // Erasing with a flat canvas color damages an attachment beneath a
            // tall insertion caret. Let TextKit repaint its glyphs and image.
            setNeedsDisplay(visibleRect)
        }
    }

    var formattingStyles: Set<NookTextStyle> {
        let attrs = formattingAttributes
        var result = Set<NookTextStyle>()
        if let font = attrs[.font] as? NSFont {
            if font.fontDescriptor.symbolicTraits.contains(.bold) { result.insert(.bold) }
            if font.fontDescriptor.symbolicTraits.contains(.italic) { result.insert(.italic) }
            if font.fontDescriptor.symbolicTraits.contains(.monoSpace) { result.insert(.code) }
        }
        if ((attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0 {
            result.insert(.underline)
        }
        if ((attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0 {
            result.insert(.strikethrough)
        }
        if let marker = listMarker(at: selectedRange().location)?.kind {
            switch marker {
            case .bullet: result.insert(.bulleted)
            case .dash: result.insert(.dashed)
            case .number: result.insert(.numbered)
            case .blockquote: result.insert(.blockquote)
            }
        }
        return result
    }

    /// A blank document starts in title typography. Once the first paragraph
    /// exists, its following paragraphs use the normal body size. This is
    /// deliberately applied only when opening plain/legacy content.
    func applyDefaultDocumentStyle() {
        guard let storage = textStorage else {
            typingAttributes = titleTypingAttributes()
            return
        }
        guard storage.length > 0 else {
            typingAttributes = titleTypingAttributes()
            return
        }

        let firstParagraph = (string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        storage.beginEditing()
        storage.addAttribute(.font, value: Self.titleFont, range: firstParagraph)
        storage.addAttribute(.paragraphStyle, value: Self.titleParagraphStyle(), range: firstParagraph)

        let bodyStart = firstParagraph.location + firstParagraph.length
        if bodyStart < storage.length {
            storage.addAttribute(
                .font,
                value: Self.bodyFont,
                range: NSRange(location: bodyStart, length: storage.length - bodyStart)
            )
            storage.addAttribute(
                .paragraphStyle,
                value: Self.bodyParagraphStyle(),
                range: NSRange(location: bodyStart, length: storage.length - bodyStart)
            )
        }
        storage.endEditing()
    }

    func applyDefaultBodyDocumentStyle() {
        guard let storage = textStorage else {
            typingAttributes = bodyTypingAttributes()
            return
        }
        guard storage.length > 0 else {
            typingAttributes = bodyTypingAttributes()
            return
        }

        storage.beginEditing()
        storage.addAttribute(.font, value: Self.bodyFont, range: NSRange(location: 0, length: storage.length))
        storage.addAttribute(.paragraphStyle, value: Self.bodyParagraphStyle(), range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        typingAttributes = bodyTypingAttributes()
    }

    func updateTypingAttributesForCurrentPosition() {
        guard selectedRange().length == 0 else { return }
        guard let storage = textStorage, storage.length > 0 else {
            if typingAttributes.isEmpty {
                typingAttributes = startsWithTitle ? titleTypingAttributes() : bodyTypingAttributes()
            }
            return
        }

        let caret = min(max(selectedRange().location, 0), storage.length)
        var location = min(caret, storage.length - 1)
        if caret > 0,
           (string as NSString).character(at: caret - 1) == 10,
           caret < storage.length {
            location = caret
        }
        var attributes = storage.attributes(at: location, effectiveRange: nil)
        attributes.removeValue(forKey: .attachment)
        typingAttributes = attributes
    }

    func paragraphRange(for selection: NSRange) -> NSRange {
        guard let storage = textStorage, storage.length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let location = min(max(selection.location, 0), storage.length)
        let length = min(selection.length, storage.length - location)
        return (string as NSString).paragraphRange(for: NSRange(location: location, length: length))
    }

    func toggleTypingStyle(_ style: NookTextStyle) {
        var attributes = typingAttributes
        switch style {
        case .bold, .italic:
            let font = attributes[.font] as? NSFont ?? Self.bodyFont
            let trait: NSFontDescriptor.SymbolicTraits = style == .bold ? .bold : .italic
            let currentTraits = font.fontDescriptor.symbolicTraits
            let nextTraits = currentTraits.contains(trait)
                ? currentTraits.subtracting(trait)
                : currentTraits.union(trait)
            let descriptor = font.fontDescriptor.withSymbolicTraits(nextTraits)
            if let nextFont = NSFont(descriptor: descriptor, size: font.pointSize) {
                attributes[.font] = nextFont
            }
        case .underline:
            toggleNumberAttribute(.underlineStyle, in: &attributes)
        case .strikethrough:
            toggleNumberAttribute(.strikethroughStyle, in: &attributes)
        case .code:
            let font = attributes[.font] as? NSFont ?? Self.bodyFont
            let isCode = font.fontDescriptor.symbolicTraits.contains(.monoSpace)
            if isCode {
                attributes[.font] = NSFont.systemFont(ofSize: font.pointSize)
                attributes.removeValue(forKey: .backgroundColor)
            } else {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                attributes[.backgroundColor] = NSColor.black.withAlphaComponent(0.12)
            }
        default:
            break
        }
        typingAttributes = attributes
    }

    func applyInlineStyle(_ style: NookTextStyle, to range: NSRange) {
        guard let storage = textStorage, range.length > 0 else { return }
        let runs = attributeRuns(in: range)
        switch style {
        case .bold, .italic:
            let trait: NSFontDescriptor.SymbolicTraits = style == .bold ? .bold : .italic
            let allHaveTrait = runs.allSatisfy { run in
                let font = run.attributes[.font] as? NSFont ?? Self.bodyFont
                return font.fontDescriptor.symbolicTraits.contains(trait)
            }
            for run in runs {
                let font = run.attributes[.font] as? NSFont ?? Self.bodyFont
                let currentTraits = font.fontDescriptor.symbolicTraits
                let nextTraits = allHaveTrait
                    ? currentTraits.subtracting(trait)
                    : currentTraits.union(trait)
                let descriptor = font.fontDescriptor.withSymbolicTraits(nextTraits)
                if let nextFont = NSFont(descriptor: descriptor, size: font.pointSize) {
                    storage.addAttribute(.font, value: nextFont, range: run.range)
                }
            }
        case .underline, .strikethrough:
            let key: NSAttributedString.Key = style == .underline ? .underlineStyle : .strikethroughStyle
            let allHaveStyle = runs.allSatisfy {
                (($0.attributes[key] as? NSNumber)?.intValue ?? 0) != 0
            }
            if allHaveStyle {
                storage.removeAttribute(key, range: range)
            } else {
                storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        case .code:
            let allCode = runs.allSatisfy {
                ($0.attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true
            }
            for run in runs {
                let font = run.attributes[.font] as? NSFont ?? Self.bodyFont
                let base = allCode ? NSFont.systemFont(ofSize: font.pointSize)
                    : NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                let retainedTraits = font.fontDescriptor.symbolicTraits.intersection([.bold, .italic])
                let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(retainedTraits))
                storage.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? base, range: run.range)
                if allCode {
                    storage.removeAttribute(.backgroundColor, range: run.range)
                } else {
                    storage.addAttribute(.backgroundColor, value: NSColor.black.withAlphaComponent(0.12), range: run.range)
                }
            }
        default:
            break
        }
    }

    @discardableResult
    func applyBlockStyle(_ style: NookTextStyle, to range: NSRange) -> NSRange {
        guard let storage = textStorage, range.length > 0 else { return range }
        let lines = paragraphRanges(in: range)
        let removeList = style.isListStyle && lines.allSatisfy { listMarker(in: $0)?.kind == style.listKind }
        var delta = 0
        // Work backwards so earlier prefixes never invalidate later ranges.
        for index in lines.indices.reversed() {
            let line = lines[index]
            let attributes = markerAttributes(at: line.location)
            let removed = listMarker(in: line)?.length ?? 0
            let marker = style.isListStyle && !removeList ? style.listMarker(number: index + 1) : ""
            storage.replaceCharacters(in: NSRange(location: line.location, length: removed),
                                      with: NSAttributedString(string: marker, attributes: attributes))
            let length = line.length - removed + marker.utf16.count
            delta += marker.utf16.count - removed
            if length > 0 {
                applyParagraphStyle(removeList ? .body : style, to: NSRange(location: line.location, length: length))
            }
        }
        return NSRange(location: range.location, length: min(storage.length - range.location, max(0, range.length + delta)))
    }

    func applyBlockTypingStyle(_ style: NookTextStyle) {
        var attributes = typingAttributes
        if style.isListStyle {
            let paragraph = mutableParagraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
            applyListParagraphStyle(style, to: paragraph)
            attributes[.paragraphStyle] = paragraph
        } else {
            applyBlockAttributes(style, to: &attributes)
        }
        typingAttributes = attributes
    }

    override func insertNewline(_ sender: Any?) {
        guard isEditable, !documentReadOnlyDueToError else { return }
        sanitizeTypingAttributes()
        if let context = listContinuationContext(), !isInsideTable(at: context.paragraph.location) {
            if context.isEmptyItem {
                let markerRange = NSRange(location: context.paragraph.location, length: context.marker.length)
                if performDocumentReplacement(in: markerRange, with: NSAttributedString(string: ""), actionName: "Exit List") {
                    setSelectedRange(NSRange(location: markerRange.location, length: 0))
                    applyBlockTypingStyle(.body)
                }
                return
            }

            let marker: String
            switch context.marker.kind {
            case .bullet: marker = "• "
            case .dash: marker = "– "
            case .blockquote: marker = "│ "
            case .number: marker = "\((context.marker.number ?? 0) + 1). "
            }
            var attrs = markerAttributes(at: context.paragraph.location)
            attrs.removeValue(forKey: .attachment)
            let continuation = NSMutableAttributedString(string: "\n\(marker)", attributes: attrs)
            let insertionRange = selectedRange()
            if performDocumentReplacement(in: insertionRange, with: continuation, actionName: "Continue List") {
                setSelectedRange(NSRange(location: insertionRange.location + continuation.length, length: 0))
            }
            return
        }

        let isHeading = ((typingAttributes[.font] as? NSFont)?.pointSize ?? 14) >= 17
        super.insertNewline(sender)
        if isHeading && !isInsideTable(at: selectedRange().location) {
            applyBlockTypingStyle(.body)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditorShortcut(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handleEditorShortcut(event) { super.keyDown(with: event) }
    }

    private func handleEditorShortcut(_ event: NSEvent) -> Bool {
        // Toolbar shortcuts must never steal undo from the separate title field.
        guard window?.firstResponder === self,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isUndo = key == "z" && (modifiers == [.command] || modifiers == [.control])
        let isRedo = (key == "z" && (modifiers == [.command, .shift] || modifiers == [.control, .shift]))
            || (key == "y" && (modifiers == [.command] || modifiers == [.control]))
        if isUndo || isRedo {
            guard isEditable, !documentReadOnlyDueToError else { return true }
            if isUndo, undoManager?.canUndo == true { undoManager?.undo() }
            if isRedo, undoManager?.canRedo == true { undoManager?.redo() }
            onHistoryChange?()
            return true
        }
        guard modifiers == [.command], let onFormat else { return false }
        switch key {
        case "b": onFormat(.bold); return true
        case "i": onFormat(.italic); return true
        case "u": onFormat(.underline); return true
        default: return false
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let image = image(at: point) else { return super.menu(for: event) }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Copy Image", action: #selector(copyContextImage(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = image
        menu.addItem(item)
        return menu
    }

    // Require a hit inside the attachment, rather than the nearest character:
    // blank space beside a photo must retain the normal text menu.
    func image(at point: NSPoint) -> NSImage? {
        guard let layoutManager, let textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: location, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                         in: textContainer).contains(location) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment else { return nil }
        if let bytes = attachment.fileWrapper?.regularFileContents {
            // Non-image file attachments can have an image icon; do not copy it.
            return NSImage(data: bytes)
        }
        guard attachment.fileWrapper == nil else { return nil }
        return attachment.image ?? (attachment.attachmentCell as? NSTextAttachmentCell)?.image
    }

    @objc private func copyContextImage(_ sender: NSMenuItem) {
        guard let image = sender.representedObject as? NSImage else { return }
        if !copyImage(image, to: .general) { NSSound.beep() }
    }

    @discardableResult
    func copyImage(_ image: NSImage, to pasteboard: NSPasteboard) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    override func paste(_ sender: Any?) {
        paste(from: .general)
    }

    func paste(from pasteboard: NSPasteboard) {
        guard isEditable, !documentReadOnlyDueToError else { return }

        if let rich = richAttributedString(from: pasteboard) {
            do {
                let normalized = try materializeAttachments(in: rich)
                if normalized.length == 1,
                   let attachment = normalized.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
                   let bytes = attachment.fileWrapper?.regularFileContents, NSImage(data: bytes) != nil {
                    _ = insertBlockImage(attachment, actionName: "Paste Image")
                    return
                }
                let insertionRange = selectedRange()
                if performDocumentReplacement(in: insertionRange, with: normalized, actionName: "Paste Rich Text") {
                    setSelectedRange(NSRange(location: insertionRange.location + normalized.length, length: 0))
                }
            } catch {
                onPasteError?(error)
            }
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            do {
                let attachment = try NookRichDocument.imageAttachment(image, maxWidth: 320)
                _ = insertBlockImage(attachment, actionName: "Paste Image")
            } catch {
                onPasteError?(error)
            }
            return
        }

        // Avoid AppKit's HTML importer, which may fetch remote image URLs.
        if let plain = pasteboard.string(forType: .string) {
            insertText(plain, replacementRange: selectedRange())
        }
    }

    @discardableResult
    func insertBlockImage(_ attachment: NSTextAttachment, actionName: String) -> Bool {
        guard let storage = textStorage, isEditable, !documentReadOnlyDueToError else { return false }
        var replacementRange = selectedRange()
        let current = storage.string as NSString
        let start = replacementRange.location
        let end = NSMaxRange(replacementRange)
        guard start <= current.length, end <= current.length else { return false }
        let needsLeadingBreak = start > 0 && current.character(at: start - 1) != 10
        // Reuse an existing paragraph boundary instead of leaving an empty line.
        if end < current.length && current.character(at: end) == 10 { replacementRange.length += 1 }

        let surrounding = sanitizedTypingAttributes(typingAttributes)
        var following = surrounding
        let paragraph = mutableParagraphStyle(from: surrounding[.paragraphStyle] as? NSParagraphStyle)
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.textLists = []
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        following[.paragraphStyle] = paragraph
        let font = surrounding[.font] as? NSFont ?? Self.bodyFont
        if [17.0, 21.0, 25.0, 26.0].contains(font.pointSize) {
            following[.font] = Self.bodyFont
        }
        let photoParagraph = mutableParagraphStyle(from: paragraph)
        photoParagraph.paragraphSpacingBefore = 10
        photoParagraph.paragraphSpacing = 10
        var photoAttributes = following
        photoAttributes[.paragraphStyle] = photoParagraph
        photoAttributes[.attachment] = attachment

        let inserted = NSMutableAttributedString(string: "")
        if needsLeadingBreak { inserted.append(NSAttributedString(string: "\n", attributes: surrounding)) }
        inserted.append(NSAttributedString(string: "\u{fffc}", attributes: photoAttributes))
        var terminator = photoAttributes
        terminator.removeValue(forKey: .attachment)
        inserted.append(NSAttributedString(string: "\n", attributes: terminator))
        guard performDocumentReplacement(in: replacementRange, with: inserted, actionName: actionName) else { return false }
        setSelectedRange(NSRange(location: start + inserted.length, length: 0))
        typingAttributes = following
        onHistoryChange?()
        return true
    }

    @discardableResult
    func performDocumentReplacement(
        in range: NSRange,
        with replacement: NSAttributedString,
        actionName: String
    ) -> Bool {
        let inserted = NSMutableAttributedString(attributedString: replacement)
        let defaults = sanitizedTypingAttributes(typingAttributes)
        var missing: [(NSRange, [NSAttributedString.Key: Any])] = []
        inserted.enumerateAttributes(in: NSRange(location: 0, length: inserted.length)) { attributes, range, _ in
            guard attributes[.attachment] != nil else { return }
            var additions: [NSAttributedString.Key: Any] = [:]
            for key in [NSAttributedString.Key.font, .foregroundColor, .paragraphStyle] where attributes[key] == nil {
                additions[key] = defaults[key]
            }
            missing.append((range, additions))
        }
        for (range, attributes) in missing { inserted.addAttributes(attributes, range: range) }
        return performDocumentMutation(
            in: range,
            replacementString: inserted.string,
            actionName: actionName
        ) {
            self.textStorage?.replaceCharacters(in: range, with: inserted)
        }
    }

    @discardableResult
    func performDocumentMutation(
        in range: NSRange,
        replacementString: String?,
        actionName: String,
        mutation: () -> Void
    ) -> Bool {
        guard let storage = textStorage, isEditable, !documentReadOnlyDueToError,
              range.location >= 0, range.length >= 0, NSMaxRange(range) <= storage.length else { return false }
        let before = NSAttributedString(attributedString: attributedString())
        let beforeSelection = selectedRange()
        let beforeTypingAttributes = typingAttributes
        breakUndoCoalescing()
        let manager = undoManager
        manager?.disableUndoRegistration()
        guard shouldChangeText(in: range, replacementString: replacementString) else {
            manager?.enableUndoRegistration()
            return false
        }
        storage.beginEditing()
        mutation()
        storage.endEditing()
        manager?.enableUndoRegistration()
        guard !before.isEqual(to: attributedString()) else { return false }
        registerDocumentUndo(before: before, selection: beforeSelection, typing: beforeTypingAttributes, actionName: actionName)
        manager?.setActionName(actionName)
        didChangeText()
        return true
    }

    private func registerDocumentUndo(
        before: NSAttributedString,
        selection: NSRange,
        typing: [NSAttributedString.Key: Any],
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDocument(before, selection: selection, typing: typing, actionName: actionName)
        }
    }

    private func restoreDocument(
        _ value: NSAttributedString,
        selection: NSRange,
        typing: [NSAttributedString.Key: Any],
        actionName: String
    ) {
        guard let storage = textStorage else { return }
        let current = NSAttributedString(attributedString: attributedString())
        let currentSelection = selectedRange()
        let currentTypingAttributes = typingAttributes
        undoManager?.disableUndoRegistration()
        storage.setAttributedString(value)
        normalizeDefaultInk()
        let location = min(selection.location, storage.length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, storage.length - location)))
        typingAttributes = typing
        undoManager?.enableUndoRegistration()
        registerDocumentUndo(before: current, selection: currentSelection, typing: currentTypingAttributes, actionName: actionName)
        undoManager?.setActionName(actionName)
        didChangeText()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enclosingScrollView?.drawsBackground = false
    }

    private var formattingAttributes: [NSAttributedString.Key: Any] {
        let selection = selectedRange()
        guard selection.length > 0, let storage = textStorage, storage.length > 0 else { return typingAttributes }
        return storage.attributes(at: min(selection.location, storage.length - 1), effectiveRange: nil)
    }

    private func attributeRuns(
        in range: NSRange
    ) -> [(range: NSRange, attributes: [NSAttributedString.Key: Any])] {
        guard let storage = textStorage else { return [] }
        var runs: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            runs.append((run, attributes))
        }
        return runs
    }

    private func markerAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
        guard let storage = textStorage, storage.length > 0 else { return typingAttributes }
        let safeLocation = min(max(location, 0), storage.length - 1)
        var attrs = storage.attributes(at: safeLocation, effectiveRange: nil)
        attrs.removeValue(forKey: .attachment)
        return attrs
    }

    private func paragraphRanges(in range: NSRange) -> [NSRange] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        let string = storage.string as NSString
        let end = min(NSMaxRange(range), string.length)
        var location = min(max(range.location, 0), string.length - 1)
        var result: [NSRange] = []
        while location < end {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            if paragraph.length == 0 { break }
            result.append(paragraph)
            let next = NSMaxRange(paragraph)
            if next <= location { break }
            location = next
        }
        if result.isEmpty {
            result.append(string.paragraphRange(for: NSRange(location: min(range.location, string.length - 1), length: 0)))
        }
        return result
    }

    private func applyParagraphStyle(_ style: NookTextStyle, to range: NSRange) {
        guard let storage = textStorage, range.length > 0 else { return }
        let paragraph = mutableParagraphStyle(
            from: storage.attribute(
                .paragraphStyle,
                at: min(range.location, storage.length - 1),
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        if style == .blockquote {
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = 14
            paragraph.paragraphSpacing = 4
        } else if style.isListStyle {
            applyListParagraphStyle(style, to: paragraph)
        } else {
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = 0
            paragraph.textLists = []
            paragraph.paragraphSpacing = style == .title ? NookLayout.titleBodyGap : 0
        }
        storage.addAttribute(.paragraphStyle, value: paragraph, range: range)

        switch style {
        case .title:
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 26, weight: .bold), range: range)
        case .heading:
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 21, weight: .semibold), range: range)
        case .subheading:
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 17, weight: .semibold), range: range)
        case .body:
            storage.addAttribute(.font, value: Self.bodyFont, range: range)
        case .monospaced:
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: range)
        default:
            break
        }
    }

    private func applyBlockAttributes(
        _ style: NookTextStyle,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        switch style {
        case .title: attributes[.font] = NSFont.systemFont(ofSize: 26, weight: .bold)
        case .heading: attributes[.font] = NSFont.systemFont(ofSize: 21, weight: .semibold)
        case .subheading: attributes[.font] = NSFont.systemFont(ofSize: 17, weight: .semibold)
        case .body: attributes[.font] = Self.bodyFont
        case .monospaced: attributes[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        default: break
        }
        let paragraph = mutableParagraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.textLists = []
        paragraph.paragraphSpacing = style == .title ? NookLayout.titleBodyGap : 0
        attributes[.paragraphStyle] = paragraph
    }

    private func applyListParagraphStyle(_ style: NookTextStyle, to paragraph: NSMutableParagraphStyle) {
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = style == .blockquote ? 14 : 18
        paragraph.paragraphSpacing = style == .blockquote ? 4 : 0
    }

    private func mutableParagraphStyle(from value: NSParagraphStyle?) -> NSMutableParagraphStyle {
        if let value, let mutable = value.mutableCopy() as? NSMutableParagraphStyle {
            return mutable
        }
        return NSMutableParagraphStyle()
    }

    private func toggleNumberAttribute(
        _ key: NSAttributedString.Key,
        in attributes: inout [NSAttributedString.Key: Any]
    ) {
        if ((attributes[key] as? NSNumber)?.intValue ?? 0) != 0 {
            attributes.removeValue(forKey: key)
        } else {
            attributes[key] = NSUnderlineStyle.single.rawValue
        }
    }

    private func isInsideTable(at location: Int) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let safeLocation = min(max(location, 0), storage.length - 1)
        let paragraph = storage.attribute(.paragraphStyle, at: safeLocation, effectiveRange: nil) as? NSParagraphStyle
        return paragraph?.textBlocks.contains(where: { $0 is NSTextTableBlock }) == true
    }

    fileprivate struct ListMarker {
        enum Kind: Equatable { case bullet, dash, number, blockquote }
        let kind: Kind
        let length: Int
        let number: Int?
    }

    private struct ListContinuation {
        let paragraph: NSRange
        let marker: ListMarker
        let isEmptyItem: Bool
    }

    private func listMarker(in paragraph: NSRange) -> ListMarker? {
        guard let storage = textStorage, paragraph.length > 0 else { return nil }
        return Self.parseListMarker(storage.string as NSString, at: paragraph.location)
    }

    private func listMarker(at location: Int) -> ListMarker? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let safeLocation = min(max(location, 0), storage.length)
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: safeLocation, length: 0))
        return listMarker(in: paragraph)
    }

    private func listContinuationContext() -> ListContinuation? {
        guard selectedRange().length == 0, let storage = textStorage, storage.length > 0 else { return nil }
        let caret = min(selectedRange().location, storage.length)
        let location = min(max(caret, 0), storage.length)
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        guard let marker = listMarker(in: paragraph), caret >= paragraph.location + marker.length else { return nil }
        let contentStart = paragraph.location + marker.length
        let contentEnd = min(paragraph.location + paragraph.length, storage.length)
        let content = (storage.string as NSString).substring(
            with: NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
        )
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return ListContinuation(paragraph: paragraph, marker: marker, isEmptyItem: normalized.isEmpty)
    }

    private static func parseListMarker(_ string: NSString, at location: Int) -> ListMarker? {
        guard location < string.length else { return nil }
        let remaining = string.substring(from: location)
        if remaining.hasPrefix("• ") { return ListMarker(kind: .bullet, length: 2, number: nil) }
        if remaining.hasPrefix("– ") { return ListMarker(kind: .dash, length: 2, number: nil) }
        if remaining.hasPrefix("│ ") { return ListMarker(kind: .blockquote, length: 2, number: nil) }

        var digits = ""
        for character in remaining {
            guard character.isNumber else { break }
            digits.append(character)
        }
        guard digits.isEmpty == false,
              remaining.hasPrefix("\(digits). "),
              let number = Int(digits) else { return nil }
        return ListMarker(kind: .number, length: (digits + ". ").utf16.count, number: number)
    }

    private func richAttributedString(from pasteboard: NSPasteboard) -> NSAttributedString? {
        if let data = pasteboard.data(forType: .rtfd), let value = try? NookRichDocument.decode(data) {
            return value
        }
        if let data = pasteboard.data(forType: .rtf), let value = try? NookRichDocument.decode(data) {
            return value
        }
        return nil
    }

    private func materializeAttachments(in value: NSAttributedString) throws -> NSAttributedString {
        // The codec validates attachments and embeds image-only payloads.
        try NookRichDocument.decode(NookRichDocument.encode(value))
    }

    private func titleTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: Self.titleFont,
            .foregroundColor: defaultInk,
            .paragraphStyle: Self.titleParagraphStyle()
        ]
    }

    private func bodyTypingAttributes() -> [NSAttributedString.Key: Any] {
        Self.bodyTypingAttributes(for: defaultInk)
    }

    static func bodyTypingAttributes(for textColor: NSColor?) -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: textColor ?? NSColor.textColor,
            .paragraphStyle: bodyParagraphStyle()
        ]
    }

    static func titleParagraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = NookLayout.titleBodyGap
        return paragraph
    }

    private static func bodyParagraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 0
        return paragraph
    }
}

private extension NookTextStyle {
    var isListStyle: Bool {
        switch self {
        case .bulleted, .dashed, .numbered, .blockquote: return true
        default: return false
        }
    }

    var listKind: NookTextView.ListMarker.Kind? {
        switch self {
        case .bulleted: return .bullet
        case .dashed: return .dash
        case .numbered: return .number
        case .blockquote: return .blockquote
        default: return nil
        }
    }

    func listMarker(number: Int) -> String {
        switch self {
        case .bulleted: return "• "
        case .dashed: return "– "
        case .numbered: return "\(number). "
        case .blockquote: return "│ "
        default: return ""
        }
    }
}
