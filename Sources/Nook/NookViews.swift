import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum NookLayout {
    /// The compact rhythm reserved for repeated list surfaces. Keeping the
    /// list edge inset and sibling gap identical makes its final row land as
    /// cleanly as the first row.
    static let contentInset: CGFloat = 8
    static let itemGap: CGFloat = 8
    static let sectionGap: CGFloat = 20
    /// Comfortable reading inset for secondary surfaces. The notes list is
    /// intentionally tighter; Settings and the editor use this wider rail so
    /// their controls do not hug the nested surface edge.
    static let comfortableInset: CGFloat = 24
    /// The editor surface is radius 28 and its circular controls are radius
    /// 15. A 13pt inset keeps the nested corner relationship exact:
    /// 15pt control radius + 13pt breathing room = 28pt parent radius.
    static let nestedControlInset: CGFloat = 13
    static let editorTextInset: CGFloat = 14
    static let editorTextVerticalInset: CGFloat = 12
    static let titleBodyGap: CGFloat = 8
}

struct NookRootView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var tagStore: TagStore
    @ObservedObject var settings: NookSettingsStore
    @ObservedObject var shortcutManager: NookShortcutManager
    let onClose: () -> Void
    let onSpacesPreferenceChanged: (Bool) -> Void

    @EnvironmentObject private var language: NookLanguageStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var filter: NoteFilter = .all
    @State private var selectedID: UUID?
    @State private var showingSettings = false
    @State private var navigationDirection: NookNavigationDirection = .forward

    private var effectiveIsDark: Bool {
        switch settings.appearance {
        case .system: return colorScheme == .dark
        case .light: return false
        case .dark: return true
        }
    }

    var body: some View {
        ZStack {
            NookCardCanvas()

            NookCardFrame(
                isDark: effectiveIsDark,
                onSettings: showSettings,
                onClose: onClose
            ) {
                ZStack(alignment: .topLeading) {
                    if let selectedID, let note = store.note(id: selectedID) {
                        NoteEditorCard(
                            note: note,
                            tagStore: tagStore,
                            isDark: effectiveIsDark,
                            onBack: returnToNotes,
                            onTogglePinned: { store.togglePinned(id: note.id) },
                            onDelete: {
                                store.delete(id: note.id)
                                returnToNotes()
                            },
                            onSave: { title, body, bodyRTF, tag, tint in
                                store.update(id: note.id, title: title, body: body, bodyRTF: bodyRTF, tag: tag, tint: tint)
                            }
                        )
                        .transition(contentTransition)
                    } else if showingSettings {
                        SettingsCard(
                            settings: settings,
                            shortcutManager: shortcutManager,
                            isDark: effectiveIsDark,
                            onBack: returnToNotes,
                            onSpacesPreferenceChanged: onSpacesPreferenceChanged
                        )
                        .transition(contentTransition)
                    } else {
                        NotesDashboardCard(
                            store: store,
                            searchText: $searchText,
                            filter: $filter,
                            isDark: effectiveIsDark,
                            onCreate: createNote,
                            onSelect: openNote
                        )
                        .transition(contentTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .animation(.easeInOut(duration: 0.26), value: contentRoute)
            }
        }
        .frame(width: 420, height: 800)
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    private func createNote() {
        let note = store.addNote()
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.26)) { selectedID = note.id }
    }

    private func showSettings() {
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.26)) {
            selectedID = nil
            showingSettings = true
        }
    }

    private func openNote(_ id: UUID) {
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.26)) { selectedID = id }
    }

    private func returnToNotes() {
        navigationDirection = .backward
        withAnimation(.easeInOut(duration: 0.26)) {
            selectedID = nil
            showingSettings = false
        }
    }

    private var contentRoute: String {
        if let selectedID {
            return "editor-\(selectedID.uuidString)"
        }
        return showingSettings ? "settings" : "notes"
    }

    private var contentTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

private enum NookNavigationDirection {
    case forward
    case backward
}

private struct NookCardCanvas: View {
    var body: some View {
        Color.clear
            .ignoresSafeArea()
    }
}

private struct NookCardFrame<Content: View>: View {
    let isDark: Bool
    let onSettings: () -> Void
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(isDark ? Color.nookShellDark : Color.nookShellLight)

            VStack(spacing: 0) {
                // The shell header owns the stable chrome. Only the inner
                // surface below it is replaced and animated between routes.
                CardTopBar(
                    title: "Nook",
                    subtitle: Date.now.formatted(.dateTime.hour().minute()),
                    isDark: isDark,
                    onSettings: onSettings,
                    onClose: onClose
                )

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
        .frame(width: 420, height: 800)
    }
}

private struct CardTopBar: View {
    let title: String
    let subtitle: String
    let isDark: Bool
    let onSettings: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var shellInk: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var shellControl: Color { isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.06) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(shellInk)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(shellInk.opacity(0.68))
            }

            Spacer()

            HStack(spacing: 7) {
                Button {
                    onSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(shellInk)
                        .frame(width: 30, height: 30)
                        .background(shellControl, in: Circle())
                }
                .buttonStyle(.plain)
                .help(language.strings.settingsHint)
                .accessibilityLabel(language.strings.settingsHint)

                Button(action: onClose) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(shellInk)
                        .frame(width: 30, height: 30)
                        .background(shellControl, in: Circle())
                }
                .buttonStyle(.plain)
                .help("\(language.strings.closePanel) (Esc)")
                .accessibilityLabel(language.strings.closePanel)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 22)
        .frame(height: 76, alignment: .top)
    }
}

private struct NotesDashboardCard: View {
    @ObservedObject var store: NotesStore
    @Binding var searchText: String
    @Binding var filter: NoteFilter

    let isDark: Bool
    let onCreate: () -> Void
    let onSelect: (UUID) -> Void

    @EnvironmentObject private var language: NookLanguageStore
    @FocusState private var searchFocused: Bool
    @State private var searchExpanded = false
    @State private var hoveredID: UUID?
    @State private var isReordering = false
    @State private var draggedID: UUID?
    @State private var dropTargetID: UUID?
    @State private var dropPlacement: NoteDropPlacement?
    @State private var lastReorderKey: String?

    private var visibleNotes: [NookNote] {
        store.visibleNotes(query: searchText, filter: filter)
    }

    private var cardSurface: Color { isDark ? .nookCardDark : .nookCardLightSurface }
    private var cardInk: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var cardMuted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(language.strings.recentNotes)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(cardInk)
                                Text(isReordering
                                    ? language.strings.reorderHint
                                    : (visibleNotes.isEmpty ? language.strings.readyForThought : "\(visibleNotes.count) \(language.current == .turkish ? "not" : "notes")"))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(cardMuted)
                            }

                            Spacer()

                            HStack(spacing: 7) {
                                Button(action: onCreate) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(cardInk)
                                        .frame(width: 32, height: 32)
                                        .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .help(language.strings.newNote)
                                .accessibilityLabel(language.strings.newNote)

                                Button {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            isReordering.toggle()
                                            draggedID = nil
                                            dropTargetID = nil
                                            dropPlacement = nil
                                            lastReorderKey = nil
                                            hoveredID = nil
                                        }
                                } label: {
                                    Image(systemName: isReordering ? "checkmark" : "arrow.up.arrow.down")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(isReordering ? (isDark ? Color.nookCardDark : Color.nookCardLightSurface) : cardInk)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            isReordering
                                                ? (isDark ? Color.nookCardLightInk : Color.nookCardInk)
                                                : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)),
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(isReordering ? language.strings.finishReordering : language.strings.reorderNotes)
                                .accessibilityLabel(isReordering ? language.strings.finishReordering : language.strings.reorderNotes)

                                if searchExpanded {
                                    HStack(spacing: 6) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 11, weight: .semibold))
                                        TextField(language.strings.searchPlaceholder, text: $searchText)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                            .focused($searchFocused)
                                            .frame(width: 112)
                                        Button {
                                            searchText = ""
                                            searchExpanded = false
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(language.strings.clearSearch)
                                    }
                                    .foregroundStyle(cardMuted)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), in: Capsule())
                                    .onAppear { searchFocused = true }
                                } else {
                                    Button {
                                        withAnimation(.easeOut(duration: 0.16)) { searchExpanded = true }
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(cardInk)
                                            .frame(width: 32, height: 32)
                                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help(language.strings.searchAccessibility)
                                    .accessibilityLabel(language.strings.searchAccessibility)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 25)
                        .padding(.bottom, 15)

                        CardTabs(filter: $filter, pinnedCount: store.pinnedCount, isDark: isDark)
                            .padding(.horizontal, NookLayout.contentInset)
                            .padding(.bottom, NookLayout.itemGap)

                        if visibleNotes.isEmpty {
                            EmptyCardState(searchText: searchText, isDark: isDark, onCreate: onCreate)
                        } else {
                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: NookLayout.itemGap) {
                                    ForEach(visibleNotes) { note in
                                        CardNoteRow(
                                            note: note,
                                            isDark: isDark,
                                            isHovered: hoveredID == note.id,
                                            isReordering: isReordering,
                                            isDragged: draggedID == note.id,
                                            isDropTarget: dropTargetID == note.id,
                                            draggedID: $draggedID,
                                            dropTargetID: $dropTargetID,
                                            dropPlacement: $dropPlacement,
                                            lastReorderKey: $lastReorderKey,
                                            noteOrder: visibleNotes,
                                            onSelect: { onSelect(note.id) },
                                            onTogglePinned: { store.togglePinned(id: note.id) },
                                            onHover: { hovering in hoveredID = hovering ? note.id : nil },
                                            onReorder: { movingID, targetID, placement in
                                                switch placement {
                                                case .before:
                                                    store.reorder(id: movingID, before: targetID)
                                                case .after:
                                                    store.reorder(id: movingID, after: targetID)
                                                }
                                            }
                                        )
                                    }
                                    // A zero-height trailing sentinel makes
                                    // LazyVStack materialize one shared item
                                    // gap after the last tile. The shell's
                                    // 10pt bottom inset then matches the
                                    // 10pt + 8pt side rhythm without stacking
                                    // another full inset at the bottom.
                                    Color.clear
                                        .frame(height: 0)
                                }
                                .padding(.horizontal, NookLayout.contentInset)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.top, 8)
            .foregroundStyle(cardInk)
        }
        .background(Color.clear)
    }
}

