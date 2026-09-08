import Foundation
import Combine

@MainActor
final class NotesStore: ObservableObject {
    struct PersistenceError: Error, Equatable, Identifiable, LocalizedError {
        enum Operation: String, Equatable {
            case load
            case save
        }

        let operation: Operation
        let url: URL
        let reason: String

        var id: String {
            "\(operation.rawValue):\(url.path):\(reason)"
        }

        var isBlocking: Bool {
            operation == .load
        }

        var errorDescription: String? {
            switch operation {
            case .load:
                return "Nook could not read its saved notes at \(url.path)."
            case .save:
                return "Nook could not save its notes at \(url.path)."
            }
        }

        var failureReason: String? {
            reason
        }

        var recoverySuggestion: String? {
            switch operation {
            case .load:
                return "No changes were written. Make a safe backup of \(url.path), repair or remove it, then choose Retry."
            case .save:
                return "Check that \(url.path) is writable, then choose Retry."
            }
        }
    }

    @Published private(set) var notes: [NookNote]
    @Published private(set) var persistenceError: PersistenceError?

    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pendingPersistTask: Task<Void, Never>?
    private var hasPendingPersistence = false
    private var isLoadBlocked = false

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let resolvedDirectoryURL: URL
        if let directoryURL {
            resolvedDirectoryURL = directoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            resolvedDirectoryURL = appSupport.appendingPathComponent("Nook", isDirectory: true)
        }
        self.directoryURL = resolvedDirectoryURL
        fileURL = resolvedDirectoryURL.appendingPathComponent("notes.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        notes = []
        persistenceError = nil
        loadNotes()
    }

    var isPersistenceBlocked: Bool {
        isLoadBlocked
    }

    /// Retries the last failed persistence operation. A load failure is retried
    /// by reading the existing file again; it is never replaced implicitly.
    /// A save failure retries the pending in-memory snapshot.
    @discardableResult
    func retryPersistence() -> Bool {
        if isLoadBlocked {
            loadNotes()
            return persistenceError == nil
        }

        guard hasPendingPersistence else {
            persistenceError = nil
            return true
        }
        persist()
        return persistenceError == nil
    }

    var pinnedCount: Int { notes.filter(\.isPinned).count }

    @discardableResult
    func migrateBuiltInTags(_ renames: [String: String]) -> Bool {
        guard !isLoadBlocked else { return false }
        var changed = false
        for index in notes.indices {
            if let name = renames[notes[index].tag] {
                notes[index].tag = name
                changed = true
            }
        }
        if changed { persist() }
        return persistenceError == nil
    }

