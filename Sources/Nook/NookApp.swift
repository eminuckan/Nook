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
struct NookApp: App {
    @NSApplicationDelegateAdaptor(NookAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
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
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: isFlipped,
            hints: nil
        )
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
        guard let url = Bundle.main.url(
            forResource: "NookLogo",
            withExtension: "svg",
            subdirectory: "Nook_Nook.bundle"
        ),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = size
        image.isTemplate = true
        return image
    }
}

@MainActor
final class NookAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusItemView: NookStatusItemView?
    private var panelController: NookPanelController?
    private let language = NookLanguageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let statusView = NookStatusItemView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        let image = NookLogoAsset.image(size: NSSize(width: 18, height: 18))
            ?? NSImage(systemSymbolName: "note.text", accessibilityDescription: "Nook")
        image?.isTemplate = true
        statusView.image = image
        statusView.toolTip = language.strings.panelTooltip
        statusView.onPrimaryAction = { [weak self] in self?.togglePanel() }
        statusView.onContextMenu = { [weak self] view in self?.showStatusMenu(from: view) }
        item.view = statusView
        statusItemView = statusView

        panelController = NookPanelController(language: language)

        // A separate preview bundle can open the panel on launch for visual QA
        // without changing the shipped menu-bar-first behavior.
        if Bundle.main.bundleIdentifier == "com.nook.quicknotes.preview" || CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.async { [weak self] in
                self?.panelController?.show()
            }
        }
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    private func showStatusMenu(from view: NSView) {
        let menu = NSMenu()
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
        panelController?.hide()
        NSApp.terminate(nil)
    }
}

@MainActor
private final class NookPanelController: NSObject, NSWindowDelegate {
    private let panel: NookPanel
    private let store: NotesStore
    private let tagStore: TagStore
    private let settings: NookSettingsStore
    private let language: NookLanguageStore
    private var shortcutManager: NookShortcutManager?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var didPlacePanel = false
    private var isApplyingPanelFrame = false
    private var isSnappingPanel = false
    private var pendingSnap: DispatchWorkItem?

    private let panelEdgeMargin: CGFloat = 14
    private let panelSnapThreshold: CGFloat = 28

    init(language: NookLanguageStore) {
        self.language = language
        store = NotesStore()
        tagStore = TagStore(notes: store.notes)
        settings = NookSettingsStore()
        panel = NookPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let manager = NookShortcutManager(settings: settings) { [weak self] in
            self?.show()
        }
        shortcutManager = manager

        let rootView = NookRootView(store: store, tagStore: tagStore, settings: settings, shortcutManager: manager, onClose: { [weak self] in
            self?.hide()
        }, onSpacesPreferenceChanged: { [weak self] value in
            self?.applyCollectionBehavior(keepAcrossSpaces: value)
        })
        .environmentObject(language)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.delegate = self
        panel.onShellDragEnded = { [weak self] in
            self?.schedulePanelSnap()
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card itself has no outline or halo; keep AppKit from adding a
        // second window shadow that reads like a light border on dark mode.
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
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
        installClickMonitors()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        pendingSnap?.cancel()
        pendingSnap = nil
        store.flushPendingPersistence()
        removeClickMonitors()
        panel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible, !isApplyingPanelFrame, !isSnappingPanel else { return }
        schedulePanelSnap()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another app is the natural end of a quick-capture moment.
        if panel.isVisible && Bundle.main.bundleIdentifier != "com.nook.quicknotes.preview" { hide() }
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

    private func installClickMonitors() {
        removeClickMonitors()

        // Preview keeps the panel mounted while the visual inspector clicks
        // around; the shipped menu-bar bundle still dismisses on outside click.
        if Bundle.main.bundleIdentifier == "com.nook.quicknotes.preview" || CommandLine.arguments.contains("--preview") { return }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            if !self.panel.frame.contains(NSEvent.mouseLocation) { self.hide() }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            let location = NSEvent.mouseLocation
            if !self.panel.frame.contains(location) { self.hide() }
            return event
        }
    }

    private func removeClickMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
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