private struct SettingsCard: View {
    @ObservedObject var settings: NookSettingsStore
    @ObservedObject var shortcutManager: NookShortcutManager
    let isDark: Bool
    let onBack: () -> Void
    let onSpacesPreferenceChanged: (Bool) -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }
    private var rowSurface: Color { isDark ? Color.white.opacity(0.065) : Color.black.opacity(0.045) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: NookLayout.sectionGap) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ink)
                            .frame(width: 30, height: 30)
                            .background(rowSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(language.strings.backToNotes)
                    .accessibilityLabel(language.strings.backToNotes)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(language.strings.settingsTitle)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                    }

                    Spacer()
                }

                NookSettingsSection(
                    title: language.strings.languageSection,
                    detail: language.strings.languageDescription,
                    ink: ink,
                    muted: muted
                ) {
                    SettingsLanguageControl(isDark: isDark, rowSurface: rowSurface)
                }

                NookSettingsSection(
                    title: language.strings.appearanceSection,
                    detail: language.strings.appearanceDescription,
                    ink: ink,
                    muted: muted
                ) {
                    SettingsAppearanceControl(
                        selection: settings.appearance,
                        isDark: isDark,
                        rowSurface: rowSurface,
                        onSelect: { settings.appearance = $0 }
                    )
                }

                NookSettingsSection(
                    title: language.strings.behaviorSection,
                    detail: nil,
                    ink: ink,
                    muted: muted
                ) {
                    SettingsToggleRow(
                        title: language.strings.keepAcrossSpaces,
                        detail: language.strings.keepAcrossSpacesDescription,
                        isOn: settings.keepPanelAcrossSpaces,
                        isDark: isDark,
                        rowSurface: rowSurface,
                        onToggle: {
                            settings.keepPanelAcrossSpaces.toggle()
                            onSpacesPreferenceChanged(settings.keepPanelAcrossSpaces)
                        }
                    )
                }

                NookSettingsSection(
                    title: language.strings.shortcutSection,
                    detail: language.strings.shortcutDescription,
                    ink: ink,
                    muted: muted
                ) {
                    SettingsShortcutControl(
                        settings: settings,
                        shortcutManager: shortcutManager,
                        isDark: isDark,
                        rowSurface: rowSurface
                    )
                }

            }
            .padding(.horizontal, NookLayout.comfortableInset)
            .padding(.top, 22)
            .padding(.bottom, NookLayout.comfortableInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(ink)
        .background(isDark ? Color.nookCardDark : Color.nookCardLightSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.top, 8)
    }
}

private struct NookSettingsSection<Content: View>: View {
    let title: String
    let detail: String?
    let ink: Color
    let muted: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Use a quiet sentence-case label instead of the small tracked
            // all-caps kicker treatment. It reads like a real preference
            // group and keeps the visual hierarchy anchored to the controls.
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)

            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(muted.opacity(0.86))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
    }
}

private struct SettingsLanguageControl: View {
    let isDark: Bool
    let rowSurface: Color

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var active: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var activeText: Color { isDark ? .nookCardDark : .nookCardLightSurface }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }

    var body: some View {
        VStack(alignment: .leading, spacing: NookLayout.itemGap) {
            HStack(spacing: NookLayout.itemGap) {
                ForEach(NookLanguagePreference.allCases) { option in
                    SettingsChoiceButton(
                        title: option.title(using: language.strings),
                        isSelected: language.preference == option,
                        active: active,
                        activeText: activeText,
                        inactiveText: muted,
                        rowSurface: rowSurface,
                        action: { language.setPreference(option) }
                    )
                }
            }

            if language.preference == .system {
                Text(language.strings.systemLanguageValue)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.72))
            }
        }
    }
}

private struct SettingsAppearanceControl: View {
    let selection: NookAppearancePreference
    let isDark: Bool
    let rowSurface: Color
    let onSelect: (NookAppearancePreference) -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var active: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var activeText: Color { isDark ? .nookCardDark : .nookCardLightSurface }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }

    var body: some View {
        HStack(spacing: NookLayout.itemGap) {
            ForEach(NookAppearancePreference.allCases) { option in
                SettingsChoiceButton(
                    title: option.title(using: language.strings),
                    isSelected: selection == option,
                    active: active,
                    activeText: activeText,
                    inactiveText: muted,
                    rowSurface: rowSurface,
                    action: { onSelect(option) }
                )
            }
        }
    }
}

private struct SettingsChoiceButton: View {
    let title: String
    let isSelected: Bool
    let active: Color
    let activeText: Color
    let inactiveText: Color
    let rowSurface: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? activeText : inactiveText)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
                .contentShape(Rectangle())
                .background(isSelected ? active : rowSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let isOn: Bool
    let isDark: Bool
    let rowSurface: Color
    let onToggle: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: NookLayout.itemGap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(detail)
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)
                NookToggle(isOn: isOn, isDark: isDark)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(minHeight: 62)
            .background(rowSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? (language.current == .turkish ? "Açık" : "On") : (language.current == .turkish ? "Kapalı" : "Off"))
    }
}

private struct SettingsShortcutControl: View {
    @ObservedObject var settings: NookSettingsStore
    @ObservedObject var shortcutManager: NookShortcutManager
    let isDark: Bool
    let rowSurface: Color

