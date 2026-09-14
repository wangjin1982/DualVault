import XCTest
@testable import DualVault

final class DuplicateFinderTests: XCTestCase {
    var base: URL!
    var root: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-dup-\(UUID().uuidString)")
        root = base.appendingPathComponent("scan")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func testFindsDuplicatesAcrossSubdirectories() throws {
        let content = Data(repeating: 7, count: 500)
        for sub in ["a", "b", "c"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try content.write(to: root.appendingPathComponent("a/photo.jpg"))
        try content.write(to: root.appendingPathComponent("b/copy-of-photo.jpg"))
        try content.write(to: root.appendingPathComponent("c/another.jpg"))
        try Data("unique".utf8).write(to: root.appendingPathComponent("unique.txt"))

        let groups = try DuplicateFinder.find(in: [root])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 3)
        XCTAssertEqual(groups[0].size, 500)
    }

    func testSameSizeDifferentContentNotGrouped() throws {
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("x1.bin"))
        try Data(repeating: 2, count: 100).write(to: root.appendingPathComponent("x2.bin"))
        let groups = try DuplicateFinder.find(in: [root])
        XCTAssertTrue(groups.isEmpty)
    }

    func testDifferentSizesNotGrouped() throws {
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("x.bin"))
        try Data(repeating: 1, count: 200).write(to: root.appendingPathComponent("y.bin"))
        let groups = try DuplicateFinder.find(in: [root])
        XCTAssertTrue(groups.isEmpty)
    }

    func testCancel() throws {
        for i in 0..<10 {
            try Data(repeating: UInt8(i), count: 300).write(to: root.appendingPathComponent("f\(i).bin"))
        }
        // 构造一对真重复，哈希阶段取消
        let dup = Data(repeating: 9, count: 300)
        try dup.write(to: root.appendingPathComponent("d1.bin"))
        try dup.write(to: root.appendingPathComponent("d2.bin"))
        var calls = 0
        XCTAssertThrowsError(try DuplicateFinder.find(in: [root], isCancelled: {
            calls += 1
            return calls > 3
        })) { error in
            XCTAssertEqual(error as? OperationError, .cancelled)
        }
    }
}
