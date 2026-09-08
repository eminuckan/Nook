import AppKit
import SwiftUI

/*
 DESIGN CONTRACT · Nook · seed nook-20260907 · user-pinned card direction
 THESIS: a quick notes card that lives at the edge; it refuses the full-window notes dashboard and the extra panel box around it.
 OWN-WORLD: a neutral light-gray or charcoal outer shell, a nested neutral-gray or dark work surface, complete rounded-radius hierarchy, and small color marks for note state.
 STORY: the user clicks the menu-bar mark, sees a single card of recent fragments, and writes before deciding where to file them.
 FIRST VIEWPORT: a 420px right-edge card with a compact header, a settings entry point, three full-width filters, rounded note rows, and an upper “Yeni not / New note” action beside search.
 FORM: the supplied reminder/task card references, translated into a single edge card; the system appearance chooses the inner surface and shell polarity.
 FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md. Pinned state uses an animated yellow pushpin; the header dismisses with a compact minimize control.
*/

@main
struct NookApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = NookAppDelegate()
        application.delegate = delegate
        // A menu-bar app has no standalone SwiftUI window scene. Keep its
        // delegate alive for the full AppKit event loop.
        withExtendedLifetime(delegate) { application.run() }
    }
}

extension Notification.Name {
    static let nookOpenSettings = Notification.Name("NookOpenSettings")
}

/// A tiny view-backed status item lets Nook keep the normal left-click action
/// while giving secondary click its own, explicit menu. AppKit's stock button
/// menu is otherwise ambiguous because assigning a menu also changes the
/// primary click behavior.
private final class NookStatusItemView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var onPrimaryAction: (() -> Void)?
    var onContextMenu: ((NSView) -> Void)?

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 22) }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Nook")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Nook")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }

        let size = image.size
        let rect = NSRect(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
        // The custom status view draws its own template mask so the mark
        // follows the menu bar's effective appearance in both light and dark.
        let tinted = NSImage(size: size, flipped: isFlipped) { bounds in
            image.draw(in: bounds)
            NSColor.labelColor.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: isFlipped,
            hints: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onPrimaryAction?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(self)
    }
}

private enum NookLogoAsset {
    static func image(size: NSSize) -> NSImage? {
        guard let url = NookResources.url(
            forResource: "NookLogo",
            withExtension: "svg"
        ),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = size
        // NookStatusItemView uses this vector's alpha as a template mask.
        image.isTemplate = false
        return image
    }
}