    @EnvironmentObject private var language: NookLanguageStore
    @StateObject private var captureSession = NookShortcutCaptureSession()
    @State private var isRecording = false
    @State private var draftShortcut: NookShortcut?
    @State private var draftIssue: NookShortcutIssue?

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }
    private var active: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var activeText: Color { isDark ? .nookCardDark : .nookCardLightSurface }

    var body: some View {
        VStack(alignment: .leading, spacing: NookLayout.itemGap) {
            HStack(spacing: NookLayout.itemGap) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 30, height: 30)
                    .background(rowSurface, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(language.strings.openNotesShortcut)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(isRecording
                        ? language.strings.shortcutListeningHint
                        : settings.openNotesShortcut.displayName)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Button(action: toggleRecording) {
                    Text(isRecording
                        ? language.strings.shortcutListening
                        : settings.openNotesShortcut.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isRecording ? activeText : ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(isRecording ? active : rowSurface, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(isRecording ? language.strings.shortcutListening : language.strings.shortcutChange)
                .accessibilityLabel(language.strings.shortcutChange)
            }

            if isRecording {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                    Text(draftShortcut?.displayName ?? language.strings.shortcutListening)
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(muted)
                .padding(.leading, 38)

            }

            if let issue = draftIssue ?? shortcutManager.registrationIssue {
                Label(issueText(issue), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.nookAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(rowSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onDisappear { captureSession.stop() }
    }

    private func toggleRecording() {
        if isRecording {
            cancelRecording()
        } else {
            draftShortcut = nil
            draftIssue = nil
            shortcutManager.clearIssue()
            captureSession.onCapture = capture
            captureSession.onInvalid = { draftIssue = $0 }
            captureSession.onCancel = cancelRecording
            isRecording = true
            captureSession.start()
        }
    }

    private func cancelRecording() {
        captureSession.stop()
        isRecording = false
        draftShortcut = nil
        draftIssue = nil
    }

    private func capture(_ shortcut: NookShortcut) {
        draftShortcut = shortcut
        if let issue = shortcut.issue {
            draftIssue = issue
            return
        }

        guard shortcutManager.setShortcut(shortcut) else {
            draftIssue = shortcutManager.registrationIssue ?? .unavailable
            return
        }

        captureSession.stop()
        isRecording = false
        draftShortcut = nil
        draftIssue = nil
    }

    private func issueText(_ issue: NookShortcutIssue) -> String {
        switch issue {
        case .modifierRequired:
            return language.strings.shortcutModifierRequired
        case let .systemConflict(name):
            return language.strings.shortcutConflictSystem(name)
        case .unavailable:
            return language.strings.shortcutConflictUnavailable
        }
    }
}

private struct NookToggle: View {
    let isOn: Bool
    let isDark: Bool

    private var off: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.1) }
    private var knob: Color { isDark ? .nookCardLightInk : .nookCardLightSurface }

    var body: some View {
        Capsule()
            .fill(isOn ? Color.nookPinYellow : off)
            .frame(width: 38, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Color.nookCardInk : knob)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
            .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

private extension NookLanguagePreference {
    func title(using strings: NookStrings) -> String {
        switch self {
        case .system: return strings.languageSystem
        case .turkish: return strings.languageTurkish
        case .english: return strings.languageEnglish
        }
    }
}

private extension NookAppearancePreference {
    func title(using strings: NookStrings) -> String {
        switch self {
        case .system: return strings.appearanceSystem
        case .light: return strings.appearanceLight
        case .dark: return strings.appearanceDark
        }
    }
}

private struct CardTabs: View {
    @Binding var filter: NoteFilter
    let pinnedCount: Int
    let isDark: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NoteFilter.allCases) { option in
                CardTabButton(
                    option: option,
                    isSelected: filter == option,
                    pinnedCount: pinnedCount,
                    isDark: isDark,
                    onSelect: {
                        withAnimation(.easeOut(duration: 0.16)) { filter = option }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(3)
        .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), in: Capsule())
        .contentShape(Capsule())
    }
}

private struct CardTabButton: View {
    let option: NoteFilter
    let isSelected: Bool
    let pinnedCount: Int
    let isDark: Bool
    let onSelect: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var active: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var activeText: Color { isDark ? .nookCardDark : .nookCardLightSurface }
    private var inactiveText: Color { isDark ? .nookCardLightMuted : .nookCardMuted }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Text(language.strings.filterTitle(option))
                if option == .pinned, pinnedCount > 0 {
                    Text("\(pinnedCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isSelected ? activeText.opacity(0.18) : inactiveText.opacity(0.14), in: Capsule())
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? activeText : inactiveText)
            .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
            .contentShape(Rectangle())
            .background(isSelected ? active : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        // Keep the Button's own hit rectangle equal to the visible tab.
        .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CardNoteRow: View {
    let note: NookNote
    let isDark: Bool
    let isHovered: Bool
    let isReordering: Bool
    let isDragged: Bool
    let isDropTarget: Bool
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?
    @Binding var dropPlacement: NoteDropPlacement?
    @Binding var lastReorderKey: String?
    let noteOrder: [NookNote]
    let onSelect: () -> Void
    let onTogglePinned: () -> Void
    let onHover: (Bool) -> Void
    let onReorder: (UUID, UUID, NoteDropPlacement) -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { note.tint.paperInk(isDark: isDark) }
    private var muted: Color { ink.opacity(isDark ? 0.72 : 0.66) }
    private var rowSurface: Color { isDark ? Color.white.opacity(0.065) : Color.black.opacity(0.045) }

    @ViewBuilder
    var body: some View {
        if isReordering {
            reorderRow
                // In arrange mode the note surface itself is the drag surface.
                // This gives the whole fixed-height card a forgiving hit area
                // and avoids a second control competing with shell dragging.
                .onDrag {
                    draggedID = note.id
                    dropTargetID = nil
                    dropPlacement = nil
                    lastReorderKey = nil
                    onHover(false)
                    return NSItemProvider(object: note.id.uuidString as NSString)
                } preview: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(note.tint.color.opacity(0.9))
                            .frame(width: 8, height: 8)
                        Text(note.title.isEmpty ? language.strings.noTitle : note.title)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 380, height: 86, alignment: .leading)
                    .background(rowSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .onDrop(
                    of: [.text],
                    delegate: NoteDropDelegate(
                        targetID: note.id,
                        draggedID: $draggedID,
                        dropTargetID: $dropTargetID,
                        dropPlacement: $dropPlacement,
                        lastReorderKey: $lastReorderKey,
                        noteOrder: noteOrder,
                        onMove: { movingID, targetID, placement in
                            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86, blendDuration: 0.08)) {
                                onReorder(movingID, targetID, placement)
                            }
                        }
                    )
                )
        } else {
            normalRow
        }
    }

    private var normalRow: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                rowVisual
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHint(language.strings.openNoteHint)
            .accessibilityLabel("\(note.title), \(note.preview(for: language.current))")

            pinButton
                .padding(.top, 10)
                .padding(.trailing, 14)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86)
        .onHover { hovering in
            hovered(hovering)
        }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    private var reorderRow: some View {
        HStack(alignment: .top, spacing: 12) {
            noteText

            Spacer(minLength: 4)

            pinButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86, alignment: .top)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(isDragged ? 1.015 : 1)
        .scaleEffect(isDropTarget ? 1.008 : 1)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.88, blendDuration: 0.04), value: isDragged)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.88, blendDuration: 0.04), value: isDropTarget)
        .accessibilityHint(language.strings.reorderHint)
        .accessibilityLabel("\(note.title), \(note.preview(for: language.current))")
    }

    private var rowVisual: some View {
        HStack(alignment: .top, spacing: 12) {
            noteText

            Spacer(minLength: 4)

            // Keep the text column clear of the overlaid pin while allowing
            // the outer Button to own the complete card hit area.
            Color.clear
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86, alignment: .top)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var noteText: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(note.title.isEmpty ? language.strings.noTitle : note.title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            Text(note.preview(for: language.current))
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .foregroundStyle(muted)
                .lineLimit(2)

            HStack(spacing: 7) {
                Text(note.tag.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(note.tint.color)
                Text("·")
                    .foregroundStyle(muted.opacity(0.64))
                Text(note.relativeDate(for: language.current))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(muted.opacity(0.82))
            }
        }
    }

    private var pinButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                onTogglePinned()
            }
        } label: {
            Image(systemName: note.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(note.isPinned ? Color.nookPinYellow : ink.opacity(0.64))
                .rotationEffect(.degrees(note.isPinned ? -16 : -34))
                .scaleEffect(note.isPinned ? 1.08 : 1)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.28, dampingFraction: 0.68), value: note.isPinned)
        }
        .buttonStyle(.plain)
        .help(note.isPinned ? language.strings.unpin : language.strings.pin)
        .accessibilityLabel(note.isPinned ? language.strings.unpin : language.strings.pin)
    }

    private var rowBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(rowSurface)
            if isDragged || isDropTarget || isHovered {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isDragged ? 0.12 : (isDropTarget ? 0.08 : 0.045)))
            }
        }
    }

    private func hovered(_ hovering: Bool) {
        // Hover affordances are useful for opening notes, but they add a
        // state write for every pointer crossing while a reorder is in
        // progress. Keep the drag path dedicated to drop geometry.
        if !isReordering { onHover(hovering) }
    }
}

private enum NoteDropPlacement: Equatable {
    case before
    case after
}

