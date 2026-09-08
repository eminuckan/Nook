import XCTest
@testable import Nook

@MainActor
private final class FakeDraft: NookDraftSaving {
    var hasUnsavedDraft = true
    var errorMessage: String? = "Could not encode this draft"
    var retrySucceeds = false
    var retries = 0
    func retrySave() -> Bool {
        retries += 1
        if retrySucceeds { hasUnsavedDraft = false }
        return retrySucceeds
    }
}

final class EditingSessionTests: XCTestCase {
    @MainActor
    func testQuitAndRelaunchGateRejectsUnsavedDraftUntilRetrySucceeds() async {
        let session = NookEditingSession()
        let draft = FakeDraft()
        session.attach(draft)
        XCTAssertFalse(session.prepareToLeave())
        XCTAssertTrue(session.hasUnsavedDraft)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertFalse(session.prepareToLeave())
        draft.retrySucceeds = true
        XCTAssertTrue(session.prepareToLeave())
        XCTAssertFalse(session.hasUnsavedDraft)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(draft.retries, 3)
    }

    @MainActor
    func testReadOnlyLoadErrorDoesNotBlockQuitOrRetry() async {
        let session = NookEditingSession()
        let draft = FakeDraft()
        draft.hasUnsavedDraft = false
        session.attach(draft)
        XCTAssertTrue(session.prepareToLeave())
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(draft.retries, 0)
    }
}
