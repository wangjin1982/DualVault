import XCTest
@testable import DualVault

final class AppThemeTests: XCTestCase {

    /// 4 套内置皮肤全部合法 + Codable 往返一致。
    func testBuiltInsRoundTrip() throws {
        XCTAssertEqual(AppTheme.builtIns.count, 4)
        for theme in AppTheme.builtIns {
            XCTAssertTrue(HexColor.validate(theme), "\(theme.name) 颜色非法")
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
            XCTAssertEqual(decoded, theme)
        }
    }

    /// 手册 §3 样例 JSON 可解码。
    func testHandbookSampleDecodes() throws {
        let json = """
        {"name":"Midnight","colors":{"background":"#1E1E2E","paneBackground":"#181825",
        "alternateRow":"#232334","selection":"#89B4FA","foreground":"#CDD6F4",
        "secondaryText":"#7F849C","centerBarBackground":"#11111B","destructive":"#F38BA8"},
        "font":{"fileList":13,"pathBar":12},"directoryIconTint":"#89B4FA"}
        """
        let theme = try JSONDecoder().decode(AppTheme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.name, "Midnight")
        XCTAssertTrue(HexColor.validate(theme))
    }

    /// 缺字段 → 默认值兜底，不崩溃。
    func testMissingFieldsGetDefaults() throws {
        let json = #"{ "name": "残缺主题" }"#
        let theme = try JSONDecoder().decode(AppTheme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.name, "残缺主题")
        XCTAssertEqual(theme.colors.background, ThemeColors().background)
        XCTAssertEqual(theme.font.fileList, 13)
    }

    /// 颜色格式错 → validate 判非法（扫描层跳过并标注）。
    func testInvalidColorRejected() {
        let bad = AppTheme(name: "坏颜色", colors: ThemeColors(background: "不是hex"))
        XCTAssertFalse(HexColor.validate(bad))
        let good = AppTheme(name: "好颜色", colors: ThemeColors(background: "#FF8800"))
        XCTAssertTrue(HexColor.validate(good))
    }

    func testHexParsing() {
        let c = HexColor.rgba("#FF8800")!
        XCTAssertEqual(c.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 0x88 / 255.0, accuracy: 0.01)
        XCTAssertNil(HexColor.rgba("FF8800"))   // 缺 #
        XCTAssertNil(HexColor.rgba("#12345"))   // 位数错
    }
}

final class ThemeStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dv-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testScanUserThemesValidAndInvalid() throws {
        let valid = AppTheme(name: "用户主题", colors: ThemeColors(background: "#112233"))
        try JSONEncoder().encode(valid).write(to: dir.appendingPathComponent("用户主题.json"))
        try Data("不是json".utf8).write(to: dir.appendingPathComponent("坏文件.json"))
        let badColor = AppTheme(name: "坏色", colors: ThemeColors(selection: "red"))
        try JSONEncoder().encode(badColor).write(to: dir.appendingPathComponent("坏色.json"))

        let store = ThemeStore(userThemesDir: dir)
        XCTAssertEqual(store.themes.count, 4 + 1)         // 内置 4 + 1 合法
        XCTAssertNotNil(store.theme(named: "用户主题"))
        XCTAssertEqual(Set(store.failedNames), ["坏文件.json", "坏色.json"])
    }

    func testReloadPicksUpNewFiles() throws {
        let store = ThemeStore(userThemesDir: dir)
        XCTAssertEqual(store.themes.count, 4)
        let late = AppTheme(name: "迟到主题")
        try JSONEncoder().encode(late).write(to: dir.appendingPathComponent("迟到主题.json"))
        store.reload()
        XCTAssertNotNil(store.theme(named: "迟到主题"))
    }
}

final class LayoutStoreTests: XCTestCase {

    func testLayoutRoundTrip() throws {
        var state = LayoutState()
        state.windowWidth = 1234
        state.windowHeight = 567
        state.focusedSide = "right"
        state.themeName = "TC-Classic"
        state.left = PaneGroupSnapshot(selectedTab: 1, tabs: [
            PaneSnapshot(path: "/tmp/a", sortKey: "size", sortAscending: false, includeHidden: true),
            PaneSnapshot(path: "/tmp/b"),
        ])
        LayoutStore.save(state)
        let loaded = LayoutStore.load()
        XCTAssertEqual(loaded, state)
    }

    /// 损坏数据 → nil，不崩溃。
    func testCorruptDataReturnsNil() {
        UserDefaults.standard.set(Data([0xDE, 0xAD]), forKey: "layout.state")
        XCTAssertNil(LayoutStore.load())
    }

    override func tearDown() {
        LayoutStore.clear()
    }
}

final class DosDateTests: XCTestCase {

    /// DOS 日期往返：编码再解码，误差 ≤ 2 秒（DOS 秒精度 2s）。
    func testDosDateRoundTrip() {
        let now = Date()
        let (d, t) = ZipEngine.dosDateTime(now)
        let decoded = ZipEngine.date(fromDosDate: d, dosTime: t)
        XCTAssertEqual(abs(decoded.timeIntervalSince(now)), 0, accuracy: 2.5)
    }

    func testDosDateKnownValue() {
        // 2024-01-15 12:30:00 本地时区
        var components = tm()
        components.tm_year = 124; components.tm_mon = 0; components.tm_mday = 15
        components.tm_hour = 12; components.tm_min = 30; components.tm_sec = 0
        components.tm_isdst = -1
        let expected = Date(timeIntervalSince1970: TimeInterval(mktime(&components)))
        let (d, t) = ZipEngine.dosDateTime(expected)
        let decoded = ZipEngine.date(fromDosDate: d, dosTime: t)
        XCTAssertEqual(decoded.timeIntervalSince(expected), 0, accuracy: 2.5)
    }
}