private struct NoteDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?
    @Binding var dropPlacement: NoteDropPlacement?
    @Binding var lastReorderKey: String?
    let noteOrder: [NookNote]
    let onMove: (UUID, UUID, NoteDropPlacement) -> Void

    func dropEntered(info: DropInfo) {
        updateTarget()
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID {
            dropTargetID = nil
            dropPlacement = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        dropTargetID = nil
        dropPlacement = nil
        lastReorderKey = nil
        return true
    }

    private func updateTarget() {
        guard let draggedID,
              let movingIndex = noteOrder.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = noteOrder.firstIndex(where: { $0.id == targetID }),
              noteOrder[movingIndex].isPinned == noteOrder[targetIndex].isPinned,
              draggedID != targetID else {
            dropTargetID = nil
            dropPlacement = nil
            return
        }

        // Crossing any part of the next card is enough to reorder. A downward
        // drag inserts after the card entered; an upward drag inserts before
        // it, so the source no longer has to travel to the following card's
        // bottom before the list responds.
        let placement: NoteDropPlacement = movingIndex < targetIndex ? .after : .before
        guard dropTargetID != targetID || dropPlacement != placement else { return }
        let moveKey = "\(draggedID.uuidString)|\(targetID.uuidString)|\(placement)"
        guard lastReorderKey != moveKey else { return }
        lastReorderKey = moveKey
        dropTargetID = targetID
        dropPlacement = placement
        onMove(draggedID, targetID, placement)
    }
}

