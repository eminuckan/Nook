import AppKit
import Combine
import SwiftUI

enum NookAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Preferences that affect the panel itself rather than an individual note.
/// They are intentionally small, local, and reversible so the menu-bar card
/// stays quick to use.
@MainActor
final class NookSettingsStore: ObservableObject {
    @Published var appearance: NookAppearancePreference {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    @Published var keepPanelAcrossSpaces: Bool {
        didSet { UserDefaults.standard.set(keepPanelAcrossSpaces, forKey: Self.spacesKey) }
    }

    @Published var openNotesShortcut: NookShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(openNotesShortcut) {
                UserDefaults.standard.set(data, forKey: Self.shortcutKey)
            }
        }
    }

    private static let appearanceKey = "nook.appearance"
    private static let spacesKey = "nook.keep-panel-across-spaces"
    private static let shortcutKey = "nook.open-notes-shortcut"

    init() {
        let savedAppearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
        appearance = savedAppearance.flatMap(NookAppearancePreference.init(rawValue:)) ?? .system

        if UserDefaults.standard.object(forKey: Self.spacesKey) == nil {
            keepPanelAcrossSpaces = true
        } else {
            keepPanelAcrossSpaces = UserDefaults.standard.bool(forKey: Self.spacesKey)
        }

        if let data = UserDefaults.standard.data(forKey: Self.shortcutKey),
           let savedShortcut = try? JSONDecoder().decode(NookShortcut.self, from: data) {
            openNotesShortcut = savedShortcut
        } else {
            openNotesShortcut = .defaultValue
        }
    }
}
