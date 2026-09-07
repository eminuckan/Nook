import Foundation
import Combine

enum NookLanguage: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    var shortLabel: String { rawValue.uppercased() }

    /// Nook only ships Turkish and English copy. For every other system
    /// locale, English is the predictable fallback.
    static var system: NookLanguage {
        let identifier = Locale.preferredLanguages.first?.lowercased()
            ?? Locale.current.identifier.lowercased()
        return identifier.hasPrefix("tr") ? .turkish : .english
    }

    var nativeName: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    var next: NookLanguage {
        self == .turkish ? .english : .turkish
    }
}

enum NookLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case turkish
    case english

    var id: String { rawValue }

    var resolved: NookLanguage {
        switch self {
        case .system: return .system
        case .turkish: return .turkish
        case .english: return .english
        }
    }
}

@MainActor
final class NookLanguageStore: ObservableObject {
    @Published var preference: NookLanguagePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.preferenceKey)
        }
    }

    var current: NookLanguage { preference.resolved }

    private static let preferenceKey = "nook.language.preference"
    private static let legacyKey = "nook.language"

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.preferenceKey),
           let preference = NookLanguagePreference(rawValue: saved) {
            self.preference = preference
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyKey),
                  let language = NookLanguage(rawValue: legacy) {
            // Preserve a choice made by an earlier build, while giving new
            // installs the explicit System default in the settings screen.
            self.preference = language == .turkish ? .turkish : .english
        } else {
            self.preference = .system
        }
    }

    func toggle() {
        preference = current.next == .turkish ? .turkish : .english
    }

    func setPreference(_ preference: NookLanguagePreference) {
        self.preference = preference
    }
}

struct NookStrings {
    let language: NookLanguage

    var tagline: String {
        language == .turkish ? "düşüncenin kenardaki yeri" : "a quiet place at the edge"
    }

