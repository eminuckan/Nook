import XCTest
@testable import Nook

final class ResourceTests: XCTestCase {
    func testDistributedAppResolvesCopiedResourcesWithoutBuildDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Nook.app/Contents/Resources")
        let bundle = resources.appendingPathComponent("Nook_Nook.bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let logo = bundle.appendingPathComponent("NookLogo.svg")
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8).write(to: logo)
        XCTAssertEqual(NookResources.packagedURL(forResource: "NookLogo", withExtension: "svg", resourceDirectory: resources), logo)
        XCTAssertNil(NookResources.packagedURL(forResource: "Missing", withExtension: "svg", resourceDirectory: resources))
        XCTAssertNil(NookResources.packagedURL(forResource: "NookLogo", withExtension: "svg", resourceDirectory: nil))
    }
}
