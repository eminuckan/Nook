import Foundation
import Combine

struct NookTag: Identifiable, Codable, Equatable {
    let name: String
    var tint: NookNote.Tint
    var isBuiltIn: Bool

    var id: String { name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
}

@MainActor
final class TagStore: ObservableObject {
    @Published private(set) var tags: [NookTag]
    let legacyBuiltInRenames: [String: String]
    private let defaults: UserDefaults
    private var pendingLegacyTags: [NookTag]

    private static let userDefaultsKey = "nook.tags"

    init(notes: [NookNote] = [], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved: [NookTag]
        if let data = defaults.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([NookTag].self, from: data) {
            saved = decoded
        } else {
            saved = []
        }

        // Only metadata explicitly marked as a shipped default may be renamed.
        // A custom tag with the same spelling remains the user's own label.
        legacyBuiltInRenames = Dictionary(saved.compactMap { tag in
            guard tag.isBuiltIn, let name = Self.legacyNames[tag.name] else { return nil }
            return (tag.name, name)
        }, uniquingKeysWith: { first, _ in first })
        pendingLegacyTags = saved.filter { $0.isBuiltIn && Self.legacyNames[$0.name] != nil }
        var merged = Self.builtIns
        for tag in saved where legacyBuiltInRenames[tag.name] == nil && !merged.contains(where: { $0.id == tag.id }) {
            merged.append(tag)
        }
        for note in notes {
            let name = legacyBuiltInRenames[note.tag] ?? note.tag
            if let index = merged.firstIndex(where: { $0.id == name.nookTagID }) {
                if merged[index].isBuiltIn == false { merged[index].tint = note.tint }
            } else if note.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                merged.append(NookTag(name: name, tint: note.tint, isBuiltIn: false))
            }
        }
        tags = merged
        // Keep legacy metadata until the note migration has reached disk, so
        // a failed save can be retried on the next launch without losing intent.
        if legacyBuiltInRenames.isEmpty { persist() }
    }

    func finishBuiltInMigration() {
        pendingLegacyTags = []
        persist()
    }

    @discardableResult
    func create(name: String, tint: NookNote.Tint) -> NookTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pendingLegacyTags.contains(where: { $0.id == trimmed.nookTagID }) else { return nil }
        guard trimmed.isEmpty == false,
              !tags.contains(where: { $0.id == trimmed.nookTagID }) else {
            return tags.first(where: { $0.id == trimmed.nookTagID })
        }

        let tag = NookTag(name: trimmed, tint: tint, isBuiltIn: false)
        tags.append(tag)
        persist()
        return tag
    }

    func tint(for name: String) -> NookNote.Tint {
        tags.first(where: { $0.id == name.nookTagID })?.tint ?? .amber
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tags + pendingLegacyTags) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    private static let builtIns: [NookTag] = [
        NookTag(name: "Inbox", tint: .amber, isBuiltIn: true),
        NookTag(name: "Ideas", tint: .amber, isBuiltIn: true),
        NookTag(name: "Design", tint: .lavender, isBuiltIn: true),
        NookTag(name: "Tasks", tint: .mint, isBuiltIn: true),
        NookTag(name: "Personal", tint: .coral, isBuiltIn: true)
    ]

    private static let legacyNames = ["Fikir": "Ideas", "Tasarım": "Design", "Görev": "Tasks", "Kişisel": "Personal"]
}

private extension String {
    var nookTagID: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
