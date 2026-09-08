import AppKit
import Combine
import ServiceManagement

@MainActor
protocol NookLoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct NookMainAppLoginService: NookLoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// macOS owns this preference. Never show a cached toggle after registration
/// fails or the user changes Login Items in System Settings.
@MainActor
final class NookLoginItem: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?
    let isSupported: Bool
    private let service: NookLoginItemService

    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    init(service: NookLoginItemService? = nil, isSupported: Bool? = nil) {
        let resolved = service ?? NookMainAppLoginService()
        self.service = resolved
        let applications = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        self.isSupported = isSupported ?? (
            Bundle.main.bundleIdentifier == "com.nook.quicknotes"
            && !CommandLine.arguments.contains("--preview")
            && Bundle.main.bundleURL.pathExtension == "app"
            && ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path].contains(applications)
        )
        status = self.isSupported ? resolved.status : .notRegistered
    }

    func refresh() {
        guard isSupported else { return }
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }
        errorMessage = nil
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
