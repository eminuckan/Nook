import XCTest
@testable import Nook

final class UpdaterTests: XCTestCase {
    @MainActor
    func testDisabledUpdaterDoesNotStartOrTryToQuit() {
        var preparedToQuit = false
        let updater = NookUpdater(enabledForCurrentBundle: false) {
            preparedToQuit = true
            return true
        }
        XCTAssertFalse(updater.isEnabled)
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.checkForUpdates()
        XCTAssertFalse(preparedToQuit)
    }

    @MainActor
    func testNonProductionBundleCannotStartUpdater() {
        let updater = NookUpdater(enabledForCurrentBundle: true)
        XCTAssertFalse(updater.isEnabled)
        XCTAssertFalse(updater.canCheckForUpdates)
    }
}
