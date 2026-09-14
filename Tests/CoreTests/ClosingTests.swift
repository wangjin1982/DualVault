import XCTest
@testable import DualVault

/// M5 收尾：撤销覆盖全操作类型 + 应用到全部行为 + totalSize 不可读统计。
final class ClosingTests: XCTestCase {
    var base: URL!
    var dir: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-close-\(UUID().uuidString)")
        dir = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: 撤销覆盖：删除(已有) / 复制(已有) / 新建文件夹 / 压缩 / 解压

    func testCreateFolderUndoTrashesIt() throws {
        let target = dir.appendingPathComponent("新文件夹")
        let fakeTrash = try FileOperationsTests.FakeTrash(bin: base.appendingPathComponent("trash"))
        let op = CreateFolderOperation(directory: target, trash: fakeTrash)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        try op.undo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeTrash.bin.appendingPathComponent("新文件夹").path))
    }

    func testZipCompressUndoTrashesArchive() throws {
        let file = dir.appendingPathComponent("f.txt")
        try Data("hello".utf8).write(to: file)
        let zipURL = dir.appendingPathComponent("f.zip")
        let fakeTrash = try FileOperationsTests.FakeTrash(bin: base.appendingPathComponent("trash"))
        let op = ZipCompressOperation(sources: [file], destination: zipURL, trash: fakeTrash)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        try op.undo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: zipURL.path))
    }

    func testZipExtractUndoTrashesProducts() throws {
        let file = dir.appendingPathComponent("x.txt")
        try Data("content".utf8).write(to: file)
        let zipURL = dir.appendingPathComponent("x.zip")
        try ZipEngine.zip([file], to: zipURL, isCancelled: { false })
        try FileManager.default.removeItem(at: file)
        let extractTo = base.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractTo, withIntermediateDirectories: true)
        let fakeTrash = try FileOperationsTests.FakeTrash(bin: base.appendingPathComponent("trash"))
        let op = ZipExtractOperation(archive: zipURL, destination: extractTo,
                                     resolutions: ConflictResolutions(), trash: fakeTrash)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractTo.appendingPathComponent("x.txt").path))
        try op.undo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractTo.appendingPathComponent("x.txt").path))
    }

    // MARK: 应用到全部与逐项决策并存（M2 已知问题 2 复核）：逐项优先于 applyToAll

    func testPerNameOverridesApplyToAll() {
        let resolutions = ConflictResolutions(perName: ["a.txt": .skip], applyToAll: .overwrite)
        XCTAssertEqual(resolutions.strategy(for: "a.txt"), .skip)
        XCTAssertEqual(resolutions.strategy(for: "b.txt"), .overwrite)
    }

    // MARK: totalSize 不可读目录统计

    func testTotalSizeDetailedCountsSkipped() throws {
        let ok = dir.appendingPathComponent("ok.txt")
        try Data(count: 100).write(to: ok)
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 50).write(to: locked.appendingPathComponent("inner.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let (size, skipped) = CopyEngine.totalSizeDetailed(of: [ok, locked])
        XCTAssertEqual(size, 100)      // 可读文件统计到；锁定目录内容进不来
        XCTAssertEqual(skipped, 1)     // 锁定目录被计为不可读
    }
}
