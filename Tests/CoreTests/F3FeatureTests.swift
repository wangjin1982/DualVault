import XCTest
@testable import DualVault

/// F3 收官包单测：zip 预览 / 分支视图 / 正则重命名 / 分割合并。
final class F3FeatureTests: XCTestCase {
    var base: URL!
    var dir: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-f3-\(UUID().uuidString)")
        dir = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: F3-1 zip 内 QuickLook：临时解压 → 预览 → 清理

    func testZipPreviewStageAndCleanup() throws {
        let src = dir.appendingPathComponent("pic.txt")
        try Data("preview-content".utf8).write(to: src)
        let zip = dir.appendingPathComponent("p.zip")
        try ZipEngine.zip([src], to: zip, isCancelled: { false })

        let tempRoot = base.appendingPathComponent("preview-tmp")
        let staged = try ZipPreviewService.stage(archive: zip, entry: "pic.txt", tempRoot: tempRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertEqual(try String(contentsOf: staged), "preview-content")

        ZipPreviewService.cleanup(tempRoot: tempRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.path))
    }

    // MARK: F3-2 分支视图

    func testBranchFlattenNestedTree() throws {
        try Data("1".utf8).write(to: dir.appendingPathComponent("root.txt"))
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("22".utf8).write(to: sub.appendingPathComponent("inner.txt"))
        let deep = sub.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data("333".utf8).write(to: deep.appendingPathComponent("leaf.txt"))

        let flat = BranchFlattener.flatten(root: dir, includeHidden: false)
        let names = flat.map(\.name)
        XCTAssertTrue(names.contains("root.txt"))
        XCTAssertTrue(names.contains("sub/"))
        XCTAssertTrue(names.contains("inner.txt"))
        XCTAssertTrue(names.contains("leaf.txt"))
        // 目录条目存在且标记为目录
        XCTAssertTrue(flat.first { $0.name == "sub/" }!.isDirectory)
        // 返回真实路径：可直接用于搬运
        XCTAssertTrue(flat.first { $0.name == "leaf.txt" }!.url.path.contains("deep"))
    }

    func testBranchFlattenRespectsHiddenFilter() throws {
        try Data("x".utf8).write(to: dir.appendingPathComponent(".hidden"))
        try Data("y".utf8).write(to: dir.appendingPathComponent("visible"))
        XCTAssertEqual(BranchFlattener.flatten(root: dir, includeHidden: false).count, 1)
        XCTAssertEqual(BranchFlattener.flatten(root: dir, includeHidden: true).count, 2)
    }

    // MARK: F3-3 正则重命名

    func testRegexLiteralAndCaptureGroup() throws {
        var r = RenameRules()
        r.useRegex = true
        r.find = #"^IMG_(\d+)$"#
        r.replace = "照片-$1"
        let entries = try BatchRename.plan(names: ["IMG_001.jpg", "IMG_002.jpg"],
                                           rules: r, existingNames: [])
        XCTAssertEqual(entries[0].renamed, "照片-001.jpg")
        XCTAssertEqual(entries[1].renamed, "照片-002.jpg")
    }

    func testInvalidRegexThrows() {
        var r = RenameRules()
        r.useRegex = true
        r.find = "([未闭合"
        XCTAssertNotNil(r.regexError())
        XCTAssertThrowsError(try BatchRename.plan(names: ["a.txt"], rules: r, existingNames: []))
    }

    func testRegexCoexistsWithLiteralMode() throws {
        // 同一字段：useRegex=false 按字面量，true 按正则
        let literal = RenameRules(find: "2024", replace: "25")
        let lit = try BatchRename.plan(names: ["photo2024.txt"], rules: literal, existingNames: [])
        XCTAssertEqual(lit[0].renamed, "photo25.txt")

        var regex = RenameRules(find: "(\\d+)", replace: "N")
        regex.useRegex = true
        let reg = try BatchRename.plan(names: ["photo2024.txt"], rules: regex, existingNames: [])
        XCTAssertEqual(reg[0].renamed, "photoN.txt")
    }

    func testPreserveExtensionToggle() throws {
        // preserveExtension=false：扩展名参与替换
        var r = RenameRules(find: "a", replace: "b")
        r.preserveExtension = false
        let entries = try BatchRename.plan(names: ["aka.aaa"], rules: r, existingNames: [])
        XCTAssertEqual(entries[0].renamed, "bkb.bbb")
        // 默认 true：扩展名不动
        let def = try BatchRename.plan(names: ["aka.aaa"], rules: RenameRules(find: "a", replace: "b"), existingNames: [])
        XCTAssertEqual(def[0].renamed, "bkb.aaa")
    }

    // MARK: F3-5 分割/合并往返

    func testSplitJoinRoundTrip() throws {
        let file = dir.appendingPathComponent("big.bin")
        let original = Data((0..<10_000_000).map { UInt8($0 % 251) })
        try original.write(to: file)

        let parts = try FileSplitter.split(file, partSize: 4_000_000, isCancelled: { false })
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.map { $0.pathExtension }, ["part1", "part2", "part3"])

        let joined = dir.appendingPathComponent("joined.bin")
        try FileSplitter.join(parts: parts, to: joined, isCancelled: { false })
        XCTAssertEqual(try Data(contentsOf: joined), original)
    }

    func testJoinVerifiesSize() throws {
        let file = dir.appendingPathComponent("s.bin")
        try Data(count: 100).write(to: file)
        let parts = try FileSplitter.split(file, partSize: 60, isCancelled: { false })
        // 让一个 part 不可读：join 的 read 失败 → written < total → 校验抛错且清理产物
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: parts[0].path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: parts[0].path) }
        let joined = dir.appendingPathComponent("bad-join.bin")
        XCTAssertThrowsError(try FileSplitter.join(parts: parts, to: joined, isCancelled: { false }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: joined.path))
    }

    func testSplitCancelCleansNothingPartial() throws {
        // split 逐 part 写；取消在第一个 part 后不产生半成品（part1 写完即成品，语义可接受）
        let file = dir.appendingPathComponent("c.bin")
        try Data(count: 500).write(to: file)
        var calls = 0
        let parts = try? FileSplitter.split(file, partSize: 100, isCancelled: {
            calls += 1
            return calls > 2
        })
        XCTAssertNil(parts)
    }

    func testSetDateUndo() throws {
        let file = dir.appendingPathComponent("d.txt")
        try Data("x".utf8).write(to: file)
        let past = Date(timeIntervalSince1970: 1_000_000)
        let op = SetDateOperation(target: file, newDate: past)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attrs[.modificationDate] as? Date, past)

        try op.undo()
        let restored = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertNotEqual(restored[.modificationDate] as? Date, past)
    }
}
