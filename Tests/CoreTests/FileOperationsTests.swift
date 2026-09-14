import XCTest
@testable import DualVault

/// 执行层集成测试：真实临时目录上验证 复制/移动/删除/冲突/取消/撤销。
final class FileOperationsTests: XCTestCase {
    var base: URL!
    var srcDir: URL!
    var dstDir: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-ops-\(UUID().uuidString)")
        srcDir = base.appendingPathComponent("src")
        dstDir = base.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func makeFile(_ name: String, size: Int, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 7, count: size).write(to: url)
        return url
    }

    private func plan(kind: TransferKind, from: PaneSide, sources: [URL]) -> TransferPlan {
        TransferPlanner.plan(from: from, kind: kind, selection: sources, to: dstDir)
    }

    // MARK: 冲突预检

    func testConflictPrecheckFindsExistingNames() throws {
        let a = try makeFile("a.txt", size: 10, in: srcDir)
        try makeFile("a.txt", size: 999, in: dstDir)
        let b = try makeFile("b.txt", size: 10, in: srcDir)
        let entries = ConflictPrecheck.entries(for: plan(kind: .copy, from: .left, sources: [a, b]))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.sourceName, "a.txt")
        XCTAssertEqual(entries.first?.sourceSize, 10)
        XCTAssertEqual(entries.first?.destSize, 999)
    }

    func testDestinationNameAppliesResolutions() throws {
        try makeFile("a.txt", size: 5, in: dstDir)
        let p = plan(kind: .copy, from: .left, sources: [srcDir.appendingPathComponent("a.txt")])
        XCTAssertNil(ConflictPrecheck.destinationName(for: "a.txt", in: p, resolutions: ConflictResolutions(perName: ["a.txt": .skip])))
        XCTAssertEqual(ConflictPrecheck.destinationName(for: "a.txt", in: p, resolutions: ConflictResolutions(perName: ["a.txt": .keepBoth])), "a 副本.txt")
        XCTAssertEqual(ConflictPrecheck.destinationName(for: "a.txt", in: p, resolutions: ConflictResolutions(perName: ["a.txt": .overwrite])), "a.txt")
        // applyToAll 覆盖逐项
        let all = ConflictResolutions(perName: [:], applyToAll: .keepBoth)
        XCTAssertEqual(ConflictPrecheck.destinationName(for: "a.txt", in: p, resolutions: all), "a 副本.txt")
    }

    // MARK: 复制

    func testCopyOperationCopiesAndUndoTrashes() throws {
        let a = try makeFile("a.txt", size: 100, in: srcDir)
        let op = CopyOperation(plan: plan(kind: .copy, from: .left, sources: [a]), resolutions: ConflictResolutions())
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        let dest = dstDir.appendingPathComponent("a.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(try Data(contentsOf: dest).count, 100)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path)) // 复制不动源

        try op.undo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testCopyCancelledCleansPartialFile() throws {
        let big = try makeFile("big.bin", size: 3_000_000, in: srcDir)
        var calls = 0
        let op = CopyOperation(plan: plan(kind: .copy, from: .left, sources: [big]), resolutions: ConflictResolutions())
        XCTAssertThrowsError(try op.execute(isCancelled: {
            calls += 1
            return calls > 2 // 第二块后取消
        }, progress: { _, _, _, _ in })) { error in
            XCTAssertEqual(error as? OperationError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dstDir.appendingPathComponent("big.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: big.path)) // 源完好
    }

    // MARK: 移动

    func testMoveOperationMovesAtomicallySameVolume() throws {
        let a = try makeFile("move-me.txt", size: 50, in: srcDir)
        let op = MoveOperation(plan: plan(kind: .move, from: .left, sources: [a]), resolutions: ConflictResolutions(), sameVolume: true)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstDir.appendingPathComponent("move-me.txt").path))

        try op.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    func testMoveCrossVolumeCopyVerifyRemove() throws {
        let a = try makeFile("xvol.txt", size: 42, in: srcDir)
        let op = MoveOperation(plan: plan(kind: .move, from: .left, sources: [a]), resolutions: ConflictResolutions(), sameVolume: false)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        // 跨卷 = 复制 + 验证 + 删源：源已消失，目标内容与源一致
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        let dest = dstDir.appendingPathComponent("xvol.txt")
        XCTAssertEqual(try Data(contentsOf: dest).count, 42)
    }

    // MARK: 删除（废纸篓红线）——注入模拟废纸篓，不依赖 ~/.Trash TCC 权限

    final class FakeTrash: TrashBackend {
        let bin: URL
        init(bin: URL) throws { self.bin = bin; try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true) }
        func trash(_ url: URL) throws -> URL {
            // 模拟真实废纸篓：重名自动加后缀
            var landed = bin.appendingPathComponent(url.lastPathComponent)
            var counter = 2
            while FileManager.default.fileExists(atPath: landed.path) {
                landed = bin.appendingPathComponent("\(url.lastPathComponent) \(counter)")
                counter += 1
            }
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        }
    }

    func testDeleteGoesToTrashAndUndoRestores() throws {
        let a = try makeFile("trash-me.txt", size: 10, in: srcDir)
        let fakeTrash = try FakeTrash(bin: base.appendingPathComponent("fake-trash"))
        let op = DeleteOperation(sources: [a], trash: fakeTrash)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeTrash.bin.appendingPathComponent("trash-me.txt").path))

        try op.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    // MARK: 大小/计数工具

    func testTotalSizeAndCount() throws {
        try makeFile("f1", size: 100, in: srcDir)
        try makeFile("f2", size: 200, in: srcDir)
        let sub = srcDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try makeFile("f3", size: 50, in: sub)
        XCTAssertEqual(CopyEngine.totalSize(of: [srcDir]), 350)
        XCTAssertEqual(CopyEngine.countFiles(under: srcDir), 3)
    }
}