    var searchPlaceholder: String { language == .turkish ? "Notlarda ara" : "Search notes" }
    var searchAccessibility: String { language == .turkish ? "Notlarda ara" : "Search notes" }
    var clearSearch: String { language == .turkish ? "Aramayı temizle" : "Clear search" }
    var recentNotes: String { language == .turkish ? "Son notlar" : "Recent notes" }
    var reorderNotes: String { language == .turkish ? "Notları sırala" : "Arrange notes" }
    var finishReordering: String { language == .turkish ? "Sıralamayı bitir" : "Finish arranging" }
    var reorderHint: String { language == .turkish ? "Notu sürükleyerek sırala" : "Drag a note to arrange" }
    var settingsTitle: String { language == .turkish ? "Ayarlar" : "Settings" }
    var settingsHint: String { language == .turkish ? "Ayarları aç" : "Open settings" }
    var languageSection: String { language == .turkish ? "Dil" : "Language" }
    var languageDescription: String { language == .turkish ? "Varsayılan olarak sistem dilini kullanır." : "Uses your system language by default." }
    var languageSystem: String { language == .turkish ? "Sistem" : "System" }
    var languageTurkish: String { "Türkçe" }
    var languageEnglish: String { "English" }
    var appearanceSection: String { language == .turkish ? "Görünüm" : "Appearance" }
    var appearanceDescription: String { language == .turkish ? "Renkleri macOS görünümüne bırak veya sabitle." : "Follow macOS or keep a fixed appearance." }
    var appearanceSystem: String { language == .turkish ? "Sistem" : "System" }
    var appearanceLight: String { language == .turkish ? "Açık" : "Light" }
    var appearanceDark: String { language == .turkish ? "Koyu" : "Dark" }
    var behaviorSection: String { language == .turkish ? "Çalışma alanı" : "Workspace" }
    var keepAcrossSpaces: String { language == .turkish ? "Masaüstlerinde görünür tut" : "Keep visible across Spaces" }
    var keepAcrossSpacesDescription: String { language == .turkish ? "Nook, masaüstleri arasında geçerken yerini korur." : "Nook keeps its place while you move between Spaces." }
    var shortcutSection: String { language == .turkish ? "Kısayol" : "Shortcut" }
    var shortcutDescription: String { language == .turkish ? "Notları açmak için klavye kısayolu. Sistem çakışmaları kontrol edilir." : "Keyboard shortcut for opening Nook. System conflicts are checked." }
    var openNotesShortcut: String { language == .turkish ? "Notları aç" : "Open notes" }
    var shortcutChange: String { language == .turkish ? "Değiştir" : "Change" }
    var shortcutListening: String { language == .turkish ? "Tuşlara bas…" : "Press keys…" }
    var shortcutListeningHint: String { language == .turkish ? "Bir modifier ve bir tuşa bas · Esc iptal eder" : "Press a modifier and a key · Esc cancels" }
    var shortcutModifierRequired: String { language == .turkish ? "⌘, ⌥, ⌃ veya ⇧ tuşlarından en az birini ekle." : "Add at least one of ⌘, ⌥, ⌃, or ⇧." }
    var shortcutConflictUnavailable: String { language == .turkish ? "Bu kombinasyon başka bir uygulama tarafından kullanılıyor olabilir." : "Another app may already be using this combination." }
    var quitNook: String { language == .turkish ? "Nook’tan çık" : "Quit Nook" }
    func shortcutConflictSystem(_ name: String) -> String { language == .turkish ? "Bu kombinasyon \(name) ile çakışıyor. Başka bir kombinasyon dene." : "This combination conflicts with \(name). Try another one." }
    var systemLanguageValue: String {
        let name = NookLanguage.system.nativeName
        return language == .turkish ? "Sistem · \(name)" : "System · \(name)"
    }
    var localStorage: String { language == .turkish ? "yerel olarak saklanıyor" : "stored locally" }
    var readyForThought: String { language == .turkish ? "Yeni bir düşünce için hazır" : "Ready for a fresh thought" }
    var newNote: String { language == .turkish ? "Yeni not" : "New note" }
    var captureHint: String { language == .turkish ? "Yakalamak için" : "Capture with" }
    var leaveFirstNote: String { language == .turkish ? "İlk notunu bırak" : "Leave your first note" }
    var noMatches: String { language == .turkish ? "Eşleşen not yok" : "No matching notes" }
    var emptyHint: String { language == .turkish ? "Aklındaki şeyi burada tut; sonra geri dönersin." : "Keep the thought here and come back to it later." }
    var noMatchesHint: String { language == .turkish ? "Başka bir kelime dene veya aramayı temizle." : "Try another word or clear the search." }
    var editNote: String { language == .turkish ? "Notu düzenle" : "Edit note" }
    var backToNotes: String { language == .turkish ? "Notlara dön" : "Back to notes" }
    var closePanel: String { language == .turkish ? "Paneli kapat" : "Close panel" }
    var noteTitle: String { language == .turkish ? "Not başlığı" : "Note title" }
    var titlePlaceholder: String { language == .turkish ? "Başlık" : "Title" }
    var noteBody: String { language == .turkish ? "Not içeriği" : "Note content" }
    var bodyPlaceholder: String { language == .turkish ? "Buraya aklındaki şeyi bırak…" : "Drop the thought here…" }
    var autosaved: String { language == .turkish ? "Otomatik kaydedildi" : "Saved locally" }
    var editorHint: String { language == .turkish ? "Seçerek biçimlendir" : "Select text to format" }
    var formatting: String { language == .turkish ? "Biçimlendirme" : "Formatting" }
    var formatMenu: String { language == .turkish ? "Metin biçimi" : "Text format" }
    var listMenu: String { language == .turkish ? "Liste seçenekleri" : "List options" }
    var insertTable: String { language == .turkish ? "Tablo ekle" : "Insert table" }
    var addAttachment: String { language == .turkish ? "Ek ekle" : "Add attachment" }
    var choosePhotoOrVideo: String { language == .turkish ? "Fotoğraf veya video seç" : "Choose Photo or Video" }
    var attachFile: String { language == .turkish ? "Dosya ekle" : "Attach File" }
    var formatBold: String { language == .turkish ? "Kalın" : "Bold" }
    var formatItalic: String { language == .turkish ? "İtalik" : "Italic" }
    var formatStrike: String { language == .turkish ? "Üstü çizili" : "Strikethrough" }
    var formatCode: String { language == .turkish ? "Kod" : "Code" }
    var formatTitle: String { language == .turkish ? "Başlık" : "Title" }
    var formatHeading: String { language == .turkish ? "Başlık 2" : "Heading" }
    var formatSubheading: String { language == .turkish ? "Alt başlık" : "Subheading" }
    var formatBody: String { language == .turkish ? "Gövde" : "Body" }
    var formatMonospaced: String { language == .turkish ? "Sabit genişlik" : "Monospaced" }
    var formatBulletedList: String { language == .turkish ? "Madde işaretli liste" : "Bulleted list" }
    var formatDashedList: String { language == .turkish ? "Çizgili liste" : "Dashed list" }
    var formatNumberedList: String { language == .turkish ? "Numaralı liste" : "Numbered list" }
    var formatBlockQuote: String { language == .turkish ? "Alıntı" : "Block quote" }
    var tagLabel: String { language == .turkish ? "Etiket" : "Tag" }
    var chooseTag: String { language == .turkish ? "Etiket seç" : "Choose tag" }
    var manageTags: String { language == .turkish ? "Etiketleri yönet" : "Manage tags" }
    var tagNamePlaceholder: String { language == .turkish ? "Etiket adı" : "Tag name" }
    var addTag: String { language == .turkish ? "Ekle" : "Add" }
    var chooseColor: String { language == .turkish ? "Renk seç" : "Choose color" }
    var existingTags: String { language == .turkish ? "Etiketlerin" : "Your tags" }
    var tagExists: String { language == .turkish ? "Bu etiket zaten var" : "That tag already exists" }
    var pin: String { language == .turkish ? "Notu sabitle" : "Pin note" }
    var unpin: String { language == .turkish ? "Sabitlemeyi kaldır" : "Unpin note" }
    var deleteNote: String { language == .turkish ? "Notu sil" : "Delete note" }
    var pinned: String { language == .turkish ? "Sabit" : "Pinned" }
    var today: String { language == .turkish ? "Bugün" : "Today" }
    var all: String { language == .turkish ? "Hepsi" : "All" }
    var noTitle: String { language == .turkish ? "Başlıksız not" : "Untitled note" }
    var openNoteHint: String { language == .turkish ? "Notu açmak için tıklayın" : "Click to open this note" }
    var languageHint: String { language == .turkish ? "English’e geç" : "Türkçe’ye geç" }
    var languageLabel: String { language == .turkish ? "Dil: Türkçe" : "Language: English" }
    var panelTooltip: String { language == .turkish ? "Nook — hızlı notlar" : "Nook — quick notes" }
    var cardTitle: String { "Nook" }

    func filterTitle(_ filter: NoteFilter) -> String {
        switch filter {
        case .all: return all
        case .pinned: return pinned
        case .today: return today
        }
    }
}

extension NookLanguageStore {
    var strings: NookStrings { NookStrings(language: current) }
}
