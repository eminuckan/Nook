import XCTest
import ServiceManagement
@testable import Nook

@MainActor
private final class FakeLoginItemService: NookLoginItemService {
    var status: SMAppService.Status = .notRegistered
    var nextRegisteredStatus: SMAppService.Status = .enabled
    var shouldFail = false
    var registrations = 0
    var unregistrations = 0
    func register() throws {
        registrations += 1
        if shouldFail { throw NSError(domain: "LoginItemTest", code: 1) }
        status = nextRegisteredStatus
    }
    func unregister() throws {
        unregistrations += 1
        if shouldFail { throw NSError(domain: "LoginItemTest", code: 2) }
        status = .notRegistered
    }
}

final class LoginItemTests: XCTestCase {
    @MainActor
    func testToggleReflectsServiceAndExternalChanges() async {
        let service = FakeLoginItemService()
        let item = NookLoginItem(service: service, isSupported: true)
        item.setEnabled(true)
        XCTAssertTrue(item.isRequested)
        XCTAssertEqual(service.registrations, 1)
        service.status = .notRegistered
        item.refresh()
        XCTAssertFalse(item.isRequested)
        item.setEnabled(true)
        item.setEnabled(false)
        XCTAssertFalse(item.isRequested)
        XCTAssertEqual(service.unregistrations, 1)
    }

    @MainActor
    func testRegistrationFailureDoesNotPretendToBeEnabled() async {
        let service = FakeLoginItemService()
        let item = NookLoginItem(service: service, isSupported: true)
        service.shouldFail = true
        item.setEnabled(true)
        XCTAssertFalse(item.isRequested)
        XCTAssertNotNil(item.errorMessage)
        service.shouldFail = false
        item.setEnabled(true)
        XCTAssertNil(item.errorMessage)
        XCTAssertTrue(item.isRequested)
    }

    @MainActor
    func testApprovalPendingCanBeCancelled() async {
        let service = FakeLoginItemService()
        service.nextRegisteredStatus = .requiresApproval
        let item = NookLoginItem(service: service, isSupported: true)
        item.setEnabled(true)
        XCTAssertTrue(item.isRequested)
        XCTAssertTrue(item.needsApproval)
        item.setEnabled(false)
        XCTAssertFalse(item.needsApproval)
        XCTAssertFalse(item.isRequested)
    }

    @MainActor
    func testPreviewNeverRegistersProductionApp() async {
        let service = FakeLoginItemService()
        service.status = .enabled
        let item = NookLoginItem(service: service, isSupported: false)
        item.setEnabled(true)
        item.setEnabled(false)
        item.refresh()
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.unregistrations, 0)
        XCTAssertFalse(item.isRequested)
    }
}