    func visibleNotes(query: String, filter: NoteFilter) -> [NookNote] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.ordered(notes.filter { note in
            let matchesQuery = normalizedQuery.isEmpty
                || note.title.localizedCaseInsensitiveContains(normalizedQuery)
                || note.body.localizedCaseInsensitiveContains(normalizedQuery)
                || note.tag.localizedCaseInsensitiveContains(normalizedQuery)

            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .pinned:
                matchesFilter = note.isPinned
            case .today:
                matchesFilter = Calendar.current.isDateInToday(note.updatedAt)
            }
            return matchesQuery && matchesFilter
        })
    }

    @discardableResult
    func addNote() -> NookNote {
        let nextOrder = (notes.compactMap(\.sortOrder).min() ?? 0) - 1
        let note = NookNote(
            id: UUID(),
            title: "Yeni not",
            body: "",
            tag: "Inbox",
            tint: .amber,
            isPinned: false,
            sortOrder: nextOrder,
            updatedAt: .now
        )
        notes.insert(note, at: 0)
        persist()
        return note
    }

    func update(
        id: UUID,
        title: String,
        body: String,
        bodyRTF: Data? = nil,
        tag: String? = nil,
        tint: NookNote.Tint? = nil
    ) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let current = notes[index]
        let nextTag = if let tag, tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            tag
        } else {
            current.tag
        }
        let nextTint = tint ?? current.tint
        guard current.title != title
            || current.body != body
            || current.bodyRTF != bodyRTF
            || current.tag != nextTag
            || current.tint != nextTint else { return }

        notes[index].title = title
        notes[index].body = body
        notes[index].bodyRTF = bodyRTF
        notes[index].tag = nextTag
        notes[index].tint = nextTint
        notes[index].updatedAt = .now
        persist()
    }

    func togglePinned(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        // Pinning changes grouping, not note recency. Keeping the original
        // timestamp lets an unpinned note animate back to its prior position.
        persist()
    }

    /// Flushes a deferred reorder write before the panel is dismissed or the
    /// app is otherwise asked to leave the current editing surface.
    func flushPendingPersistence() {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil
        guard hasPendingPersistence else { return }
        persist()
    }

    /// Moves one note before another in the stable manual order. The pinned
    /// grouping remains a stronger invariant, so a drag cannot silently move
    /// an unpinned note into the pinned group (or vice versa).
    func reorder(id: UUID, before targetID: UUID) {
        reorder(id: id, relativeTo: targetID, placement: .before)
    }

    func reorder(id: UUID, after targetID: UUID) {
        reorder(id: id, relativeTo: targetID, placement: .after)
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        persist()
    }

    func note(id: UUID) -> NookNote? {
        notes.first(where: { $0.id == id })
    }

    private func persist() {
        hasPendingPersistence = true
        guard isLoadBlocked == false else { return }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(notes)
            try data.write(to: fileURL, options: [.atomic])
            hasPendingPersistence = false
            persistenceError = nil
        } catch {
            persistenceError = PersistenceError(operation: .save, url: fileURL, reason: error.localizedDescription)
        }
    }

    private func loadNotes() {
        do {
            let data = try Data(contentsOf: fileURL)
            let saved = try decoder.decode([NookNote].self, from: data)
            notes = Self.normalized(saved)
            isLoadBlocked = false
            hasPendingPersistence = false
            persistenceError = nil
        } catch {
            // Only a definite missing-file result means there is no existing
            // data to protect. Permission failures, decode failures, and other
            // read errors must remain blocked even if fileExists is ambiguous.
            if isMissingFileError(error) {
                let shouldPersistCurrentNotes = isLoadBlocked && hasPendingPersistence
                isLoadBlocked = false
                persistenceError = nil
                if shouldPersistCurrentNotes {
                    persist()
                } else {
                    seedNotes()
                    hasPendingPersistence = false
                }
                return
            }

            notes = []
            isLoadBlocked = true
            persistenceError = PersistenceError(operation: .load, url: fileURL, reason: error.localizedDescription)
        }
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == CocoaError.Code.fileNoSuchFile.rawValue
                || nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
                return true
            }
            // Data(contentsOf:) reports a regular-file parent as
            // fileReadCorruptFile on some macOS versions. The child path is
            // definitely absent in that case, while the same code for an
            // existing directory must remain a blocking read failure.
            if nsError.code == CocoaError.Code.fileReadUnknown.rawValue
                || nsError.code == CocoaError.Code.fileReadCorruptFile.rawValue {
                return parentIsRegularFile
            }
            return false
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == ENOENT || (nsError.code == ENOTDIR && parentIsRegularFile)
        }
        return false
    }

    private var parentIsRegularFile: Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue == false
    }

    private func seedNotes() {
        var seeded = Self.sampleNotes
        for index in seeded.indices { seeded[index].sortOrder = index }
        notes = Self.ordered(seeded)
    }

    private static func normalized(_ saved: [NookNote]) -> [NookNote] {
        var loaded = saved.sorted { $0.updatedAt > $1.updatedAt }
        for index in loaded.indices where loaded[index].sortOrder == nil {
            loaded[index].sortOrder = index
        }
        return Self.ordered(loaded)
    }

    private enum ReorderPlacement {
        case before
        case after
    }

    private func reorder(id: UUID, relativeTo targetID: UUID, placement: ReorderPlacement) {
        guard id != targetID,
              let moving = notes.first(where: { $0.id == id }),
              let target = notes.first(where: { $0.id == targetID }),
              moving.isPinned == target.isPinned else { return }

        var ordered = Self.ordered(notes)
        guard let fromIndex = ordered.firstIndex(where: { $0.id == id }) else { return }
        let note = ordered.remove(at: fromIndex)
        guard let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        let insertionIndex = placement == .before ? targetIndex : targetIndex + 1
        ordered.insert(note, at: min(insertionIndex, ordered.count))

        for (index, item) in ordered.enumerated() {
            guard let noteIndex = notes.firstIndex(where: { $0.id == item.id }) else { continue }
            notes[noteIndex].sortOrder = index
        }
        scheduleReorderPersistence()
    }

    private func scheduleReorderPersistence() {
        hasPendingPersistence = true
        pendingPersistTask?.cancel()
        pendingPersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self?.flushPendingPersistence()
        }
    }

    private static func ordered(_ notes: [NookNote]) -> [NookNote] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private static let sampleNotes: [NookNote] = [
        NookNote(
            id: UUID(),
            title: "Kingo için yön",
            body: "Menü çubuğunda tek tık → sağdan açılan panel → düşünceyi hemen bırak.\n\nİlk hareket her zaman yazmak olmalı; klasörleme sonra.",
            tag: "Ideas",
            tint: .amber,
            isPinned: true,
            updatedAt: .now.addingTimeInterval(-60 * 7)
        ),
        NookNote(
            id: UUID(),
            title: "Referanslar / koyu yüzey",
            body: "Grafit zemin, kirli beyaz metin, tek sıcak vurgu. Derinlik gölgeyle değil katman aralığıyla gelsin.",
            tag: "Design",
            tint: .lavender,
            isPinned: false,
            updatedAt: .now.addingTimeInterval(-60 * 34)
        ),
        NookNote(
            id: UUID(),
            title: "Bu hafta",
            body: "□ Side panel açılışını test et\n□ Notları JSON’a yaz\n□ Menü çubuğu ikonunu sadeleştir",
            tag: "Tasks",
            tint: .mint,
            isPinned: false,
            updatedAt: .now.addingTimeInterval(-60 * 60 * 3)
        ),
        NookNote(
            id: UUID(),
            title: "Akşam fikri",
            body: "Notlar bir light table gibi dursun: seçilen parça biraz öne çıksın, geri kalanlar sessizce akışta kalsın.",
            tag: "Personal",
            tint: .coral,
            isPinned: false,
            updatedAt: .now.addingTimeInterval(-60 * 60 * 24 * 2)
        )
    ]
}
