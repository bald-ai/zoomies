import XCTest
@testable import Zoomies

final class BundledResourceLocatorTests: XCTestCase {
    func testMainBundleResourceLookupAndMissingNameUseLocalBundleOnly() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let bundleURL = root.appendingPathComponent("Fixture.bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let resource = bundleURL.appendingPathComponent("fixture.txt")
        try Data("resource".utf8).write(to: resource)
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        XCTAssertEqual(BundledResourceLocator.resourceURL(named: "fixture", withExtension: "txt", mainBundle: bundle)?.standardizedFileURL, resource.standardizedFileURL)
        XCTAssertNil(BundledResourceLocator.resourceURL(named: "absent", withExtension: "txt", mainBundle: bundle))
    }

    func testResourceURLFindsDirectFileInSearchDirectory() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("screenshot-sound.mp3")
        try Data("sound".utf8).write(to: fileURL, options: .atomic)

        let resolvedURL = BundledResourceLocator.resourceURL(
            named: "screenshot-sound",
            withExtension: "mp3",
            searchDirectories: [root]
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, fileURL.standardizedFileURL)
    }

    func testResourceURLFindsFileInsideChildBundle() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let bundleURL = root.appendingPathComponent("Example.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let fileURL = bundleURL.appendingPathComponent("screenshot-sound.mp3")
        try Data("sound".utf8).write(to: fileURL, options: .atomic)

        let resolvedURL = BundledResourceLocator.resourceURL(
            named: "screenshot-sound",
            withExtension: "mp3",
            searchDirectories: [root]
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, fileURL.standardizedFileURL)
    }
}
