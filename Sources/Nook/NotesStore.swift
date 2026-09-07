import Foundation
import Combine

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [NookNote]

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pendingPersistTask: Task<Void, Never>?
    private var hasPendingPersistence = false

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = appSupport.appendingPathComponent("Nook", isDirectory: true)
        fileURL = directory.appendingPathComponent("notes.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? decoder.decode([NookNote].self, from: data) {
            var loaded = saved.sorted { $0.updatedAt > $1.updatedAt }
            for index in loaded.indices where loaded[index].sortOrder == nil {
                loaded[index].sortOrder = index
            }
            notes = Self.ordered(loaded)
        } else {
            var seeded = Self.sampleNotes
            for index in seeded.indices { seeded[index].sortOrder = index }
            notes = Self.ordered(seeded)
        }
    }

    var pinnedCount: Int { notes.filter(\.isPinned).count }

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
        notes[index].title = title
        notes[index].body = body
        notes[index].bodyRTF = bodyRTF
        if let tag, tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            notes[index].tag = tag
        }
        if let tint { notes[index].tint = tint }
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
        hasPendingPersistence = false
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
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(notes)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Nook could not save notes: %@", error.localizedDescription)
        }
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
            tag: "Fikir",
            tint: .amber,
            isPinned: true,
            updatedAt: .now.addingTimeInterval(-60 * 7)
        ),
        NookNote(
            id: UUID(),
            title: "Referanslar / koyu yüzey",
            body: "Grafit zemin, kirli beyaz metin, tek sıcak vurgu. Derinlik gölgeyle değil katman aralığıyla gelsin.",
            tag: "Tasarım",
            tint: .lavender,
            isPinned: false,
            updatedAt: .now.addingTimeInterval(-60 * 34)
        ),
        NookNote(
            id: UUID(),
            title: "Bu hafta",
            body: "□ Side panel açılışını test et\n□ Notları JSON’a yaz\n□ Menü çubuğu ikonunu sadeleştir",
            tag: "Görev",
            tint: .mint,
            isPinned: false,
            updatedAt: .now.addingTimeInterval(-60 * 60 * 3)
        ),
        NookNote(
            id: UUID(),
            title: "Akşam fikri",
            body: "Notlar bir light table gibi dursun: seçilen parça biraz öne çıksın, geri kalanlar sessizce akışta kalsın.",
            tag: "Kişisel",
            tint: .coral,
            isPinned: false,
            updatedAt: .now.addingTimeInterval(-60 * 60 * 24 * 2)
        )
    ]
}
