import XCTest
@testable import DualVault

final class DirectoryLoaderTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dv-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: tempDir.appendingPathComponent("visible.txt"))
        try Data("b".utf8).write(to: tempDir.appendingPathComponent(".hidden.txt"))
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("subdir"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadsDirectoryContents() throws {
        let items = try DirectoryLoader.load(url: tempDir)
        XCTAssertEqual(items.count, 2) // visible.txt + subdir
        XCTAssertTrue(items.contains { $0.name == "visible.txt" && !$0.isDirectory })
        XCTAssertTrue(items.contains { $0.name == "subdir" && $0.isDirectory })
    }

    func testHiddenFilter() throws {
        let items = try DirectoryLoader.load(url: tempDir, includeHidden: true)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.contains { $0.name == ".hidden.txt" && $0.isHidden })
    }

    func testFileItemFields() throws {
        let items = try DirectoryLoader.load(url: tempDir)
        let file = items.first { $0.name == "visible.txt" }
        XCTAssertEqual(file?.size, 1)
        XCTAssertNotEqual(file?.modified, .distantPast)
        XCTAssertEqual(file?.kind, "TXT")
        let dir = items.first { $0.name == "subdir" }
        XCTAssertEqual(dir?.kind, "文件夹")
    }

    func testNotADirectoryThrows() {
        let fileURL = tempDir.appendingPathComponent("visible.txt")
        XCTAssertThrowsError(try DirectoryLoader.load(url: fileURL)) { error in
            XCTAssertEqual(error as? DirectoryLoaderError, .notADirectory(fileURL))
        }
    }

    func testNonexistentThrows() {
        let ghost = tempDir.appendingPathComponent("ghost")
        XCTAssertThrowsError(try DirectoryLoader.load(url: ghost)) { error in
            XCTAssertEqual(error as? DirectoryLoaderError, .notADirectory(ghost))
        }
    }
}
