import XCTest
@testable import DualVault

/// 标签页状态隔离（验收 #5 的模型层）。
final class PaneGroupModelTests: XCTestCase {
    var base: URL!
    var dirA: URL!
    var dirB: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-tabs-\(UUID().uuidString)")
        dirA = base.appendingPathComponent("dirA")
        dirB = base.appendingPathComponent("dirB")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func testNewTabInheritsCurrentDirectory() {
        let group = PaneGroupModel(side: .left, initialURL: dirA)
        group.selectedPane.navigate(to: dirB)
        let tab = group.newTab()
        XCTAssertEqual(tab.state.url.path, dirB.standardizedFileURL.path)
        XCTAssertEqual(group.tabs.count, 2)
        XCTAssertEqual(group.selectedTabID, tab.id)
    }

    func testLastTabCannotClose() {
        let group = PaneGroupModel(side: .left, initialURL: dirA)
        let only = group.selectedTabID
        XCTAssertFalse(group.closeTab(id: only))
        XCTAssertEqual(group.tabs.count, 1)
    }

    func testCloseTabSelectsNeighbor() {
        let group = PaneGroupModel(side: .left, initialURL: dirA)
        let second = group.newTab()
        let third = group.newTab()
        XCTAssertTrue(group.closeTab(id: third.id))
        XCTAssertEqual(group.selectedTabID, second.id)
    }

    func testTabStatesIndependent() {
        let group = PaneGroupModel(side: .left, initialURL: dirA)
        let first = group.selectedTab
        let second = group.newTab()
        second.state.navigate(to: dirB)
        second.state.selectAll()
        // 切回第一个标签：路径与选择互不影响
        group.select(id: first.id)
        XCTAssertEqual(group.selectedPane.url.path, dirA.standardizedFileURL.path)
        XCTAssertTrue(group.selectedPane.selection.isEmpty)
        group.select(id: second.id)
        XCTAssertEqual(group.selectedPane.url.path, dirB.standardizedFileURL.path)
    }
}

/// 隐藏文件开关两栏独立记忆（验收 #4）。
final class HiddenFilesToggleTests: XCTestCase {
    var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-hidden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base.appendingPathComponent(".secret"))
        try Data("y".utf8).write(to: base.appendingPathComponent("visible"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func testTogglePerPaneIndependent() {
        let left = PaneState(url: base)
        let right = PaneState(url: base)
        XCTAssertEqual(left.items.count, 1)
        XCTAssertEqual(right.items.count, 1)
        left.toggleHiddenFiles()
        XCTAssertEqual(left.items.count, 2)   // 左栏已显示隐藏
        XCTAssertEqual(right.items.count, 1)  // 右栏不受影响
        right.toggleHiddenFiles()
        XCTAssertEqual(right.items.count, 2)
        left.toggleHiddenFiles()
        XCTAssertEqual(left.items.count, 1)   // 再切回，各自独立记忆
        XCTAssertEqual(right.items.count, 2)
    }
}