private struct EmptyCardState: View {
    let searchText: String
    let isDark: Bool
    let onCreate: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 24)
            Image(systemName: searchText.isEmpty ? "square.and.pencil" : "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 48, height: 48)
                .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), in: Circle())
            Text(searchText.isEmpty ? language.strings.leaveFirstNote : language.strings.noMatches)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
            Text(searchText.isEmpty ? language.strings.emptyHint : language.strings.noMatchesHint)
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 235)
            if searchText.isEmpty {
                Button(language.strings.newNote, action: onCreate)
                    .buttonStyle(NookCardButtonStyle(isDark: isDark))
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct NoteEditorCard: View {
    let note: NookNote
    @ObservedObject var tagStore: TagStore
    let isDark: Bool
    let onBack: () -> Void
    let onTogglePinned: () -> Void
    let onDelete: () -> Void
    let onSave: (String, String, Data?, String, NookNote.Tint) -> Void

    @EnvironmentObject private var language: NookLanguageStore
    @StateObject private var editorBridge = NookEditorBridge()
    @State private var titleText: String
    @State private var bodyText: String
    @State private var bodyRTF: Data?
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var selectedTag: String
    @State private var selectedTint: NookNote.Tint

    private struct EditorDocument {
        let title: String
        let body: String
        let richData: Data?
    }

    init(
        note: NookNote,
        tagStore: TagStore,
        isDark: Bool,
        onBack: @escaping () -> Void,
        onTogglePinned: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSave: @escaping (String, String, Data?, String, NookNote.Tint) -> Void
    ) {
        self.note = note
        self.tagStore = tagStore
        self.isDark = isDark
        self.onBack = onBack
        self.onTogglePinned = onTogglePinned
        self.onDelete = onDelete
        self.onSave = onSave
        let document = Self.editorDocument(for: note)
        _titleText = State(initialValue: document.title)
        _bodyText = State(initialValue: document.body)
        _bodyRTF = State(initialValue: document.richData)
        _selectedTag = State(initialValue: note.tag)
        _selectedTint = State(initialValue: note.tint)
    }

    var body: some View {
        NoteEditorSurface(
            note: note,
            tagStore: tagStore,
            isDark: isDark,
            onBack: onBack,
            onTogglePinned: onTogglePinned,
            onDelete: onDelete,
            editorBridge: editorBridge,
            titleText: $titleText,
            bodyText: $bodyText,
            bodyRTF: $bodyRTF,
            selection: $selection,
            selectedTag: $selectedTag,
            selectedTint: $selectedTint
        )
        .onChange(of: titleText) { _ in saveDraft() }
        .onChange(of: bodyText) { _ in saveDraft() }
        .onChange(of: bodyRTF) { _ in saveDraft() }
        .onChange(of: selectedTag) { _ in saveDraft() }
        .onChange(of: selectedTint) { _ in saveDraft() }
        .onExitCommand(perform: onBack)
    }

    private func saveDraft() {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty
            ? (note.title.isEmpty || Self.isDefaultTitle(note.title) ? language.strings.newNote : note.title)
            : trimmedTitle
        onSave(title, bodyText, bodyRTF, selectedTag, selectedTint)
    }

    private static func editorDocument(for note: NookNote) -> EditorDocument {
        var title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = note.body.replacingOccurrences(of: "\r\n", with: "\n")

        if title.isEmpty || isDefaultTitle(title) {
            // A legacy default title means the first non-empty paragraph was
            // the user's real title. Preserve a leading empty paragraph,
            // though: it is how a newly inserted table reserves its title
            // slot without turning the first cell into the heading.
            let split = splitFirstParagraph(body)
            if split.title.isEmpty == false {
                title = split.title
                body = split.body
            } else {
                title = ""
            }
        } else if body.hasPrefix("\(title)\n") {
            // Older composite-document builds could duplicate the title in
            // the stored body. Strip only that exact leading paragraph.
            body.removeFirst(title.count + 1)
        }

        return EditorDocument(
            title: title,
            body: body,
            richData: editorRichData(for: note, title: title, body: body)
        )
    }

    private static func splitFirstParagraph(_ text: String) -> (title: String, body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard let newline = normalized.firstIndex(of: "\n") else {
            return (normalized.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }

        let title = normalized[..<newline].trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyStart = normalized.index(after: newline)
        return (String(title), String(normalized[bodyStart...]))
    }

    private static func isDefaultTitle(_ title: String) -> Bool {
        title.caseInsensitiveCompare("Yeni not") == .orderedSame
            || title.caseInsensitiveCompare("New note") == .orderedSame
    }

    private static func editorRichData(for note: NookNote, title: String, body: String) -> Data? {
        guard let savedData = note.bodyRTF,
              let saved = try? NSAttributedString(
                  data: savedData,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              ) else { return nil }

        if saved.string == body {
            return savedData
        }

        // Older builds persisted the title and body as one RTF stream, while
        // the model has always stored the body separately. Extract the body
        // paragraphs without discarding table blocks or attachments.
        let candidates = [
            "\(title)\n\(body)",
            "\(note.title)\n\(note.body)",
            "\n\(body)"
        ]
        guard candidates.contains(saved.string) else { return nil }
        let newlineRange = (saved.string as NSString).range(of: "\n")
        guard newlineRange.location != NSNotFound else { return nil }

        let bodyStart = newlineRange.location + newlineRange.length
        guard bodyStart < saved.length else { return nil }
        let bodyRange = NSRange(location: bodyStart, length: saved.length - bodyStart)
        let bodyAttributed = saved.attributedSubstring(from: bodyRange)
        guard bodyAttributed.string == body else { return nil }
        return try? bodyAttributed.data(
            from: NSRange(location: 0, length: bodyAttributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}

private struct NoteEditorSurface: View {
    let note: NookNote
    @ObservedObject var tagStore: TagStore
    let isDark: Bool
    let onBack: () -> Void
    let onTogglePinned: () -> Void
    let onDelete: () -> Void
    @ObservedObject var editorBridge: NookEditorBridge

    @Binding var titleText: String
    @Binding var bodyText: String
    @Binding var bodyRTF: Data?
    @Binding var selection: NSRange
    @Binding var selectedTag: String
    @Binding var selectedTint: NookNote.Tint

    @EnvironmentObject private var language: NookLanguageStore
    @State private var isTagPickerPresented = false
    @State private var isFormattingPopoverPresented = false
    @State private var isListPopoverPresented = false
    @State private var isAttachmentPopoverPresented = false
    @FocusState private var isTitleFocused: Bool

    private var surface: Color { isDark ? .nookCardDark : .nookCardLightSurface }
    private var editorSurface: Color {
        isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }
    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }
    private var hasSelection: Bool { selection.length > 0 }
    private var editorTileShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 20,
                bottomLeading: 28,
                bottomTrailing: 28,
                topTrailing: 20
            ),
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NookLayout.itemGap) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 30, height: 30)
                        .background(isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .help(language.strings.backToNotes)
                .accessibilityLabel(language.strings.backToNotes)

                Spacer()

                Button {
                    isTitleFocused = false
                    editorBridge.resignFocus()
                    isFormattingPopoverPresented = false
                    isListPopoverPresented = false
                    isAttachmentPopoverPresented = false
                    isTagPickerPresented.toggle()
                } label: {
                    HStack(spacing: NookLayout.itemGap) {
                        Circle()
                            .fill(selectedTint.color)
                            .frame(width: 7, height: 7)
                        Text(selectedTag.isEmpty ? language.strings.chooseTag : selectedTag)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(editorSurface, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(language.strings.chooseTag)
                .accessibilityLabel("\(language.strings.tagLabel): \(selectedTag)")

                Button(action: onTogglePinned) {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(note.isPinned ? Color.nookPinYellow : muted)
                        .frame(width: 30, height: 30)
                        .background(editorSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .help(note.isPinned ? language.strings.unpin : language.strings.pin)
                .accessibilityLabel(note.isPinned ? language.strings.unpin : language.strings.pin)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(muted)
                        .frame(width: 30, height: 30)
                        .background(editorSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .help(language.strings.deleteNote)
                .accessibilityLabel(language.strings.deleteNote)
            }
            .padding(.horizontal, NookLayout.nestedControlInset)
            .padding(.top, NookLayout.nestedControlInset)
            .padding(.bottom, NookLayout.contentInset)

            NookFormattingToolbar(
                isDark: isDark,
                hasSelection: hasSelection,
                bridge: editorBridge,
                isPresented: $isFormattingPopoverPresented,
                isListPresented: $isListPopoverPresented,
                isAttachmentPresented: $isAttachmentPopoverPresented,
                onInsertTable: {
                    isFormattingPopoverPresented = false
                    isListPopoverPresented = false
                    isAttachmentPopoverPresented = false
                    editorBridge.insertTable()
                },
                onInsertPhoto: {
                    isFormattingPopoverPresented = false
                    isListPopoverPresented = false
                    isAttachmentPopoverPresented = false
                    editorBridge.insertPhotoOrVideo()
                },
                onInsertFile: {
                    isFormattingPopoverPresented = false
                    isListPopoverPresented = false
                    isAttachmentPopoverPresented = false
                    editorBridge.insertFileAttachment()
                }
            )
                // Align the toolbar capsule with the back button and title;
                // the editor content below keeps its existing inset.
                .padding(.horizontal, NookLayout.nestedControlInset)
                .padding(.bottom, NookLayout.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The menu must sit above the AppKit text view as well as the
                // rest of the editor surface. A list or attachment menu is
                // just as modal visually as the Aa menu.
                .zIndex((isFormattingPopoverPresented || isListPopoverPresented || isAttachmentPopoverPresented) ? 4 : 0)

            VStack(spacing: 0) {
                // The title has its own reserved paragraph. It shares the
                // writing surface visually, but its height is independent of
                // the body so tables and attachments can never consume it.
                ZStack(alignment: .topLeading) {
                    TextField("", text: $titleText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1...4)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($isTitleFocused)
                        .accessibilityLabel(language.strings.noteTitle)

                    if titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(language.strings.bodyPlaceholder)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(muted.opacity(0.75))
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, NookLayout.editorTextInset)
                .padding(.top, NookLayout.editorTextVerticalInset)
                .padding(.bottom, NookLayout.titleBodyGap)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)

                ZStack(alignment: .topLeading) {
                    NookRichTextEditor(
                        text: $bodyText,
                        richData: $bodyRTF,
                        selection: $selection,
                        isDark: isDark,
                        placeholder: language.strings.bodyPlaceholder,
                        startsWithTitle: false,
                        bridge: editorBridge
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(language.strings.noteBody)

                    if bodyText.isEmpty && titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text(language.strings.bodyPlaceholder)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(muted.opacity(0.72))
                            .padding(.horizontal, NookLayout.editorTextInset)
                            .padding(.top, NookLayout.editorTextVerticalInset)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(editorSurface, in: editorTileShape)
            .clipShape(editorTileShape)
            // Let the writing canvas meet the inner surface on three edges.
            // Its lower corners inherit the parent radius so the flush edge
            // remains a deliberate nested shape instead of a square cutoff.
            .padding(.top, NookLayout.itemGap)

        }
        .background(surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.top, 8)
        .overlay(alignment: .topTrailing) {
            if isTagPickerPresented {
                TagPickerPopover(
                    tagStore: tagStore,
                    selectedTag: $selectedTag,
                    selectedTint: $selectedTint,
                    isDark: isDark,
                    onSelect: { isTagPickerPresented = false }
                )
                .environmentObject(language)
                .padding(.top, 58)
                .padding(.trailing, 16)
                .zIndex(5)
            }
        }
        .onAppear {
            tagStore.create(name: selectedTag, tint: selectedTint)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isTitleFocused = true
                } else {
                    editorBridge.focus()
                }
            }
        }
    }
}

@MainActor
private final class NookEditorBridge: ObservableObject {
    weak var textView: NSTextView?
    var onRichTextChange: (() -> Void)?

    func attach(_ textView: NSTextView) {
        self.textView = textView
    }

    func focus() {
        textView?.window?.makeFirstResponder(textView)
    }

    func resignFocus() {
        textView?.window?.makeFirstResponder(nil)
    }

    func apply(_ style: NookTextStyle) {
        guard let textView, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()

        switch style {
        case .bold, .italic, .strikethrough, .code:
            guard selection.length > 0 else { return }
            applyInline(style, to: selection, in: textView, storage: storage)

        case .title, .heading, .subheading, .body, .monospaced, .bulleted, .dashed, .numbered, .blockquote:
            let paragraphRange = paragraphRange(for: selection, in: textView)
            guard paragraphRange.length > 0 else { return }
            applyBlock(style, to: paragraphRange, in: textView, storage: storage)
        }

        textView.undoManager?.setActionName(style.actionName)
        onRichTextChange?()
    }

    /// Inserts a real TextKit table into the document. Each cell is its own
    /// paragraph carrying an NSTextTableBlock, so borders are drawn by
    /// AppKit rather than being made from box-drawing characters. The table
    /// therefore keeps its geometry when a cell grows and every cell remains
    /// a normal editable text range.
    func insertTable(rows: Int = 3, columns: Int = 2) {
        guard let textView, let storage = textView.textStorage else { return }

        let range = textView.selectedRange()
        let string = storage.string as NSString
        let rangeEnd = range.location + range.length
        let needsLeadingBreak = range.location > 0 && string.character(at: range.location - 1) != 10
        let needsTrailingBreak = rangeEnd < string.length && string.character(at: rangeEnd) != 10
        let attributed = makeTable(
            rows: rows,
            columns: columns,
            textColor: textView.textColor ?? NSColor.textColor
        )

        if needsLeadingBreak {
            attributed.insert(NSAttributedString(string: "\n"), at: 0)
        }
        if needsTrailingBreak {
            attributed.append(NSAttributedString(string: "\n", attributes: NookTextView.bodyTypingAttributes(for: textView.textColor)))
        }

        storage.replaceCharacters(in: range, with: attributed)
        let firstCellLocation = range.location + (needsLeadingBreak ? 1 : 0)
        textView.setSelectedRange(NSRange(location: firstCellLocation, length: 0))
        textView.didChangeText()
        focus()
        onRichTextChange?()
    }

    /// Opens the photo/video picker. Images are rendered directly in the
    /// writing stream; videos use the file attachment representation.
    func insertPhotoOrVideo() {
        chooseAttachment(allowedContentTypes: [.image, .movie], inlineImages: true)
    }

    /// Opens the general file picker. Even image files selected here remain a
    /// file attachment, keeping the paperclip action distinct from Photos.
    func insertFileAttachment() {
        chooseAttachment(allowedContentTypes: [.data], inlineImages: false)
    }

    private func chooseAttachment(allowedContentTypes: [UTType], inlineImages: Bool) {
        guard textView != nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedContentTypes
        panel.begin { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            self?.insertFile(url, inlineImage: inlineImages)
        }
    }

    private func insertFile(_ url: URL, inlineImage: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let attachment = NSTextAttachment()

        if inlineImage, let image = NSImage(contentsOf: url) {
            attachment.image = Self.scaledImage(image, maxWidth: 320)
        } else if let wrapper = try? FileWrapper(url: url, options: .immediate) {
            attachment.fileWrapper = wrapper
        } else {
            let range = textView.selectedRange()
            let link = NSAttributedString(
                string: url.lastPathComponent,
                attributes: [.link: url, .underlineStyle: NSUnderlineStyle.single.rawValue]
            )
            storage.replaceCharacters(in: range, with: link)
            textView.setSelectedRange(NSRange(location: range.location + link.length, length: 0))
            textView.didChangeText()
            focus()
            onRichTextChange?()
            return
        }

        let inserted = NSAttributedString(attachment: attachment)
        let range = textView.selectedRange()
        storage.replaceCharacters(in: range, with: inserted)
        textView.setSelectedRange(NSRange(location: range.location + inserted.length, length: 0))
        textView.didChangeText()
        focus()
        onRichTextChange?()
    }

    private func applyInline(
        _ style: NookTextStyle,
        to range: NSRange,
        in textView: NSTextView,
        storage: NSTextStorage
    ) {
        storage.beginEditing()
        switch style {
        case .bold, .italic:
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: 14)
            let trait: NSFontDescriptor.SymbolicTraits = style == .bold ? .bold : .italic
            let currentTraits = font.fontDescriptor.symbolicTraits
            let nextTraits = currentTraits.contains(trait)
                ? currentTraits.subtracting(trait)
                : currentTraits.union(trait)
            let descriptor = font.fontDescriptor.withSymbolicTraits(nextTraits)
            if let nextFont = NSFont(descriptor: descriptor, size: font.pointSize) {
                storage.addAttribute(.font, value: nextFont, range: range)
            }
        case .strikethrough:
            let current = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? NSNumber
            if current?.intValue == NSUnderlineStyle.single.rawValue {
                storage.removeAttribute(.strikethroughStyle, range: range)
            } else {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        case .code:
            let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.addAttribute(.font, value: codeFont, range: range)
            storage.addAttribute(.backgroundColor, value: NSColor.black.withAlphaComponent(0.12), range: range)
        default:
            break
        }
        storage.endEditing()
        textView.setSelectedRange(range)
    }

    private func applyBlock(
        _ style: NookTextStyle,
        to range: NSRange,
        in textView: NSTextView,
        storage: NSTextStorage
    ) {
        let string = textView.string as NSString
        let selected = string.substring(with: range)
        let transformed: String

        switch style {
        case .bulleted:
            transformed = prefixedLines(selected, prefix: "• ")
        case .dashed:
            transformed = prefixedLines(selected, prefix: "– ")
        case .numbered:
            transformed = selected
                .components(separatedBy: .newlines)
                .enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
        case .blockquote:
            transformed = prefixedLines(selected, prefix: "│ ")
        default:
            transformed = selected
        }

        storage.beginEditing()
        if transformed != selected {
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            storage.replaceCharacters(in: range, with: NSAttributedString(string: transformed, attributes: attributes))
        }

        let updatedRange = NSRange(location: range.location, length: (transformed as NSString).length)
        let font: NSFont
        switch style {
        case .title: font = NSFont.systemFont(ofSize: 26, weight: .bold)
        case .heading: font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        case .subheading: font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        case .monospaced: font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        default: font = NSFont.systemFont(ofSize: 14, weight: .regular)
        }
        storage.addAttribute(.font, value: font, range: updatedRange)

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = style == .title ? NookLayout.titleBodyGap : 0
        storage.addAttribute(.paragraphStyle, value: paragraph, range: updatedRange)

        if style == .blockquote {
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = 14
            paragraph.paragraphSpacing = 4
            storage.addAttribute(.paragraphStyle, value: paragraph, range: updatedRange)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: updatedRange)
        }
        storage.endEditing()
        textView.setSelectedRange(updatedRange)
    }

    private func paragraphRange(for selection: NSRange, in textView: NSTextView) -> NSRange {
        let string = textView.string as NSString
        guard string.length > 0 else { return NSRange(location: 0, length: 0) }
        let location = min(selection.location, string.length - 1)
        let length = min(max(selection.length, 1), string.length - location)
        return string.paragraphRange(for: NSRange(location: location, length: length))
    }

    private func prefixedLines(_ text: String, prefix: String) -> String {
        text.components(separatedBy: .newlines)
            .map { line in line.hasPrefix(prefix) ? line : prefix + line }
            .joined(separator: "\n")
    }

    private func makeTable(rows: Int, columns: Int, textColor: NSColor) -> NSMutableAttributedString {
        let rowCount = max(rows, 1)
        let columnCount = max(columns, 1)
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = NSTextTable.LayoutAlgorithm(rawValue: 1)!
        table.collapsesBorders = false
        table.hidesEmptyCells = false

        let borderColor = textColor.withAlphaComponent(0.28)
        let result = NSMutableAttributedString()

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: row,
                    rowSpan: 1,
                    startingColumn: column,
                    columnSpan: 1
                )
                // Fixed layout plus a percentage width gives every column the
                // same track while leaving TextKit free to grow a row's
                // height when its text wraps.
                block.setContentWidth(
                    100 / CGFloat(columnCount),
                    type: NSTextBlock.ValueType(rawValue: 1)!
                )
                block.setWidth(
                    1,
                    type: NSTextBlock.ValueType(rawValue: 0)!,
                    for: NSTextBlock.Layer(rawValue: 0)!
                )
                block.setWidth(
                    8,
                    type: NSTextBlock.ValueType(rawValue: 0)!,
                    for: NSTextBlock.Layer(rawValue: -1)!
                )
                block.setBorderColor(borderColor)
                block.verticalAlignment = NSTextBlock.VerticalAlignment(rawValue: 0)!

                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacing = 0
                paragraph.textBlocks = [block]
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph
                ]
                // Keep a real editable character in an empty cell. The
                // paragraph terminator remains the cell boundary; this space
                // simply makes the insertion point easy to place with a
                // mouse before the user starts typing.
                result.append(NSAttributedString(string: " \n", attributes: attributes))
            }
        }

        // A plain paragraph after the table gives the user an escape route
        // for continuing to type below it without creating another cell.
        result.append(NSAttributedString(
            string: "\n",
            attributes: NookTextView.bodyTypingAttributes(for: textColor)
        ))
        return result
    }

    private static func scaledImage(_ image: NSImage, maxWidth: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxWidth, size.width > 0 else { return image }
        let scale = maxWidth / size.width
        let scaled = NSImage(size: NSSize(width: maxWidth, height: size.height * scale))
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaled.size), from: .zero, operation: .sourceOver, fraction: 1)
        scaled.unlockFocus()
        return scaled
    }
}

