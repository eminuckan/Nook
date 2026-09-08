import XCTest
@testable import Nook

final class TagStoreTests: XCTestCase {
    @MainActor
    func testFreshDefaultsAreEnglish() async throws {
        let name = "NookTagsTest.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TagStore(defaults: defaults)
        XCTAssertEqual(store.tags.map(\.name), ["Inbox", "Ideas", "Design", "Tasks", "Personal"])
    }

    @MainActor
    func testOnlyProvenBuiltInsMigrateAndNotesKeepContentAndDates() async throws {
        let name = "NookTagsTest.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let saved = [NookTag(name: "Fikir", tint: .amber, isBuiltIn: true), NookTag(name: "Tasarım", tint: .blue, isBuiltIn: false)]
        try defaults.set(JSONEncoder().encode(saved), forKey: "nook.tags")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = NotesStore(directoryURL: directory)
        let note = notes.addNote()
        notes.update(id: note.id, title: "Custom title", body: "Personal content", bodyRTF: nil, tag: "Fikir")
        let before = try XCTUnwrap(notes.note(id: note.id))
        let tags = TagStore(notes: notes.notes, defaults: defaults)
        XCTAssertEqual(tags.legacyBuiltInRenames, ["Fikir": "Ideas"])
        XCTAssertTrue(tags.tags.contains { $0.name == "Tasarım" && !$0.isBuiltIn })
        XCTAssertFalse(tags.tags.contains { $0.name == "Fikir" })
        XCTAssertNotNil(tags.create(name: "Work", tint: .blue))
        XCTAssertNil(tags.create(name: "Fikir", tint: .blue))
        let stillPending = try JSONDecoder().decode([NookTag].self, from: XCTUnwrap(defaults.data(forKey: "nook.tags")))
        XCTAssertTrue(stillPending.contains { $0.name == "Fikir" && $0.isBuiltIn })
        XCTAssertTrue(notes.migrateBuiltInTags(tags.legacyBuiltInRenames))
        tags.finishBuiltInMigration()
        var expected = before; expected.tag = "Ideas"
        XCTAssertEqual(notes.note(id: note.id), expected)
        XCTAssertEqual(NotesStore(directoryURL: directory).note(id: note.id)?.tag, "Ideas")
        XCTAssertTrue(TagStore(defaults: defaults).legacyBuiltInRenames.isEmpty)
    }
}
