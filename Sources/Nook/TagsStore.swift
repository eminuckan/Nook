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

    private static let userDefaultsKey = "nook.tags"

    init(notes: [NookNote] = []) {
        let saved: [NookTag]
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([NookTag].self, from: data) {
            saved = decoded
        } else {
            saved = []
        }

        var merged = Self.builtIns
        for tag in saved where !merged.contains(where: { $0.id == tag.id }) {
            merged.append(tag)
        }
        for note in notes {
            if let index = merged.firstIndex(where: { $0.id == note.tag.nookTagID }) {
                if merged[index].isBuiltIn == false { merged[index].tint = note.tint }
            } else if note.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                merged.append(NookTag(name: note.tag, tint: note.tint, isBuiltIn: false))
            }
        }
        tags = merged
        persist()
    }

    @discardableResult
    func create(name: String, tint: NookNote.Tint) -> NookTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let data = try? JSONEncoder().encode(tags) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    private static let builtIns: [NookTag] = [
        NookTag(name: "Inbox", tint: .amber, isBuiltIn: true),
        NookTag(name: "Fikir", tint: .amber, isBuiltIn: true),
        NookTag(name: "Tasarım", tint: .lavender, isBuiltIn: true),
        NookTag(name: "Görev", tint: .mint, isBuiltIn: true),
        NookTag(name: "Kişisel", tint: .coral, isBuiltIn: true)
    ]
}

private extension String {
    var nookTagID: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
