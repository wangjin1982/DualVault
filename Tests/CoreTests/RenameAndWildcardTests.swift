import XCTest
@testable import DualVault

final class WildcardMatcherTests: XCTestCase {

    func testStar() throws {
        XCTAssertTrue(WildcardMatcher.matches("report.pdf", pattern: "*.pdf"))
        XCTAssertFalse(WildcardMatcher.matches("report.txt", pattern: "*.pdf"))
        XCTAssertTrue(WildcardMatcher.matches("a.pdf", pattern: "*.*"))
    }

    func testQuestionMark() throws {
        XCTAssertTrue(WildcardMatcher.matches("file1.txt", pattern: "file?.txt"))
        XCTAssertFalse(WildcardMatcher.matches("file12.txt", pattern: "file?.txt"))
    }

    func testMultiSegment() throws {
        XCTAssertTrue(WildcardMatcher.matches("2024-01-报告.pdf", pattern: "2024-*-*.pdf"))
        XCTAssertTrue(WildcardMatcher.matches("ab", pattern: "a*b"))
        XCTAssertTrue(WildcardMatcher.matches("acb", pattern: "a*b"))
        XCTAssertFalse(WildcardMatcher.matches("axbyc", pattern: "a*b"))
    }

    func testCaseInsensitivityDefault() throws {
        XCTAssertTrue(WildcardMatcher.matches("REPORT.PDF", pattern: "*.pdf"))
        XCTAssertFalse(WildcardMatcher.matches("REPORT.PDF", pattern: "*.pdf", caseSensitive: true))
    }

    func testEdgeCases() throws {
        XCTAssertTrue(WildcardMatcher.matches("", pattern: "*"))
        XCTAssertTrue(WildcardMatcher.matches("abc", pattern: "abc"))
        XCTAssertFalse(WildcardMatcher.matches("abc", pattern: "abd"))
    }
}

final class BatchRenameTests: XCTestCase {

    let rules = RenameRules()

    func testFindReplaceKeepsExtension() throws {
        let entries = try BatchRename.plan(names: ["照片 001.jpg", "照片 002.jpg"],
                                       rules: RenameRules(find: "照片", replace: "图片"),
                                       existingNames: [])
        XCTAssertEqual(entries[0].renamed, "图片 001.jpg")
        XCTAssertEqual(entries[1].renamed, "图片 002.jpg")
        XCTAssertFalse(entries[0].conflict)
    }

    func testPrefixSuffixAndCase() throws {
        var r = RenameRules(prefix: "新-", suffix: "-终")
        r.caseTransform = .upper
        let entries = try BatchRename.plan(names: ["abc.txt"], rules: r, existingNames: [])
        XCTAssertEqual(entries[0].renamed, "新-ABC-终.txt")
    }

    func testNumberTemplate() throws {
        var r = RenameRules()
        r.template = "照片 ({N})"
        let entries = try BatchRename.plan(names: ["a.jpg", "b.jpg", "c.jpg"],
                                       rules: r, existingNames: [],
                                       )
        XCTAssertEqual(entries.map(\.renamed), ["照片 (1).jpg", "照片 (2).jpg", "照片 (3).jpg"])
    }

    func testTemplateStartNumberAndNameToken() throws {
        var r = RenameRules()
        r.template = "{name}-第{N}版"
        r.startNumber = 5
        let entries = try BatchRename.plan(names: ["草稿.txt"], rules: r, existingNames: [])
        XCTAssertEqual(entries[0].renamed, "草稿-第5版.txt")
    }

    func testConflictWithExisting() throws {
        let entries = try BatchRename.plan(names: ["a.txt"],
                                       rules: RenameRules(find: "a", replace: "b"),
                                       existingNames: ["b.txt"])
        XCTAssertTrue(entries[0].conflict)
    }

    func testConflictAmongThemselves() throws {
        // 两个不同名替换后撞车
        let entries = try BatchRename.plan(names: ["a1.txt", "b1.txt"],
                                       rules: RenameRules(find: "1", replace: ""),
                                       existingNames: [])
        XCTAssertEqual(entries[0].renamed, "a.txt")
        XCTAssertEqual(entries[1].renamed, "b.txt")
        XCTAssertFalse(entries[0].conflict)
        XCTAssertFalse(entries[1].conflict)
        // 同名撞车：都变成 x.txt
        let clash = try BatchRename.plan(names: ["p.txt", "q.txt"],
                                     rules: RenameRules(template: "x"),
                                     existingNames: [])
        XCTAssertFalse(clash[0].conflict)
        XCTAssertTrue(clash[1].conflict)   // 后者与前者冲突
    }

    func testNoChangeNoConflict() throws {
        let entries = try BatchRename.plan(names: ["a.txt"], rules: RenameRules(), existingNames: ["a.txt"])
        XCTAssertFalse(entries[0].conflict)
        XCTAssertFalse(BatchRename.hasChanges(entries))
    }

    func testHiddenDotfileNotTreatedAsExtension() throws {
        let entries = try BatchRename.plan(names: [".gitignore"],
                                       rules: RenameRules(find: "git", replace: "hg"),
                                       existingNames: [])
        XCTAssertEqual(entries[0].renamed, ".hgignore")
    }
}
