import XCTest
@testable import DualVault

/// F4 打磨收敛：合并冲突收口 / 比较进度 / 重复组自选保留。
final class F4ConvergenceTests: XCTestCase {
    var base: URL!
    var dir: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-f4-\(UUID().uuidString)")
        dir = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: F4-1 合并产物冲突走 ConflictResolver

    func testJoinKeepBothOnExistingDestination() throws {
        let file = dir.appendingPathComponent("big.bin")
        let original = Data((0..<300).map { UInt8($0 % 251) })
        try original.write(to: file)
        let parts = try FileSplitter.split(file, partSize: 200, isCancelled: { false })
        try FileManager.default.removeItem(at: file)
        // 已存在同名产物
        try Data("old".utf8).write(to: dir.appendingPathComponent("big.bin"))

        let resolved = JoinOperation.resolvedDestination(
            dir.appendingPathComponent("big.bin"),
            existingNames: ["big.bin"],
            resolutions: ConflictResolutions(perName: ["big.bin": .keepBoth]))
        XCTAssertEqual(resolved?.lastPathComponent, "big 副本.bin")

        let fakeTrash = try FileOperationsTests.FakeTrash(bin: base.appendingPathComponent("trash"))
        let op = JoinOperation(parts: parts, destination: dir.appendingPathComponent("big.bin"),
                               resolutions: ConflictResolutions(perName: ["big.bin": .keepBoth]),
                               trash: fakeTrash)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("big 副本.bin")), original)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("big.bin")), "old") // 原产物未动

        try op.undo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("big 副本.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: parts[0].path)) // parts 还原
    }

    func testJoinOverwriteTrashesExistingAndUndoRestores() throws {
        let file = dir.appendingPathComponent("doc.bin")
        let original = Data((0..<100).map { UInt8($0 % 13) })
        try original.write(to: file)
        let parts = try FileSplitter.split(file, partSize: 60, isCancelled: { false })
        try FileManager.default.removeItem(at: file)
        try Data("previous".utf8).write(to: dir.appendingPathComponent("doc.bin"))

        let fakeTrash = try FileOperationsTests.FakeTrash(bin: base.appendingPathComponent("trash"))
        let op = JoinOperation(parts: parts, destination: dir.appendingPathComponent("doc.bin"),
                               resolutions: ConflictResolutions(perName: ["doc.bin": .overwrite]),
                               trash: fakeTrash)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("doc.bin")), original) // 已覆盖

        try op.undo()
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("doc.bin")), "previous") // 旧产物还原
        XCTAssertTrue(FileManager.default.fileExists(atPath: parts[0].path))
    }

    func testJoinSkipThrowsCancelled() throws {
        let file = dir.appendingPathComponent("s.bin")
        try Data(count: 100).write(to: file)
        let parts = try FileSplitter.split(file, partSize: 60, isCancelled: { false })
        let op = JoinOperation(parts: parts, destination: file,
                               resolutions: ConflictResolutions(perName: ["s.bin": .skip]))
        XCTAssertThrowsError(try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })) { error in
            XCTAssertEqual(error as? OperationError, .cancelled)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: parts[0].path)) // 未动
    }

    // MARK: F4-2 比较进度回调

    func testCompareProgressIncreases() throws {
        try Data("a".utf8).write(to: dir.appendingPathComponent("f1"))
        try Data("b".utf8).write(to: dir.appendingPathComponent("f2"))
        let other = base.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: other.appendingPathComponent("f1"))

        var callbacks: [(Int, Int)] = []
        _ = try DiffEngine.compare(left: dir, right: other, mode: .name) {
            callbacks.append(($0, $1))
        }
        XCTAssertFalse(callbacks.isEmpty)
        XCTAssertEqual(callbacks.first?.1, callbacks.last?.1)     // total 稳定
        XCTAssertEqual(callbacks.last?.0, callbacks.last?.1)      // 最终 done == total
        for i in 1..<callbacks.count {
            XCTAssertGreaterThanOrEqual(callbacks[i].0, callbacks[i - 1].0) // 单调递增
        }
    }

    // MARK: F4-3 组内自选保留（纯过滤逻辑）

    func testDuplicateKeepChoiceFilter() throws {
        let files = (0..<3).map { dir.appendingPathComponent("dup\($0).bin") }
        let group = DuplicateGroup(size: 10, files: files)
        let keep = files[2]
        let rest = group.files.filter { $0 != keep }
        XCTAssertEqual(rest, [files[0], files[1]])   // 保留指定项，其余进删除列表
        XCTAssertFalse(rest.contains(keep))
    }
}