@MainActor
final class NookAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusItemView: NookStatusItemView?
    private var panelController: NookPanelController?
    private var updater: NookUpdater?
    private let language = NookLanguageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        if let iconURL = NookResources.url(forResource: "NookAppIcon", withExtension: "svg"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let statusView = NookStatusItemView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        let image: NSImage?
        if let logo = NookLogoAsset.image(size: NSSize(width: 18, height: 18)) {
            image = logo
        } else {
            let fallback = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Nook")
            fallback?.isTemplate = true
            image = fallback
        }
        statusView.image = image
        statusView.toolTip = language.strings.panelTooltip
        statusView.onPrimaryAction = { [weak self] in self?.togglePanel() }
        statusView.onContextMenu = { [weak self] view in self?.showStatusMenu(from: view) }
        item.view = statusView
        statusItemView = statusView

        let updater = NookUpdater(
            enabledForCurrentBundle: Bundle.main.bundleIdentifier == "com.nook.quicknotes"
                && Bundle.main.bundleURL.pathExtension == "app"
                && !CommandLine.arguments.contains("--preview"),
            prepareToQuit: { [weak self] in self?.panelController?.prepareToQuit() ?? true }
        )
        self.updater = updater
        panelController = NookPanelController(language: language, updater: updater)

        // A separate preview bundle can open the panel on launch for visual QA
        // without changing the shipped menu-bar-first behavior.
        if Bundle.main.bundleIdentifier == "com.nook.quicknotes.preview" || CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.async { [weak self] in
                self?.panelController?.show()
            }
        }
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Nook")
        let settingsItem = NSMenuItem(title: language.strings.settingsTitle + "…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: language.strings.quitNook, action: #selector(quitNook), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    @objc private func openSettings() {
        panelController?.show()
        NotificationCenter.default.post(name: .nookOpenSettings, object: nil)
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return false
    }

    private func showStatusMenu(from view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let checkItem = NSMenuItem(title: language.strings.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        checkItem.target = self
        checkItem.isEnabled = updater?.canCheckForUpdates == true
        menu.addItem(checkItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: language.strings.quitNook,
            action: #selector(quitNook),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.minY), in: view)
    }

    @objc private func quitNook() {
        NSApp.terminate(nil)
    }

    @objc private func checkForUpdates() {
        panelController?.hide()
        updater?.checkForUpdates()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        panelController?.prepareToQuit() == false ? .terminateCancel : .terminateNow
    }
}

@MainActor
private final class NookPanelController: NSObject, NSWindowDelegate {
    private let panel: NookPanel
    private let store: NotesStore
    private let tagStore: TagStore
    private let settings: NookSettingsStore
    private let loginItem: NookLoginItem
    private let editingSession = NookEditingSession()
    private let language: NookLanguageStore
    private var shortcutManager: NookShortcutManager?
    private var didPlacePanel = false
    private var isApplyingPanelFrame = false
    private var isSnappingPanel = false
    private var pendingSnap: DispatchWorkItem?

    private let panelEdgeMargin: CGFloat = 14
    private let panelSnapThreshold: CGFloat = 28

    init(language: NookLanguageStore, updater: NookUpdater) {
        self.language = language
        let isPreview = Bundle.main.bundleIdentifier == "com.nook.quicknotes.preview"
            || CommandLine.arguments.contains("--preview")
        // Preview exercises the real persistence path without touching personal notes.
        let previewDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nook-Editor-Preview", isDirectory: true)
        store = NotesStore(directoryURL: isPreview ? previewDirectory : nil)
        tagStore = TagStore(notes: store.notes)
        if store.migrateBuiltInTags(tagStore.legacyBuiltInRenames) {
            tagStore.finishBuiltInMigration()
        }
        settings = NookSettingsStore()
        loginItem = NookLoginItem()
        panel = NookPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
            // Editing must activate Nook so system UI (including Spotlight
            // clipboard history) returns input to this app, not the app behind it.
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        let manager = NookShortcutManager(settings: settings) { [weak self] in
            self?.show()
        }
        shortcutManager = manager

        let rootView = NookRootView(store: store, tagStore: tagStore, settings: settings, shortcutManager: manager, updater: updater, loginItem: loginItem, editingSession: editingSession, onClose: { [weak self] in
            self?.hide()
        }, onSpacesPreferenceChanged: { [weak self] value in
            self?.applyCollectionBehavior(keepAcrossSpaces: value)
        })
        .environmentObject(language)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        // Clip the native backing layer too: SwiftUI's rounded content mask
        // alone can leave a rectangular hosting layer around transparent corners.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 38
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.delegate = self
        panel.onShellDragEnded = { [weak self] in
            self?.schedulePanelSnap()
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Let the window compositor draw a single soft shadow outside the
        // rounded shell without reserving space inside the editor.
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        // Stay visible while the user works in other apps or clipboard history.
        // Only explicit dismissal should hide this sticky companion panel.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        // The panel is a companion to the desktop, not to a single Space.
        // `canJoinAllSpaces` keeps it visible when the user swipes between
        // desktops; `stationary` prevents Space transitions from dragging it.
        applyCollectionBehavior(keepAcrossSpaces: settings.keepPanelAcrossSpaces)
        // NookPanel owns the small, non-interactive shell/header drag surface.
        // Keeping it at the window layer means the editor, rows, and scroll
        // view never lose their normal SwiftUI hit areas.
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.title = "Nook"
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        if didPlacePanel {
            clampPanelToVisibleScreenIfNeeded()
        } else {
            positionPanel()
            didPlacePanel = true
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        pendingSnap?.cancel()
        pendingSnap = nil
        store.flushPendingPersistence()
        panel.orderOut(nil)
    }

    func prepareToQuit() -> Bool {
        let draftReady = editingSession.prepareToLeave()
        store.flushPendingPersistence()
        let saveError = store.persistenceError.flatMap { $0.isBlocking ? nil : $0 }
        guard !draftReady || saveError != nil else { return true }
        show()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = language.strings.saveFailed
        alert.informativeText = language.strings.unsavedQuitWarning + "\n\n"
            + (editingSession.errorMessage ?? saveError?.reason ?? language.strings.editorError)
        alert.addButton(withTitle: language.strings.retry)
        alert.addButton(withTitle: language.strings.cancel)
        alert.addButton(withTitle: language.strings.quitWithoutSaving)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard editingSession.prepareToLeave() else { return false }
            return store.retryPersistence()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible, !isApplyingPanelFrame, !isSnappingPanel else { return }
        schedulePanelSnap()
    }

    private func positionPanel() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let panelHeight = min(panel.frame.height, visibleFrame.height - (panelEdgeMargin * 2))
        let origin = NSPoint(
            x: visibleFrame.maxX - panel.frame.width - panelEdgeMargin,
            y: visibleFrame.minY + panelEdgeMargin
        )
        applyPanelFrame(
            NSRect(x: origin.x, y: origin.y, width: panel.frame.width, height: panelHeight),
            animated: false
        )
    }

    private func schedulePanelSnap() {
        pendingSnap?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.snapPanelToNearestEdgeIfNeeded()
        }
        pendingSnap = work
        // A short settling window prevents the panel from fighting the native
        // drag while the pointer is still moving, then gives the drop a soft
        // ease-out into the nearest edge.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    private func snapPanelToNearestEdgeIfNeeded() {
        guard panel.isVisible, let screen = screenContainingPanel() else { return }

        let visibleFrame = screen.visibleFrame
        let currentFrame = panel.frame
        var targetOrigin = currentFrame.origin

        if abs(currentFrame.minX - visibleFrame.minX) <= panelSnapThreshold {
            targetOrigin.x = visibleFrame.minX + panelEdgeMargin
        } else if abs(currentFrame.maxX - visibleFrame.maxX) <= panelSnapThreshold {
            targetOrigin.x = visibleFrame.maxX - currentFrame.width - panelEdgeMargin
        }

        if abs(currentFrame.minY - visibleFrame.minY) <= panelSnapThreshold {
            targetOrigin.y = visibleFrame.minY + panelEdgeMargin
        } else if abs(currentFrame.maxY - visibleFrame.maxY) <= panelSnapThreshold {
            targetOrigin.y = visibleFrame.maxY - currentFrame.height - panelEdgeMargin
        }

        // A display can be unplugged while the panel is hidden. Keep the
        // restored window reachable, but do not pull it around during a normal
        // drag unless it is actually outside the active screen's safe frame.
        targetOrigin.x = clamped(
            targetOrigin.x,
            lower: visibleFrame.minX + panelEdgeMargin,
            upper: max(visibleFrame.minX + panelEdgeMargin, visibleFrame.maxX - currentFrame.width - panelEdgeMargin)
        )
        targetOrigin.y = clamped(
            targetOrigin.y,
            lower: visibleFrame.minY + panelEdgeMargin,
            upper: max(visibleFrame.minY + panelEdgeMargin, visibleFrame.maxY - currentFrame.height - panelEdgeMargin)
        )

        guard abs(targetOrigin.x - currentFrame.origin.x) > 0.5 || abs(targetOrigin.y - currentFrame.origin.y) > 0.5 else { return }

        isSnappingPanel = true
        isApplyingPanelFrame = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(targetOrigin)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Borderless utility panels can opt out of the animator when a
                // display seam is crossed. Make the final resting frame
                // deterministic even in that AppKit edge case.
                if abs(self.panel.frame.origin.x - targetOrigin.x) > 0.5
                    || abs(self.panel.frame.origin.y - targetOrigin.y) > 0.5 {
                    self.panel.setFrameOrigin(targetOrigin)
                }
                self.isApplyingPanelFrame = false
                self.isSnappingPanel = false
            }
        }
    }

    private func clampPanelToVisibleScreenIfNeeded() {
        guard let screen = screenContainingPanel() else { return }
        let visibleFrame = screen.visibleFrame
        let currentFrame = panel.frame
        let targetOrigin = NSPoint(
            x: clamped(
                currentFrame.origin.x,
                lower: visibleFrame.minX + panelEdgeMargin,
                upper: max(visibleFrame.minX + panelEdgeMargin, visibleFrame.maxX - currentFrame.width - panelEdgeMargin)
            ),
            y: clamped(
                currentFrame.origin.y,
                lower: visibleFrame.minY + panelEdgeMargin,
                upper: max(visibleFrame.minY + panelEdgeMargin, visibleFrame.maxY - currentFrame.height - panelEdgeMargin)
            )
        )

        guard targetOrigin != currentFrame.origin else { return }
        applyPanelFrame(
            NSRect(origin: targetOrigin, size: currentFrame.size),
            animated: false
        )
    }

    private func applyPanelFrame(_ frame: NSRect, animated: Bool) {
        isApplyingPanelFrame = true
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isApplyingPanelFrame = false
                }
            }
        } else {
            panel.setFrame(frame, display: false)
            isApplyingPanelFrame = false
        }
    }

    private func screenContainingPanel() -> NSScreen? {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }

        // A panel can straddle the seam for a frame while crossing from an
        // upper monitor to a lower one. Choose the screen with the largest
        // overlap instead of jumping back to NSScreen.main.
        return NSScreen.screens.max { lhs, rhs in
            intersectionArea(panel.frame, lhs.frame) < intersectionArea(panel.frame, rhs.frame)
        } ?? NSScreen.main
    }

    private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func applyCollectionBehavior(keepAcrossSpaces: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        if keepAcrossSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        panel.collectionBehavior = behavior
    }

}

private final class NookPanel: NSPanel {
    var onShellDragEnded: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if canStartShellDrag(at: event.locationInWindow) {
                // Let AppKit own the drag loop. This preserves native pointer
                // capture while the panel crosses a display seam (including
                // an upper-to-lower monitor) and avoids stealing SwiftUI's
                // list/editor gestures.
                performDrag(with: event)
                onShellDragEnded?()
                return
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    private func canStartShellDrag(at point: NSPoint) -> Bool {
        let width = frame.width
        let height = frame.height
        let shellGutter: CGFloat = 12
        let headerHeight: CGFloat = 76

        // The outer gutter and the quiet part of the header are intentionally
        // drag-safe. Header controls (settings/minimize/back) stay clickable.
        let inOuterGutter = point.x <= shellGutter
            || point.x >= width - shellGutter
            || point.y <= shellGutter
        let inHeader = point.y >= height - headerHeight
            && point.x < width - 100

        return inOuterGutter || inHeader
    }

}