private enum NookTextStyle {
    case bold
    case italic
    case strikethrough
    case code
    case title
    case heading
    case subheading
    case body
    case monospaced
    case bulleted
    case dashed
    case numbered
    case blockquote

    var actionName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .code: return "Code"
        case .title: return "Title"
        case .heading: return "Heading"
        case .subheading: return "Subheading"
        case .body: return "Body"
        case .monospaced: return "Monospaced"
        case .bulleted: return "Bulleted List"
        case .dashed: return "Dashed List"
        case .numbered: return "Numbered List"
        case .blockquote: return "Block Quote"
        }
    }
}

private struct NookRichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richData: Data?
    @Binding var selection: NSRange
    let isDark: Bool
    let placeholder: String
    let startsWithTitle: Bool
    let bridge: NookEditorBridge

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none

        let textView = NookTextView()
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = isDark ? .textColor : NookPalette.cardInkNS
        textView.insertionPointColor = isDark ? NSColor.white : NSColor.black
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(calibratedRed: 0.99, green: 0.72, blue: 0.16, alpha: 0.75),
            .foregroundColor: isDark ? NSColor.black : NookPalette.cardInkNS
        ]
        textView.textContainerInset = NSSize(
            width: NookLayout.editorTextInset,
            height: NookLayout.editorTextVerticalInset
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.startsWithTitle = startsWithTitle
        // Let AppKit accept image data from the pasteboard. NookTextView also
        // normalizes image pastes into NSTextAttachment so they share the same
        // RTF persistence path as files picked from the attachment button.
        textView.importsGraphics = true
        textView.usesFontPanel = false
        textView.string = text
        var restoredRichText = false
        if let richData,
           let attributed = try? NSAttributedString(
               data: richData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ),
           attributed.string == text {
            textView.textStorage?.setAttributedString(attributed)
            restoredRichText = true
        }
        if !restoredRichText {
            if startsWithTitle {
                textView.applyDefaultDocumentStyle()
            } else {
                textView.applyDefaultBodyDocumentStyle()
            }
        }
        textView.updateTypingAttributesForCurrentPosition()

        bridge.attach(textView)
        context.coordinator.textView = textView
        bridge.onRichTextChange = { [weak coordinator = context.coordinator] in
            coordinator?.syncFromTextView()
        }
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NookTextView else { return }
        bridge.attach(textView)
        textView.textColor = isDark ? .textColor : NookPalette.cardInkNS
        textView.insertionPointColor = isDark ? NSColor.white : NSColor.black
        if textView.string != text {
            let previousSelection = textView.selectedRange()
            textView.string = text
            if richData == nil {
                if startsWithTitle {
                    textView.applyDefaultDocumentStyle()
                } else {
                    textView.applyDefaultBodyDocumentStyle()
                }
            }
            let location = min(previousSelection.location, textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NookRichTextEditor
        weak var textView: NookTextView?

        init(_ parent: NookRichTextEditor) {
            self.parent = parent
        }

        func syncFromTextView() {
            guard let textView else { return }
            parent.text = textView.string
            parent.selection = textView.selectedRange()
            parent.richData = Self.makeRichData(from: textView)
        }

        func textDidChange(_ notification: Notification) {
            textView?.updateTypingAttributesForCurrentPosition()
            syncFromTextView()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.selection = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            textView?.updateTypingAttributesForCurrentPosition()
        }

        private static func makeRichData(from textView: NSTextView) -> Data? {
            let length = textView.textStorage?.length ?? 0
            guard length > 0 else { return nil }
            return try? textView.attributedString().data(
                from: NSRange(location: 0, length: length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }
    }
}

private final class NookTextView: NSTextView {
    private static let titleFont = NSFont.systemFont(ofSize: 25, weight: .bold)
    private static let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    var startsWithTitle = true

    override var acceptsFirstResponder: Bool { true }

    /// A blank document starts in title typography. Once the first paragraph
    /// exists, its following paragraphs use the normal body size. This is
    /// deliberately applied only when opening plain/legacy content so an
    /// existing rich document keeps the user's explicit styles.
    func applyDefaultDocumentStyle() {
        guard let storage = textStorage else {
            typingAttributes = titleTypingAttributes()
            return
        }

        guard storage.length > 0 else {
            typingAttributes = titleTypingAttributes()
            return
        }

        let firstParagraph = (string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        storage.beginEditing()
        storage.addAttribute(.font, value: Self.titleFont, range: firstParagraph)
        storage.addAttribute(.paragraphStyle, value: Self.titleParagraphStyle(), range: firstParagraph)

        let bodyStart = firstParagraph.location + firstParagraph.length
        if bodyStart < storage.length {
            storage.addAttribute(
                .font,
                value: Self.bodyFont,
                range: NSRange(location: bodyStart, length: storage.length - bodyStart)
            )
            storage.addAttribute(
                .paragraphStyle,
                value: Self.bodyParagraphStyle(),
                range: NSRange(location: bodyStart, length: storage.length - bodyStart)
            )
        }
        storage.endEditing()
    }

    func applyDefaultBodyDocumentStyle() {
        guard let storage = textStorage else {
            typingAttributes = bodyTypingAttributes()
            return
        }

        guard storage.length > 0 else {
            typingAttributes = bodyTypingAttributes()
            return
        }

        storage.beginEditing()
        storage.addAttribute(.font, value: Self.bodyFont, range: NSRange(location: 0, length: storage.length))
        storage.addAttribute(.paragraphStyle, value: Self.bodyParagraphStyle(), range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        typingAttributes = bodyTypingAttributes()
    }

    func updateTypingAttributesForCurrentPosition() {
        guard let storage = textStorage, storage.length > 0 else {
            typingAttributes = startsWithTitle ? titleTypingAttributes() : bodyTypingAttributes()
            return
        }

        let location = min(max(selectedRange().location, 0), storage.length - 1)
        typingAttributes = storage.attributes(at: location, effectiveRange: nil)
    }

    override func insertNewline(_ sender: Any?) {
        let currentTypingAttributes = typingAttributes
        let isInsideTable = (currentTypingAttributes[.paragraphStyle] as? NSParagraphStyle)?
            .textBlocks
            .contains(where: { $0 is NSTextTableBlock }) == true
        super.insertNewline(sender)
        if isInsideTable {
            // A return inside a cell creates another paragraph in that same
            // table block. Keep its block metadata so the new line remains
            // inside the cell instead of escaping into the document body.
            typingAttributes = currentTypingAttributes
        } else {
            // AppKit carries the current title attributes across a newline.
            // The next normal paragraph is the body, so switch typing
            // attributes immediately after the insertion.
            typingAttributes = bodyTypingAttributes()
        }
    }

    override func paste(_ sender: Any?) {
        if let image = NSImage(pasteboard: NSPasteboard.general) {
            let attachment = NSTextAttachment()
            attachment.image = Self.scaledImage(image, maxWidth: 320)
            let inserted = NSAttributedString(attachment: attachment)
            let range = selectedRange()
            textStorage?.replaceCharacters(in: range, with: inserted)
            setSelectedRange(NSRange(location: range.location + inserted.length, length: 0))
            didChangeText()
            return
        }
        super.paste(sender)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        drawsBackground = false
        enclosingScrollView?.drawsBackground = false
    }

    private func titleTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: Self.titleFont,
            .foregroundColor: textColor ?? NSColor.textColor,
            .paragraphStyle: Self.titleParagraphStyle()
        ]
    }

    private func bodyTypingAttributes() -> [NSAttributedString.Key: Any] {
        Self.bodyTypingAttributes(for: textColor)
    }

    static func bodyTypingAttributes(for textColor: NSColor?) -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: textColor ?? NSColor.textColor,
            .paragraphStyle: bodyParagraphStyle()
        ]
    }

    static func titleParagraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = NookLayout.titleBodyGap
        return paragraph
    }

    private static func bodyParagraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 0
        return paragraph
    }

    private static func scaledImage(_ image: NSImage, maxWidth: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxWidth, size.width > 0 else { return image }
        let scale = maxWidth / size.width
        let scaled = NSImage(size: NSSize(width: maxWidth, height: size.height * scale))
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaled.size), from: .zero, operation: .sourceOver, fraction: 1)
        scaled.unlockFocus()
        return scaled
    }
}

