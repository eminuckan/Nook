import AppKit
import Combine
import Sparkle

/// Sparkle owns update discovery, signature verification, installation and relaunch.
/// Nook only supplies its settings and the document-persistence gate.
@MainActor
final class NookUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    let isEnabled: Bool
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()
    private let prepareToQuit: () -> Bool

    init(enabledForCurrentBundle: Bool, prepareToQuit: @escaping () -> Bool = { true }) {
        isEnabled = enabledForCurrentBundle
            && Bundle.main.bundleIdentifier == "com.nook.quicknotes"
            && Bundle.main.bundleURL.pathExtension == "app"
        self.prepareToQuit = prepareToQuit
        super.init()
        guard isEnabled else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &observations)
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        prepareToQuit()
    }
}
