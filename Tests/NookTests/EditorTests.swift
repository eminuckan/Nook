import AppKit
import SwiftUI
import XCTest
@testable import Nook

final class EditorTests: XCTestCase {
    @MainActor
    private final class Harness {
        var text: String
        var richData: Data?
        var selection = NSRange(location: 0, length: 0)
        var saves: [(String, Data)] = []
        let bridge = NookEditorBridge()
        let view = NookTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let window: NSWindow
        var coordinator: NookRichTextEditor.Coordinator!
        var editor: NookRichTextEditor {
            NookRichTextEditor(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                richData: Binding(get: { self.richData }, set: { self.richData = $0 }),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 }),
                isDark: false, placeholder: "", startsWithTitle: false, bridge: bridge,
                onDocumentChange: { self.saves.append(($0, $1)) }
            )
        }

        init(_ text: String = "", richData: Data? = nil, isDark: Bool = false) {
            _ = NSApplication.shared
            self.text = text
            self.richData = richData
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.isRichText = true
            view.allowsUndo = true
            view.startsWithTitle = false
            view.configureAppearance(isDark: isDark)
            bridge.attach(view)
            coordinator = NookRichTextEditor.Coordinator(editor)
            coordinator.textView = view
            _ = coordinator.installDocument(in: view, text: text, richData: richData, startsWithTitle: false)
            view.delegate = coordinator
            window.makeFirstResponder(view)
            view.undoManager?.removeAllActions()
        }

        func close() {
            view.delegate = nil
            coordinator = nil
            window.close()
        }
    }

    @MainActor
    func testImageInsertUndoRedoSynchronouslySavesRecoverableDocument() async throws {
        let h = Harness("before")
        defer { h.close() }
        let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
            NSColor.systemOrange.setFill(); rect.fill(); return true
        }
        let attachment = try NookRichDocument.imageAttachment(image)
        h.view.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(h.view.performDocumentReplacement(in: h.view.selectedRange(), with: NSAttributedString(attachment: attachment), actionName: "Insert Image"))
        XCTAssertEqual(h.saves.count, 1)
        XCTAssertEqual(h.text, "before\u{fffc}")
        XCTAssertTrue(h.bridge.canUndo)
        let saved = try NookRichDocument.decode(XCTUnwrap(h.richData))
        XCTAssertNotNil((saved.attribute(.attachment, at: 6, effectiveRange: nil) as? NSTextAttachment)?.fileWrapper?.regularFileContents)
        h.bridge.undo()
        XCTAssertEqual(h.view.string, "before")
        XCTAssertEqual(h.text, "before")
        XCTAssertFalse(h.bridge.canUndo, "One insertion must produce one undo step")
        XCTAssertTrue(h.bridge.canRedo)
        h.bridge.redo()
        XCTAssertEqual(h.text, "before\u{fffc}")
        XCTAssertEqual(h.saves.count, 3)
        let redone = try NookRichDocument.decode(XCTUnwrap(h.richData))
        if redone.length > 6 { XCTAssertNotNil(redone.attribute(.attachment, at: 6, effectiveRange: nil)) }
    }

    @MainActor
    func testListConversionAtNonzeroSelectionAndUndo() async throws {
        let h = Harness("intro\n• first\n• second\ntail")
        defer { h.close() }
        h.view.setSelectedRange(NSRange(location: 6, length: 17))
        h.bridge.apply(.numbered)
        XCTAssertEqual(h.view.string, "intro\n1. first\n2. second\ntail")
        XCTAssertEqual(h.view.selectedRange(), NSRange(location: 6, length: 19))
        h.bridge.undo()
        XCTAssertEqual(h.view.string, "intro\n• first\n• second\ntail")
        h.bridge.redo()
        XCTAssertEqual(h.view.string, "intro\n1. first\n2. second\ntail")
        h.bridge.apply(.body)
        XCTAssertEqual(h.view.string, "intro\nfirst\nsecond\ntail")
        XCTAssertEqual(h.view.selectedRange(), NSRange(location: 6, length: 13))
        XCTAssertNoThrow(try NookRichDocument.decode(XCTUnwrap(h.richData)))
    }

    @MainActor
    func testEmptyListContinuationExitAndTrailingParagraph() async throws {
        let h = Harness()
        defer { h.close() }
        h.bridge.apply(.numbered)
        XCTAssertEqual(h.text, "1. ")
        XCTAssertEqual(h.view.selectedRange(), NSRange(location: 3, length: 0))
        h.view.insertText("one", replacementRange: h.view.selectedRange())
        h.view.insertNewline(nil)
        XCTAssertEqual(h.text, "1. one\n2. ")
        h.view.insertNewline(nil)
        XCTAssertEqual(h.text, "1. one\n")
        XCTAssertFalse(h.view.formattingStyles.contains(.numbered))
        XCTAssertEqual((h.view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent, 0)
        h.bridge.apply(.bulleted)
        XCTAssertEqual(h.text, "1. one\n• ")
        h.view.insertNewline(nil)
        XCTAssertEqual(h.text, "1. one\n")
    }

    @MainActor
    func testCaretFormattingAndHeadingReturnUseTypingAttributes() async throws {
        let h = Harness("word")
        defer { h.close() }
        h.view.setSelectedRange(NSRange(location: 4, length: 0))
        XCTAssertFalse(h.view.formattingStyles.contains(.underline))
        XCTAssertFalse(h.view.formattingStyles.contains(.strikethrough))
        h.bridge.apply(.underline)
        XCTAssertTrue(h.bridge.activeStyles.contains(.underline))
        XCTAssertEqual(h.saves.count, 0, "Caret style changes must not rewrite the document")
        h.view.insertText("!", replacementRange: h.view.selectedRange())
        XCTAssertEqual((h.view.textStorage?.attribute(.underlineStyle, at: 4, effectiveRange: nil) as? NSNumber)?.intValue, 1)
        h.view.setSelectedRange(NSRange(location: 0, length: 5))
        h.bridge.apply(.heading)
        h.view.setSelectedRange(NSRange(location: 5, length: 0))
        h.view.insertNewline(nil)
        h.view.insertText("body", replacementRange: h.view.selectedRange())
        XCTAssertEqual((h.view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)?.pointSize, 14)
    }

    @MainActor
    func testFormattingKeepsPerRunSizesTableBlocksAndAttachmentBytes() async throws {
        let h = Harness()
        defer { h.close() }
        h.bridge.insertTable(rows: 1, columns: 2)
        let wrapper = FileWrapper(regularFileWithContents: Data("offline".utf8))
        wrapper.preferredFilename = "proof.txt"
        h.view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(h.view.performDocumentReplacement(in: h.view.selectedRange(), with: NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)), actionName: "Insert File"))
        h.view.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 22), range: NSRange(location: 1, length: 1))
        h.view.setSelectedRange(NSRange(location: 0, length: 5))
        h.bridge.apply(.bold)
        XCTAssertEqual((h.view.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.pointSize, 22)
        h.bridge.apply(.bulleted)
        h.bridge.apply(.body)
        let saved = try NookRichDocument.decode(XCTUnwrap(h.richData))
        var attachmentCount = 0
        var blockCount = 0
        saved.enumerateAttributes(in: NSRange(location: 0, length: saved.length)) { attrs, _, _ in
            if let attachment = attrs[.attachment] as? NSTextAttachment {
                attachmentCount += 1
                XCTAssertEqual(attachment.fileWrapper?.regularFileContents, Data("offline".utf8))
            }
            if (attrs[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.contains(where: { $0 is NSTextTableBlock }) == true { blockCount += 1 }
        }
        XCTAssertEqual(attachmentCount, 1)
        XCTAssertGreaterThanOrEqual(blockCount, 2)
    }

    @MainActor
    func testInvalidSerializedDataIsReadOnlyAndPreserved() async throws {
        let corrupt = Data("broken document".utf8)
        let h = Harness("searchable text", richData: corrupt)
        defer { h.close() }
        XCTAssertTrue(h.view.documentReadOnlyDueToError)
        XCTAssertFalse(h.bridge.hasUnsavedDraft)
        XCTAssertFalse(h.view.isEditable)
        h.bridge.apply(.bold)
        h.view.insertNewline(nil)
        XCTAssertFalse(h.view.performDocumentReplacement(in: NSRange(location: 0, length: 0), with: NSAttributedString(string: "bad"), actionName: "Bad"))
        h.coordinator.syncFromTextView()
        XCTAssertEqual(h.richData, corrupt)
        XCTAssertEqual(h.text, "searchable text")
        XCTAssertTrue(h.saves.isEmpty)
    }

    @MainActor
    func testSerializationFailureKeepsLastSavedPairAndNativeDraft() async throws {
        let h = Harness("saved")
        defer { h.close() }
        h.coordinator.syncFromTextView()
        let previous = h.richData
        let invalid = NSAttributedString(attachment: NSTextAttachment())
        XCTAssertTrue(h.view.performDocumentReplacement(in: NSRange(location: 5, length: 0), with: invalid, actionName: "Unsavable"))
        XCTAssertEqual(h.view.string, "saved\u{fffc}")
        XCTAssertEqual(h.text, "saved")
        XCTAssertEqual(h.richData, previous)
        XCTAssertNotNil(h.bridge.errorMessage)
        XCTAssertEqual(h.saves.count, 1)
        h.bridge.undo()
        XCTAssertEqual(h.view.string, "saved")
        XCTAssertNil(h.bridge.errorMessage)
    }
    @MainActor
    func testSwiftUIRefreshDoesNotReplaceUnsavedNativeDraft() async throws {
        _ = NSApplication.shared
        let bridge = NookEditorBridge()
        func editor(isDark: Bool) -> NookRichTextEditor {
            NookRichTextEditor(text: .constant("saved"), richData: .constant(nil),
                               selection: .constant(NSRange(location: 0, length: 0)),
                               isDark: isDark, placeholder: "", startsWithTitle: false, bridge: bridge)
        }
        let hosting = NSHostingView(rootView: editor(isDark: false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        await Task.yield()
        let native = try XCTUnwrap(bridge.textView)
        XCTAssertTrue(native.performDocumentReplacement(in: NSRange(location: 5, length: 0),
                                                       with: NSAttributedString(attachment: NSTextAttachment()),
                                                       actionName: "Unsavable"))
        XCTAssertNotNil(bridge.errorMessage)
        hosting.rootView = editor(isDark: true)
        hosting.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertTrue(bridge.textView === native)
        XCTAssertEqual(native.string, "saved\u{fffc}")
        XCTAssertNotNil(bridge.errorMessage)
    }

    @MainActor
    func testRichClipboardWinsOverImageAndPreservesFormatting() async throws {
        let h = Harness()
        defer { h.close() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let rich = NSAttributedString(string: "Rich text", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.systemPurple
        ])
        pasteboard.setData(try NookRichDocument.encode(rich), forType: .rtfd)
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        pasteboard.setData(try XCTUnwrap(image.tiffRepresentation), forType: .tiff)
        h.view.paste(from: pasteboard)
        XCTAssertEqual(h.text, "Rich text")
        let saved = try NookRichDocument.decode(XCTUnwrap(h.richData))
        XCTAssertTrue(try XCTUnwrap(saved.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual((saved.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 22)
        XCTAssertEqual(h.saves.count, 1)
    }

    @MainActor
    func testCodeTogglePreservesSizesAndExistingBoldTrait() async throws {
        let h = Harness("large small")
        defer { h.close() }
        h.view.textStorage?.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 22), range: NSRange(location: 0, length: 5))
        h.view.setSelectedRange(NSRange(location: 0, length: 11))
        h.bridge.apply(.code)
        let codeFont = try XCTUnwrap(h.view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(codeFont.pointSize, 22)
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.bold))
        h.bridge.apply(.code)
        let restored = try XCTUnwrap(h.view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(restored.pointSize, 22)
        XCTAssertFalse(restored.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertTrue(restored.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @MainActor
    func testKeyboardUndoRedoSupportsMacAndControlShortcuts() async throws {
        let h = Harness("word")
        defer { h.close() }
        func event(_ key: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                          timestamp: 0, windowNumber: h.window.windowNumber, context: nil,
                                          characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 6))
        }
        h.view.setSelectedRange(NSRange(location: 0, length: 4))
        h.bridge.apply(.bold)
        XCTAssertTrue(h.view.performKeyEquivalent(with: try event("z", [.command])))
        XCTAssertFalse(h.view.formattingStyles.contains(.bold))
        XCTAssertTrue(h.bridge.canRedo)
        XCTAssertTrue(h.view.performKeyEquivalent(with: try event("z", [.command, .shift])))
        XCTAssertTrue(h.view.formattingStyles.contains(.bold))
        h.view.keyDown(with: try event("z", [.control]))
        XCTAssertFalse(h.view.formattingStyles.contains(.bold))
        h.view.keyDown(with: try event("y", [.control]))
        XCTAssertTrue(h.view.formattingStyles.contains(.bold))
        h.view.keyDown(with: try event("z", [.control]))
        h.view.keyDown(with: try event("z", [.control, .shift]))
        XCTAssertTrue(h.view.formattingStyles.contains(.bold))

        let payload = Data("attachment".utf8)
        let wrapper = FileWrapper(regularFileWithContents: payload)
        wrapper.preferredFilename = "file.txt"
        XCTAssertTrue(h.view.performDocumentReplacement(in: NSRange(location: 4, length: 0),
                                                       with: NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)),
                                                       actionName: "Insert Attachment"))
        h.view.keyDown(with: try event("z", [.control]))
        XCTAssertEqual(h.view.string, "word")
        h.view.keyDown(with: try event("y", [.control]))
        XCTAssertEqual(h.view.string, "word\u{fffc}")
        let decoded = try NookRichDocument.decode(XCTUnwrap(h.richData))
        XCTAssertEqual((decoded.attribute(.attachment, at: 4, effectiveRange: nil) as? NSTextAttachment)?.fileWrapper?.regularFileContents, payload)

        h.window.makeFirstResponder(nil)
        XCTAssertFalse(h.view.performKeyEquivalent(with: try event("z", [.control])))
        XCTAssertEqual(h.view.string, "word\u{fffc}", "Unfocused editor must not consume title-field undo")
    }

    @MainActor
    func testTypingAfterPhotoUsesReadableInkAndBodyAttributesInBothThemes() async throws {
        for isDark in [false, true] {
            let h = Harness("before\n", isDark: isDark)
            defer { h.close() }
            let image = NSImage(size: NSSize(width: 80, height: 60), flipped: false) { rect in
                NSColor.orange.setFill(); rect.fill(); return true
            }
            let photo = try NookRichDocument.imageAttachment(image)
            h.view.setSelectedRange(NSRange(location: h.view.string.utf16.count, length: 0))
            XCTAssertTrue(h.view.performDocumentReplacement(in: h.view.selectedRange(),
                                                           with: NSAttributedString(attachment: photo), actionName: "Photo"))
            h.view.setSelectedRange(NSRange(location: h.view.string.utf16.count, length: 0))
            h.view.insertNewline(nil)
            h.bridge.apply(.bold)
            h.view.insertText("after", replacementRange: h.view.selectedRange())
            let saved = try NookRichDocument.decode(XCTUnwrap(h.richData))
            XCTAssertEqual(saved.string, "before\n\u{fffc}\nafter")
            let ordinary = NSRange(location: 8, length: 6)
            saved.enumerateAttributes(in: ordinary) { attributes, _, _ in
                XCTAssertNil(attributes[.attachment])
                XCTAssertEqual((attributes[.font] as? NSFont)?.pointSize, 14)
                let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)
                let expected = h.view.defaultInk.usingColorSpace(.sRGB)!
                XCTAssertEqual(color?.redComponent ?? -1, expected.redComponent, accuracy: 0.005)
                XCTAssertEqual(color?.greenComponent ?? -1, expected.greenComponent, accuracy: 0.005)
                XCTAssertEqual(color?.blueComponent ?? -1, expected.blueComponent, accuracy: 0.005)
            }
            XCTAssertTrue((saved.attribute(.font, at: 9, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
            XCTAssertNil(h.view.typingAttributes[.attachment])
            XCTAssertEqual(h.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), isDark ? .darkAqua : .aqua)
            XCTAssertEqual((saved.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)?.fileWrapper?.regularFileContents,
                           photo.fileWrapper?.regularFileContents)
            h.view.needsDisplay = false
            h.view.drawInsertionPoint(in: NSRect(x: 5, y: 5, width: 1, height: 60), color: .white, turnedOn: false)
            XCTAssertTrue(h.view.needsDisplay, "Caret erasure must repaint attachment glyphs instead of drawing a flat stripe")
        }
    }

    @MainActor
    func testThemeReloadMapsDefaultInksAndPreservesCustomColors() async throws {
        let custom = NSColor(srgbRed: 0.75, green: 0.2, blue: 0.4, alpha: 1)
        for isDark in [false, true] {
            let document = NSMutableAttributedString(string: "default custom", attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: isDark ? NookPalette.cardInkNS : NSColor.white
            ])
            document.addAttribute(.foregroundColor, value: custom, range: NSRange(location: 8, length: 6))
            let h = Harness(document.string, richData: try NookRichDocument.encode(document), isDark: isDark)
            defer { h.close() }
            let defaultColor = try XCTUnwrap(h.view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(defaultColor, h.view.defaultInk)
            let restoredCustom = try XCTUnwrap((h.view.textStorage?.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB))
            XCTAssertEqual(restoredCustom.redComponent, 0.75, accuracy: 0.005)
            XCTAssertEqual(restoredCustom.greenComponent, 0.2, accuracy: 0.005)
            XCTAssertEqual(restoredCustom.blueComponent, 0.4, accuracy: 0.005)
            h.view.configureAppearance(isDark: !isDark)
            XCTAssertEqual(h.view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, h.view.defaultInk)
            XCTAssertEqual((h.view.textStorage?.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB), restoredCustom)
            XCTAssertTrue(h.saves.isEmpty, "Appearance refresh must not create a content edit")
        }
    }

    @MainActor
    func testBlockPhotoHasBreathingRoomAndMatchingBodyFontWithOneUndo() async throws {
        let h = Harness("before", isDark: true)
        defer { h.close() }
        let image = NSImage(size: NSSize(width: 80, height: 60), flipped: false) { rect in
            NSColor.orange.setFill(); rect.fill(); return true
        }
        let photo = try NookRichDocument.imageAttachment(image)
        h.view.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(h.view.insertBlockImage(photo, actionName: "Insert Photo"))
        XCTAssertEqual(h.text, "before\n\u{fffc}\n")
        XCTAssertEqual(h.view.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertEqual(h.saves.count, 1)
        let paragraph = try XCTUnwrap(h.view.textStorage?.attribute(.paragraphStyle, at: 7, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertGreaterThanOrEqual(paragraph.paragraphSpacingBefore, 10)
        XCTAssertGreaterThanOrEqual(paragraph.paragraphSpacing, 10)
        XCTAssertEqual((h.view.typingAttributes[.font] as? NSFont)?.pointSize, 14)
        XCTAssertEqual((h.view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacingBefore, 0)
        h.bridge.undo()
        XCTAssertEqual(h.text, "before")
        XCTAssertFalse(h.bridge.canUndo)
        h.bridge.redo()
        XCTAssertEqual(h.text, "before\n\u{fffc}\n")
        h.view.insertText("after", replacementRange: h.view.selectedRange())
        let saved = try NookRichDocument.decode(XCTUnwrap(h.richData))
        XCTAssertEqual(saved.string, "before\n\u{fffc}\nafter")
        XCTAssertEqual((saved.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 14)
        XCTAssertEqual((saved.attribute(.font, at: 9, effectiveRange: nil) as? NSFont)?.pointSize, 14)
        XCTAssertEqual((saved.attribute(.paragraphStyle, at: 9, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacingBefore, 0)
        XCTAssertNotNil(saved.attribute(.attachment, at: 7, effectiveRange: nil))
    }

    @MainActor
    func testImageClipboardReusesBoundariesAndRepeatedPhotoDoesNotAddBlankLines() async throws {
        let h = Harness("above\nbelow")
        defer { h.close() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            NSColor.orange.setFill(); rect.fill(); return true
        }
        pasteboard.setData(try XCTUnwrap(image.tiffRepresentation), forType: .tiff)
        h.view.setSelectedRange(NSRange(location: 5, length: 0))
        h.view.paste(from: pasteboard)
        XCTAssertEqual(h.text, "above\n\u{fffc}\nbelow")
        h.view.paste(from: pasteboard)
        XCTAssertEqual(h.text, "above\n\u{fffc}\n\u{fffc}\nbelow")
        XCTAssertFalse(h.text.contains("\n\n"))
        XCTAssertEqual(h.saves.count, 2)
    }

    @MainActor
    func testPhotoSpacingReloadPreservesTextFontsCustomSpacingAndTableBlocks() async throws {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            NSColor.orange.setFill(); rect.fill(); return true
        }
        let photo = try NookRichDocument.imageAttachment(image)
        let old = NSMutableAttributedString(string: "small\n", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        old.append(NSAttributedString(attachment: photo))
        old.append(NSAttributedString(string: "\nsmall", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        let custom = NSMutableParagraphStyle()
        custom.paragraphSpacingBefore = 5
        custom.paragraphSpacing = 22
        old.addAttribute(.paragraphStyle, value: custom, range: NSRange(location: 6, length: 2))
        let h = Harness(old.string, richData: try NookRichDocument.encode(old))
        defer { h.close() }
        let photoStyle = try XCTUnwrap(h.view.textStorage?.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(photoStyle.paragraphSpacingBefore, 5)
        XCTAssertEqual(photoStyle.paragraphSpacing, 22)
        XCTAssertEqual((h.view.textStorage?.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.pointSize, 12)
        XCTAssertTrue(h.saves.isEmpty)

        let table = Harness()
        defer { table.close() }
        table.bridge.insertTable(rows: 1, columns: 2)
        table.view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(table.view.insertBlockImage(photo, actionName: "Photo in Table"))
        let block = try XCTUnwrap(table.view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertTrue(block.textBlocks.contains(where: { $0 is NSTextTableBlock }))
        XCTAssertEqual((table.view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.count, block.textBlocks.count)
    }

    @MainActor
    func testUnsavedNativeDraftSurvivesErrorsAndOnlySuccessfulRetryClearsIt() async throws {
        let h = Harness("saved")
        defer { h.close() }
        h.coordinator.syncFromTextView()
        XCTAssertFalse(h.bridge.hasUnsavedDraft)
        h.bridge.report(error: NookRichDocument.DocumentError.unreadableImage)
        XCTAssertFalse(h.bridge.hasUnsavedDraft, "Picker or generic errors must not mark the native document dirty")
        XCTAssertTrue(h.view.performDocumentReplacement(in: NSRange(location: 5, length: 0),
                                                       with: NSAttributedString(attachment: NSTextAttachment()),
                                                       actionName: "Unsavable"))
        XCTAssertTrue(h.bridge.hasUnsavedDraft)
        XCTAssertEqual(h.saves.count, 1)
        h.bridge.clearError()
        XCTAssertTrue(h.bridge.hasUnsavedDraft, "Dismissing an error cannot discard an unsaved native draft")
        XCTAssertFalse(h.bridge.retrySave())
        XCTAssertTrue(h.bridge.hasUnsavedDraft)
        XCTAssertNotNil(h.bridge.errorMessage)
        XCTAssertEqual(h.saves.count, 1)
        h.bridge.textView = nil
        XCTAssertFalse(h.bridge.retrySave(), "A missing native editor cannot report that its draft was saved")
        h.bridge.attach(h.view)
        let wrapper = FileWrapper(regularFileWithContents: Data("repaired attachment".utf8))
        wrapper.preferredFilename = "repaired.txt"
        h.view.textStorage?.addAttribute(.attachment, value: NSTextAttachment(fileWrapper: wrapper),
                                        range: NSRange(location: 5, length: 1))
        XCTAssertTrue(h.bridge.retrySave())
        XCTAssertFalse(h.bridge.hasUnsavedDraft)
        XCTAssertNil(h.bridge.errorMessage)
        XCTAssertEqual(h.saves.count, 2)
        XCTAssertEqual(h.text, "saved\u{fffc}")
        let saved = try NookRichDocument.decode(XCTUnwrap(h.richData))
        XCTAssertEqual((saved.attribute(.attachment, at: 5, effectiveRange: nil) as? NSTextAttachment)?.fileWrapper?.regularFileContents,
                       Data("repaired attachment".utf8))
    }

}
