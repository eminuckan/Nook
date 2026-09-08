import AppKit
import XCTest
@testable import Nook

final class RichDocumentTests: XCTestCase {
    private func image() -> NSImage {
        NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
    }

    func testPhotosFilesAndFormattingSurviveRepeatedDiskRoundTrips() throws {
        let photo = try NookRichDocument.imageAttachment(image(), filename: "Photo.jpg")
        let payload = Data("An attached file that must remain available offline.".utf8)
        let wrapper = FileWrapper(regularFileWithContents: payload)
        wrapper.preferredFilename = "Notes.txt"
        let document = NSMutableAttributedString(string: "Heading\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 21),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        document.append(NSAttributedString(attachment: photo))
        document.append(NSAttributedString(string: "\n"))
        document.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var restored: NSAttributedString = document
        for _ in 0..<3 {
            try NookRichDocument.encode(restored).write(to: url, options: .atomic)
            restored = try NookRichDocument.decode(Data(contentsOf: url))
            XCTAssertEqual(restored.string, document.string)
            var attachments: [NSTextAttachment] = []
            restored.enumerateAttribute(.attachment, in: NSRange(location: 0, length: restored.length)) { value, _, _ in
                if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
            }
            XCTAssertEqual(attachments.count, 2)
            XCTAssertNotNil(attachments[0].fileWrapper?.regularFileContents)
            XCTAssertNotNil(NSImage(data: try XCTUnwrap(attachments[0].fileWrapper?.regularFileContents)))
            XCTAssertLessThanOrEqual(try XCTUnwrap(attachments[0].attachmentCell).cellSize().width, 321)
            XCTAssertEqual(attachments[1].fileWrapper?.regularFileContents, payload)
            let font = try XCTUnwrap(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
            XCTAssertEqual(font.pointSize, 21, accuracy: 0.1)
        }
    }

    func testLegacyRTFRemainsReadable() throws {
        let original = NSAttributedString(string: "Türkçe 👋\nOld note", attributes: [.font: NSFont.systemFont(ofSize: 17)])
        let oldData = try original.data(from: NSRange(location: 0, length: original.length), documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf
        ])
        let decoded = try NookRichDocument.decode(oldData)
        XCTAssertEqual(decoded.string, original.string)
        XCTAssertEqual((decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 17)
    }

    func testImageOnlyUntitledNoteKeepsItsBody() throws {
        let imageOnly = NSAttributedString(attachment: try NookRichDocument.imageAttachment(image()))
        var note = fixture(body: imageOnly.string)
        note.bodyRTF = try NookRichDocument.encode(imageOnly)
        let restored = try NookRichDocument.decode(XCTUnwrap(NookRichDocument.bodyData(for: note)))
        XCTAssertEqual(restored.string, imageOnly.string)
        XCTAssertNotNil(restored.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func testCompositeMigrationPreservesPhotoAndDoesNotStripMatchingBodyPrefix() throws {
        let document = NSMutableAttributedString(string: "Heading\n")
        document.append(NSAttributedString(attachment: try NookRichDocument.imageAttachment(image())))
        var composite = fixture(body: "\u{fffc}")
        composite.title = "Heading"
        composite.bodyRTF = try NookRichDocument.encode(document)
        let migrated = try NookRichDocument.decode(XCTUnwrap(NookRichDocument.bodyData(for: composite)))
        XCTAssertEqual(migrated.string, composite.body)
        XCTAssertNotNil(migrated.attribute(.attachment, at: 0, effectiveRange: nil))
        composite.body = document.string
        let untouched = try NookRichDocument.decode(XCTUnwrap(NookRichDocument.bodyData(for: composite)))
        XCTAssertEqual(untouched.string, document.string)
    }

    func testInvalidDataIsNeverSilentlyDiscardedByMetadataMigration() {
        var note = fixture(body: "Still searchable")
        note.bodyRTF = Data("invalid rich document".utf8)
        XCTAssertEqual(NookRichDocument.bodyData(for: note), note.bodyRTF)
        XCTAssertThrowsError(try NookRichDocument.decode(note.bodyRTF!))
    }

    func testEmptyDocumentRoundTrip() throws {
        let data = try NookRichDocument.encode(NSAttributedString(string: ""))
        XCTAssertEqual(try NookRichDocument.decode(data).string, "")
    }

    @MainActor
    func testPhotoSurvivesStoreRestartAndMetadataEdit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotesStore(directoryURL: directory)
        let note = store.addNote()
        let photo = try NookRichDocument.imageAttachment(image())
        let document = NSAttributedString(attachment: photo)
        let data = try NookRichDocument.encode(document)
        store.update(id: note.id, title: "Photo note", body: document.string, bodyRTF: data)
        XCTAssertNil(store.persistenceError)
        let reopenedStore = NotesStore(directoryURL: directory)
        let reopened = try XCTUnwrap(reopenedStore.note(id: note.id))
        reopenedStore.update(id: reopened.id, title: "Renamed", body: reopened.body, bodyRTF: reopened.bodyRTF, tag: "Photos")
        let restarted = try XCTUnwrap(NotesStore(directoryURL: directory).note(id: note.id))
        let restored = try NookRichDocument.decode(XCTUnwrap(restarted.bodyRTF))
        let restoredPhoto = try XCTUnwrap(restored.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(restoredPhoto.fileWrapper?.regularFileContents, photo.fileWrapper?.regularFileContents)
        XCTAssertEqual(restarted.title, "Renamed")
        XCTAssertEqual(restarted.tag, "Photos")
    }

    private func fixture(body: String) -> NookNote {
        NookNote(id: UUID(), title: "Yeni not", body: body, tag: "Inbox", tint: .amber, isPinned: false, updatedAt: .now)
    }
}