private struct NookFormattingToolbar: View {
    let isDark: Bool
    let hasSelection: Bool
    let bridge: NookEditorBridge
    @Binding var isPresented: Bool
    @Binding var isListPresented: Bool
    @Binding var isAttachmentPresented: Bool
    let onInsertTable: () -> Void
    let onInsertPhoto: () -> Void
    let onInsertFile: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var railSurface: Color { isDark ? Color.white.opacity(0.085) : Color.black.opacity(0.055) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 2) {
                NookFormatButton(
                    icon: "textformat",
                    label: language.strings.formatMenu,
                    ink: ink,
                    isEnabled: true,
                    isSelected: isPresented
                ) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isListPresented = false
                        isAttachmentPresented = false
                        isPresented.toggle()
                    }
                }
                NookFormatButton(
                    icon: "list.bullet",
                    label: language.strings.listMenu,
                    ink: ink,
                    isEnabled: true,
                    isSelected: isListPresented
                ) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isPresented = false
                        isAttachmentPresented = false
                        isListPresented.toggle()
                    }
                }
                NookFormatButton(
                    icon: "tablecells",
                    label: language.strings.insertTable,
                    ink: ink,
                    isEnabled: true
                ) {
                    isPresented = false
                    isListPresented = false
                    isAttachmentPresented = false
                    onInsertTable()
                }
                NookFormatButton(
                    icon: "paperclip",
                    label: language.strings.addAttachment,
                    ink: ink,
                    isEnabled: true
                ) {
                    isPresented = false
                    isListPresented = false
                    withAnimation(.easeOut(duration: 0.14)) { isAttachmentPresented.toggle() }
                }
            }
            .padding(4)
            .background(railSurface, in: Capsule())

            if isPresented {
                NookTextStylePopover(
                    isDark: isDark,
                    hasSelection: hasSelection,
                    bridge: bridge,
                    onDismiss: { isPresented = false }
                )
                .environmentObject(language)
                .offset(y: 48)
                .zIndex(2)
            }

            if isListPresented {
                NookListPopover(
                    isDark: isDark,
                    bridge: bridge,
                    onDismiss: { isListPresented = false }
                )
                .environmentObject(language)
                .offset(x: 34, y: 48)
                .zIndex(2)
            }

            if isAttachmentPresented {
                NookAttachmentPopover(
                    isDark: isDark,
                    onInsertPhoto: {
                        isAttachmentPresented = false
                        onInsertPhoto()
                    },
                    onInsertFile: {
                        isAttachmentPresented = false
                        onInsertFile()
                    }
                )
                .environmentObject(language)
                .offset(x: 74, y: 48)
                .zIndex(2)
            }
        }
        .frame(height: 42, alignment: .topLeading)
        .zIndex((isPresented || isListPresented || isAttachmentPresented) ? 2 : 0)
    }
}

