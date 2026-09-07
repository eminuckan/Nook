import AppKit
import SwiftUI

struct NookNote: Identifiable, Codable, Equatable {
    enum Tint: String, Codable, CaseIterable {
        case amber
        case coral
        case lavender
        case mint
        case blue

        var color: Color {
            switch self {
            case .amber: return .nookAmber
            case .coral: return .nookCoral
            case .lavender: return .nookLavender
            case .mint: return .nookMint
            case .blue: return .nookBlue
            }
        }

        var accessibilityName: String {
            switch self {
            case .amber: return "amber"
            case .coral: return "coral"
            case .lavender: return "lavender"
            case .mint: return "mint"
            case .blue: return "blue"
            }
        }

        /// The tint palette is retained for tag labels, chips, and other small
        /// state marks; note rows themselves stay on a quiet neutral surface.
        func paperColor(isDark: Bool) -> Color {
            let components: (CGFloat, CGFloat, CGFloat)
            if isDark {
                switch self {
                case .amber: components = (0.40, 0.29, 0.14)
                case .coral: components = (0.45, 0.24, 0.18)
                case .lavender: components = (0.29, 0.23, 0.42)
                case .mint: components = (0.24, 0.33, 0.24)
                case .blue: components = (0.10, 0.35, 0.40)
                }
            } else {
                switch self {
                case .amber: components = (0.98, 0.76, 0.43)
                case .coral: components = (1.00, 0.61, 0.46)
                case .lavender: components = (0.62, 0.50, 0.78)
                case .mint: components = (0.64, 0.72, 0.42)
                case .blue: components = (0.08, 0.64, 0.72)
                }
            }
            return Color(nsColor: NSColor(srgbRed: components.0, green: components.1, blue: components.2, alpha: 1))
        }

        func paperInk(isDark: Bool) -> Color {
            isDark ? .nookCardLightInk : .nookCardInk
        }
    }

    var id: UUID
    var title: String
    var body: String
    /// Optional RTF keeps the body editor's formatting without breaking the
    /// plain-text title/body preview and search contract used by the list.
    /// Legacy composite streams are reduced to the body when opened.
    var bodyRTF: Data? = nil
    var tag: String
    var tint: Tint
    var isPinned: Bool
    /// Stable manual order for drag-and-drop arrangement. Optional keeps old
    /// notes.json files decodable; NotesStore fills missing values on load.
    var sortOrder: Int? = nil
    var updatedAt: Date

    func preview(for language: NookLanguage) -> String {
        let flattened = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.isEmpty == false else {
            return language == .turkish ? "Boş not" : "Empty note"
        }
        return flattened
    }

    func relativeDate(for language: NookLanguage) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language == .turkish ? "tr_TR" : "en_US")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: .now)
    }
}

enum NoteFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case today

    var id: String { rawValue }

}

enum NookPalette {
    static let ink = Color(nsColor: NSColor(srgbRed: 0.055, green: 0.061, blue: 0.074, alpha: 1))
    static let inkRaised = Color(nsColor: NSColor(srgbRed: 0.088, green: 0.098, blue: 0.118, alpha: 1))
    static let inkSoft = Color(nsColor: NSColor(srgbRed: 0.115, green: 0.125, blue: 0.149, alpha: 1))
    static let line = Color(nsColor: NSColor(srgbRed: 0.21, green: 0.225, blue: 0.255, alpha: 0.62))
    static let text = Color(nsColor: NSColor(srgbRed: 0.93, green: 0.925, blue: 0.9, alpha: 1))
    static let textMuted = Color(nsColor: NSColor(srgbRed: 0.59, green: 0.6, blue: 0.63, alpha: 1))
    static let textFaint = Color(nsColor: NSColor(srgbRed: 0.38, green: 0.4, blue: 0.44, alpha: 1))
    static let amber = Color(nsColor: NSColor(srgbRed: 0.95, green: 0.62, blue: 0.28, alpha: 1))
    static let pinYellow = Color(nsColor: NSColor(srgbRed: 0.99, green: 0.72, blue: 0.16, alpha: 1))
    static let coral = Color(nsColor: NSColor(srgbRed: 0.95, green: 0.42, blue: 0.38, alpha: 1))
    static let lavender = Color(nsColor: NSColor(srgbRed: 0.67, green: 0.57, blue: 0.95, alpha: 1))
    static let mint = Color(nsColor: NSColor(srgbRed: 0.36, green: 0.79, blue: 0.66, alpha: 1))
    static let blue = Color(nsColor: NSColor(srgbRed: 0.36, green: 0.63, blue: 0.95, alpha: 1))
    static let cardInkNS = NSColor(srgbRed: 0.105, green: 0.12, blue: 0.125, alpha: 1)
    static let cardLightSurfaceNS = NSColor(srgbRed: 0.94, green: 0.945, blue: 0.94, alpha: 1)
}

extension Color {
    static let nookInk = NookPalette.ink
    static let nookInkRaised = NookPalette.inkRaised
    static let nookInkSoft = NookPalette.inkSoft
    static let nookLine = NookPalette.line
    static let nookText = NookPalette.text
    static let nookTextMuted = NookPalette.textMuted
    static let nookTextFaint = NookPalette.textFaint
    static let nookAmber = NookPalette.amber
    static let nookPinYellow = NookPalette.pinYellow
    static let nookCoral = NookPalette.coral
    static let nookLavender = NookPalette.lavender
    static let nookMint = NookPalette.mint
    static let nookBlue = NookPalette.blue
    // Light appearance stays neutral: the inner work surface is a cool gray
    // that is visibly lighter than the pale-gray shell without reading beige.
    static let nookCardInk = Color(nsColor: NookPalette.cardInkNS)
    static let nookCardMuted = Color(nsColor: NSColor(srgbRed: 0.39, green: 0.42, blue: 0.425, alpha: 1))
    static let nookCardLightSurface = Color(nsColor: NookPalette.cardLightSurfaceNS)
    static let nookCardLightRaised = Color(nsColor: NSColor(srgbRed: 0.967, green: 0.972, blue: 0.968, alpha: 1))
    static let nookCardDark = Color(nsColor: NSColor(srgbRed: 0.095, green: 0.095, blue: 0.09, alpha: 1))
    static let nookCardLightInk = Color(nsColor: NSColor(srgbRed: 0.95, green: 0.94, blue: 0.9, alpha: 1))
    static let nookCardLightMuted = Color(nsColor: NSColor(srgbRed: 0.68, green: 0.67, blue: 0.63, alpha: 1))
    static let nookShellLight = Color(nsColor: NSColor(srgbRed: 0.89, green: 0.90, blue: 0.88, alpha: 1))
    static let nookShellDark = Color(nsColor: NSColor(srgbRed: 0.19, green: 0.195, blue: 0.19, alpha: 1))

}
