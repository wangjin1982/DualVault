import XCTest
@testable import DualVault

final class E1ServiceTests: XCTestCase {
    var base: URL!
    var dir: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-e1-\(UUID().uuidString)")
        dir = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: RenameOperation 执行 + 撤销

    func testRenameOperationExecuteAndUndo() throws {
        let a = dir.appendingPathComponent("old-a.txt")
        let b = dir.appendingPathComponent("old-b.txt")
        try Data("1".utf8).write(to: a)
        try Data("2".utf8).write(to: b)
        let op = RenameOperation(pairs: [
            (a, dir.appendingPathComponent("new-a.txt")),
            (b, dir.appendingPathComponent("new-b.txt")),
        ])
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new-a.txt").path))

        try op.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    // MARK: FolderSizer

    func testFolderSizerTotalsAndSkips() throws {
        try Data(count: 100).write(to: dir.appendingPathComponent("f1"))
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(count: 50).write(to: sub.appendingPathComponent("f2"))
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 999).write(to: locked.appendingPathComponent("secret"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let result = FolderSizer.compute(urls: [dir], isCancelled: { false }, onProgress: { _, _ in })
        XCTAssertEqual(result.size, 150)
        XCTAssertEqual(result.files, 2)
        XCTAssertEqual(result.skipped, 1)
    }

    func testFolderSizerCancelStops() throws {
        for i in 0..<50 {
            try Data(count: 10).write(to: dir.appendingPathComponent("f\(i)"))
        }
        var calls = 0
        let result = FolderSizer.compute(urls: [dir], isCancelled: {
            calls += 1
            return calls > 5
        }, onProgress: { _, _ in })
        XCTAssertLessThan(result.files, 50)
    }
}
