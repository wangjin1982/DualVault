import XCTest
import CryptoKit
@testable import DualVault

/// 文件夹比较三模式 + 同步计划/执行/撤销 + 干跑一致性（F1 验收 1/2/3/5）。
final class DiffAndSyncTests: XCTestCase {
    var base: URL!
    var left: URL!
    var right: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-diff-\(UUID().uuidString)")
        left = base.appendingPathComponent("left")
        right = base.appendingPathComponent("right")
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func put(_ data: Data, _ root: URL, _ rel: String) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// 构造差异树：共有的 same.txt（同内容）、diff.txt（同名不同内容）、sub/only-left.txt、right-only.txt（仅右侧）
    private func makeDivergentTrees() throws {
        try put(Data("same".utf8), left, "same.txt")
        try put(Data("same".utf8), right, "same.txt")
        try put(Data("left-version".utf8), left, "diff.txt")
        try put(Data("right-version".utf8), right, "diff.txt")
        try put(Data("L".utf8), left, "sub/only-left.txt")
        try put(Data("R".utf8), right, "right-only.txt")
    }

    func testCompareNameMode() throws {
        try makeDivergentTrees()
        let entries = try DiffEngine.compare(left: left, right: right, mode: .name)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0.status) })
        XCTAssertEqual(byPath["same.txt"], .same)
        XCTAssertEqual(byPath["diff.txt"], .same)          // 名称模式不看内容
        XCTAssertEqual(byPath["sub/only-left.txt"], .onlyInLeft)
        XCTAssertEqual(byPath["right-only.txt"], .onlyInRight)
    }

    func testCompareNameSizeMode() throws {
        try makeDivergentTrees()
        let entries = try DiffEngine.compare(left: left, right: right, mode: .nameSize)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0.status) })
        XCTAssertEqual(byPath["diff.txt"], .different)     // 大小不同 → 不同
        XCTAssertEqual(byPath["same.txt"], .same)
    }

    func testCompareContentModeSameSizeDifferentContent() throws {
        // 同名同大小不同内容：只有内容模式能区分
        try put(Data(repeating: 1, count: 100), left, "x.bin")
        try put(Data(repeating: 2, count: 100), right, "x.bin")
        let nameSize = try DiffEngine.compare(left: left, right: right, mode: .nameSize)
        XCTAssertEqual(nameSize.first { $0.relativePath == "x.bin" }?.status, .same)
        let content = try DiffEngine.compare(left: left, right: right, mode: .content)
        XCTAssertEqual(content.first { $0.relativePath == "x.bin" }?.status, .different)
    }

    func testStreamingHashMatchesOneShot() throws {
        let file = left.appendingPathComponent("big.bin")
        try Data((0..<300_000).map { UInt8($0 % 251) }).write(to: file)
        let streamed = try StreamingHasher.sha256(of: file)
        let oneshot = SHA256OneShot(data: try Data(contentsOf: file))
        XCTAssertEqual(streamed, oneshot)
    }

    // MARK: 同步计划

    func testPlanMirrorCoversTrashAndCopy() throws {
        try makeDivergentTrees()
        let entries = try DiffEngine.compare(left: left, right: right, mode: .content)
        let plan = SyncPlan.make(entries: entries, mode: .mirrorLeftToRight, leftRoot: left, rightRoot: right)
        let kinds = Dictionary(grouping: plan, by: { $0.relativePath })
        XCTAssertEqual(kinds["diff.txt"]?.first?.kind, .copyToRight)
        XCTAssertEqual(kinds["sub/only-left.txt"]?.first?.kind, .copyToRight)
        XCTAssertEqual(kinds["right-only.txt"]?.first?.kind, .trashOnRight)
        XCTAssertEqual(kinds["same.txt"], nil)
    }

    func testPlanCopyNewToRightNeverDeletes() throws {
        try makeDivergentTrees()
        let entries = try DiffEngine.compare(left: left, right: right, mode: .nameSize)
        let plan = SyncPlan.make(entries: entries, mode: .copyNewToRight, leftRoot: left, rightRoot: right)
        XCTAssertFalse(plan.contains { $0.kind == .trashOnRight })
        XCTAssertFalse(plan.contains { $0.kind == .copyToLeft })
        XCTAssertEqual(plan.count, 2) // diff.txt（大小不同）+ sub/only-left.txt
    }

    func testPlanBothWays() throws {
        try makeDivergentTrees()
        let entries = try DiffEngine.compare(left: left, right: right, mode: .name)
        let plan = SyncPlan.make(entries: entries, mode: .copyNewBothWays, leftRoot: left, rightRoot: right)
        XCTAssertEqual(plan.first { $0.relativePath == "right-only.txt" }?.kind, .copyToLeft)
        XCTAssertFalse(plan.contains { $0.kind == .trashOnRight })
    }

    // MARK: 执行 + 撤销（镜像删除走 trash，验收 #3）+ 干跑一致性（验收 #5）

    func testMirrorExecutionAndUndo() throws {
        try makeDivergentTrees()
        let entries = try DiffEngine.compare(left: left, right: right, mode: .content)
        let plan = SyncPlan.make(entries: entries, mode: .mirrorLeftToRight, leftRoot: left, rightRoot: right)
        let fakeTrash = try FileOperationsTests.FakeTrash(bin: base.appendingPathComponent("trash"))
        let op = SyncOperation(actions: plan, trash: fakeTrash)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })

        // 执行产物 = 计划承诺：右侧 now = 左侧，右侧独有项进 trash
        XCTAssertEqual(try Data(contentsOf: right.appendingPathComponent("diff.txt")), Data("left-version".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: right.appendingPathComponent("sub/only-left.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: right.appendingPathComponent("right-only.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeTrash.bin.appendingPathComponent("right-only.txt").path))

        try op.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: right.appendingPathComponent("right-only.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: right.appendingPathComponent("sub/only-left.txt").path))
        XCTAssertEqual(try Data(contentsOf: right.appendingPathComponent("diff.txt")), Data("right-version".utf8))
    }

    /// 干跑预览（plan）与实际执行产物一致（验收 #5）。
    func testDryRunMatchesExecution() throws {
        try makeDivergentTrees()
        let entries = try DiffEngine.compare(left: left, right: right, mode: .content)
        let plan = SyncPlan.make(entries: entries, mode: .copyNewToRight, leftRoot: left, rightRoot: right)
        let op = SyncOperation(actions: plan)
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        // 计划中每个 copyToRight 的目标都应存在且内容等于源
        for action in plan where action.kind == .copyToRight {
            XCTAssertEqual(try Data(contentsOf: action.destination), try Data(contentsOf: action.source),
                           "\(action.relativePath) 执行结果与计划不一致")
        }
    }
}

/// 测试内的一次性 SHA256（对照流式实现）。
private func SHA256OneShot(data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
