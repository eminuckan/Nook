import XCTest
@testable import Nook

final class ListLayoutTests: XCTestCase {
    func testNearlyFullListUsesRemainingHeightWithoutChangingGaps() {
        let height = NookLayout.noteHeight(count: 6, availableHeight: 566)
        XCTAssertEqual(height * 6 + NookLayout.itemGap * 5, 566, accuracy: 0.001)
    }

    func testShortListsStayCompactAndOverflowKeepsScrollableRows() {
        XCTAssertEqual(NookLayout.noteHeight(count: 2, availableHeight: 566), 86)
        XCTAssertEqual(NookLayout.noteHeight(count: 7, availableHeight: 566), 86)
        XCTAssertEqual(NookLayout.noteHeight(count: 0, availableHeight: 566), 86)
    }
}