private struct NookFormatButton: View {
    let icon: String
    let label: String
    let ink: Color
    let isEnabled: Bool
    var isSelected: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(ink)
                .frame(width: 34, height: 34)
                .background((isHovered || isSelected) ? Color.primary.opacity(0.1) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case "bold":
            Text("B")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        case "italic":
            Text("I")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .italic()
        case "textformat":
            Text("Aa")
                .font(.system(size: 14, weight: .medium, design: .rounded))
        case "tablecells":
            Image(systemName: "tablecells")
                .font(.system(size: 15, weight: .semibold))
        case "paperclip":
            Image(systemName: "paperclip")
                .font(.system(size: 15, weight: .semibold))
        case "list.bullet":
            Image(systemName: "list.bullet")
                .font(.system(size: 15, weight: .semibold))
        case "strikethrough":
            Image(systemName: "strikethrough")
                .font(.system(size: 15, weight: .semibold))
        default:
            Image(systemName: "curlybraces")
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

private struct NookTextStylePopover: View {
    let isDark: Bool
    let hasSelection: Bool
    let bridge: NookEditorBridge
    let onDismiss: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }
    private var background: Color {
        isDark ? Color(nsColor: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.135, alpha: 1)) : .nookCardLightRaised
    }
    private var controlSurface: Color { isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.055) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                NookFormatButton(icon: "bold", label: language.strings.formatBold, ink: ink, isEnabled: hasSelection) { bridge.apply(.bold) }
                NookFormatButton(icon: "italic", label: language.strings.formatItalic, ink: ink, isEnabled: hasSelection) { bridge.apply(.italic) }
                NookFormatButton(icon: "strikethrough", label: language.strings.formatStrike, ink: ink, isEnabled: hasSelection) { bridge.apply(.strikethrough) }
                NookFormatButton(icon: "curlybraces", label: language.strings.formatCode, ink: ink, isEnabled: hasSelection) { bridge.apply(.code) }
            }
            // Keep the inline controls as individual circular buttons. The
            // style popover itself is already the grouping surface; a second
            // capsule here made the menu look like a nested control rail.
            .padding(.horizontal, 2)
            .padding(.vertical, 2)

            styleButton(language.strings.formatTitle, style: .title, font: .system(size: 18, weight: .bold, design: .rounded))
            styleButton(language.strings.formatHeading, style: .heading, font: .system(size: 15, weight: .semibold, design: .rounded))
            styleButton(language.strings.formatSubheading, style: .subheading, font: .system(size: 13, weight: .semibold, design: .rounded))
            styleButton(language.strings.formatBody, style: .body, font: .system(size: 12, weight: .regular, design: .rounded))
            styleButton(language.strings.formatMonospaced, style: .monospaced, font: .system(size: 12, weight: .regular, design: .monospaced))

            Divider()
                .overlay(muted.opacity(0.22))
                .padding(.vertical, 3)

            styleButton(language.strings.formatBulletedList, style: .bulleted, font: .system(size: 12, weight: .medium, design: .rounded))
            styleButton(language.strings.formatDashedList, style: .dashed, font: .system(size: 12, weight: .medium, design: .rounded))
            styleButton(language.strings.formatNumberedList, style: .numbered, font: .system(size: 12, weight: .medium, design: .rounded))

            Divider()
                .overlay(muted.opacity(0.22))
                .padding(.vertical, 3)

            styleButton(language.strings.formatBlockQuote, style: .blockquote, font: .system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(8)
        .frame(width: 192)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isDark ? 0.3 : 0.16), radius: 16, y: 7)
    }

    private func styleButton(_ title: String, style: NookTextStyle, font: Font) -> some View {
        Button {
            bridge.apply(style)
            onDismiss()
        } label: {
            Text(title)
                .font(font)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.horizontal, 10)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(controlSurface.opacity(0), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(title)
    }
}

private struct NookListPopover: View {
    let isDark: Bool
    let bridge: NookEditorBridge
    let onDismiss: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var background: Color {
        isDark ? Color(nsColor: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.135, alpha: 1)) : .nookCardLightRaised
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            listButton(language.strings.formatBulletedList, marker: "•", style: .bulleted)
            listButton(language.strings.formatDashedList, marker: "–", style: .dashed)
            listButton(language.strings.formatNumberedList, marker: "1.", style: .numbered)
        }
        .padding(6)
        .frame(width: 178)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(isDark ? 0.3 : 0.16), radius: 16, y: 7)
    }

    private func listButton(_ title: String, marker: String, style: NookTextStyle) -> some View {
        Button {
            bridge.apply(style)
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Text(marker)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct NookAttachmentPopover: View {
    let isDark: Bool
    let onInsertPhoto: () -> Void
    let onInsertFile: () -> Void

    @EnvironmentObject private var language: NookLanguageStore

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }
    private var background: Color {
        isDark ? Color(nsColor: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.135, alpha: 1)) : .nookCardLightRaised
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            attachmentButton(
                icon: "photo.on.rectangle",
                title: language.strings.choosePhotoOrVideo,
                action: onInsertPhoto
            )
            attachmentButton(
                icon: "doc",
                title: language.strings.attachFile,
                action: onInsertFile
            )
        }
        .padding(6)
        .frame(width: 208)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(isDark ? 0.3 : 0.16), radius: 16, y: 7)
    }

    private func attachmentButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(muted)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TagPickerPopover: View {
    @ObservedObject var tagStore: TagStore
    @Binding var selectedTag: String
    @Binding var selectedTint: NookNote.Tint
    let isDark: Bool
    let onSelect: () -> Void

    @EnvironmentObject private var language: NookLanguageStore
    @State private var isCreating = false
    @State private var newTagName = ""
    @State private var newTint: NookNote.Tint = .amber
    @FocusState private var tagNameFocused: Bool

    private var ink: Color { isDark ? .nookCardLightInk : .nookCardInk }
    private var muted: Color { isDark ? .nookCardLightMuted : .nookCardMuted }
    private var panel: Color { isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045) }
    private var background: Color {
        if isDark {
            return Color(nsColor: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.125, alpha: 1))
        }
        return .nookCardLightRaised
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookLayout.itemGap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.strings.chooseTag)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(language.strings.existingTags)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(muted)
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isCreating.toggle() }
                } label: {
                    Image(systemName: isCreating ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 28, height: 28)
                        .background(panel, in: Circle())
                }
                .buttonStyle(.plain)
                .help(language.strings.manageTags)
                .accessibilityLabel(language.strings.manageTags)
            }

            if isCreating {
                VStack(alignment: .leading, spacing: NookLayout.itemGap) {
                    TextField(language.strings.tagNamePlaceholder, text: $newTagName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .focused($tagNameFocused)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: NookLayout.itemGap) {
                        Text(language.strings.chooseColor)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(muted)
                        Spacer()
                        ForEach(NookNote.Tint.allCases, id: \.rawValue) { tint in
                            Button {
                                newTint = tint
                            } label: {
                                Circle()
                                    .fill(tint.color)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        if newTint == tint {
                                            Circle().stroke(ink, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tint.accessibilityName)
                        }
                    }

                    Button {
                        if let created = tagStore.create(name: newTagName, tint: newTint) {
                            selectedTag = created.name
                            selectedTint = created.tint
                            newTagName = ""
                            isCreating = false
                            onSelect()
                        }
                    } label: {
                        Text(language.strings.addTag)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isDark ? Color.nookCardDark : Color.nookCardLightSurface)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background((isDark ? Color.nookCardLightInk : Color.nookCardInk).opacity(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.38 : 1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(NookLayout.contentInset)
                .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: NookLayout.itemGap) {
                    ForEach(tagStore.tags) { tag in
                        Button {
                            selectedTag = tag.name
                            selectedTint = tag.tint
                            onSelect()
                        } label: {
                            HStack(spacing: NookLayout.itemGap) {
                                Circle().fill(tag.tint.color).frame(width: 8, height: 8)
                                Text(tag.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(ink)
                                Spacer()
                                if selectedTag.caseInsensitiveCompare(tag.name) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(tag.tint.color)
                                }
                            }
                            .padding(.horizontal, NookLayout.contentInset)
                            .frame(height: 30)
                            .background(selectedTag.caseInsensitiveCompare(tag.name) == .orderedSame ? panel : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Color.clear
                        .frame(height: NookLayout.contentInset)
                }
            }
            .frame(maxHeight: 190)
        }
        .padding(NookLayout.contentInset)
        .frame(width: 260)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(isDark ? 0.26 : 0.14), radius: 16, y: 7)
        .foregroundStyle(ink)
        .onChange(of: isCreating) { creating in
            if creating {
                DispatchQueue.main.async { tagNameFocused = true }
            } else {
                tagNameFocused = false
            }
        }
        .onAppear {
            if isCreating {
                DispatchQueue.main.async { tagNameFocused = true }
            }
        }
    }
}

private struct NookCardButtonStyle: ButtonStyle {
    let isDark: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isDark ? Color.nookCardDark : Color.nookCardLightSurface)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background((isDark ? Color.nookCardLightInk : Color.nookCardInk).opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
