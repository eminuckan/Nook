import Foundation
import XCTest
@testable import Nook

@MainActor
final class NotesStoreTests: XCTestCase {
    func testMissingFileSeedsNotesWithoutAnError() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let store = NotesStore(directoryURL: directory)

        XCTAssertFalse(store.notes.isEmpty)
        XCTAssertNil(store.persistenceError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: notesURL(in: directory).path))
    }

    func testUnreadableExistingFileIsPreservedAndBlocksWrites() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = notesURL(in: directory)
        let originalData = Data("not-json".utf8)
        try originalData.write(to: fileURL)

        let store = NotesStore(directoryURL: directory)

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(store.isPersistenceBlocked)
        XCTAssertEqual(store.persistenceError?.operation, .load)
        XCTAssertEqual(store.persistenceError?.url, fileURL)
        XCTAssertTrue(store.persistenceError?.recoverySuggestion?.contains("Retry") == true)
        XCTAssertTrue(store.persistenceError?.recoverySuggestion?.contains("safe backup") == true)

        _ = store.addNote()

        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertEqual(store.persistenceError?.operation, .load)
        XCTAssertTrue(store.isPersistenceBlocked)
        XCTAssertFalse(store.retryPersistence())
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    func testRetryPersistenceReloadsARepairedFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = notesURL(in: directory)
        try Data("not-json".utf8).write(to: fileURL)

        let store = NotesStore(directoryURL: directory)
        XCTAssertTrue(store.isPersistenceBlocked)

        let repairedNote = makeNote(title: "Recovered")
        try encode([repairedNote], to: fileURL)

        XCTAssertTrue(store.retryPersistence())
        XCTAssertEqual(store.notes, [repairedNote])
        XCTAssertNil(store.persistenceError)
        XCTAssertFalse(store.isPersistenceBlocked)
    }

    func testSaveFailureIsPublishedAndRetryPersistsPendingNotes() throws {
        let parent = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(parent) }
        let directory = parent.appendingPathComponent("storage", isDirectory: true)
        try Data("directory placeholder".utf8).write(to: directory)

        let store = NotesStore(directoryURL: directory)
        _ = store.addNote()

        XCTAssertEqual(store.persistenceError?.operation, .save)
        XCTAssertFalse(store.persistenceError?.isBlocking ?? true)

        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertTrue(store.retryPersistence())
        XCTAssertNil(store.persistenceError)

        let savedData = try Data(contentsOf: notesURL(in: directory))
        let savedNotes = try decode([NookNote].self, from: savedData)
        XCTAssertEqual(savedNotes.map(\.id), store.notes.map(\.id))
        for (saved, current) in zip(savedNotes, store.notes) {
            XCTAssertEqual(saved.title, current.title)
            XCTAssertEqual(saved.body, current.body)
            XCTAssertEqual(saved.bodyRTF, current.bodyRTF)
            XCTAssertEqual(saved.updatedAt.timeIntervalSince1970, current.updatedAt.timeIntervalSince1970, accuracy: 1)
        }
    }

    func testUpdateWithUnchangedValuesDoesNotRewriteTheNote() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let note = makeNote(title: "Stable")
        try encode([note], to: notesURL(in: directory))

        let store = NotesStore(directoryURL: directory)
        let originalData = try Data(contentsOf: notesURL(in: directory))

        store.update(
            id: note.id,
            title: note.title,
            body: note.body,
            bodyRTF: note.bodyRTF,
            tag: note.tag,
            tint: note.tint
        )

        XCTAssertEqual(store.note(id: note.id), note)
        XCTAssertEqual(try Data(contentsOf: notesURL(in: directory)), originalData)
        XCTAssertNil(store.persistenceError)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookNotesStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func notesURL(in directory: URL) -> URL {
        directory.appendingPathComponent("notes.json")
    }

    private func makeNote(title: String) -> NookNote {
        NookNote(
            id: UUID(),
            title: title,
            body: "Body",
            tag: "Inbox",
            tint: .amber,
            isPinned: false,
            sortOrder: 0,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
