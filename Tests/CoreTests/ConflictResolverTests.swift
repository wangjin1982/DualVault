import XCTest
@testable import DualVault

final class ConflictResolverTests: XCTestCase {

    func testNoConflictReturnsOriginalName() {
        let name = ConflictResolver.resolvedName(for: "报告.pdf", strategy: .keepBoth, existingNames: ["其他.txt"])
        XCTAssertEqual(name, "报告.pdf")
    }

    func testOverwriteKeepsName() {
        let name = ConflictResolver.resolvedName(for: "报告.pdf", strategy: .overwrite, existingNames: ["报告.pdf"])
        XCTAssertEqual(name, "报告.pdf")
    }

    func testSkipReturnsNil() {
        let name = ConflictResolver.resolvedName(for: "报告.pdf", strategy: .skip, existingNames: ["报告.pdf"])
        XCTAssertNil(name)
    }

    func testKeepBothAddsSuffix() {
        let name = ConflictResolver.resolvedName(for: "报告.pdf", strategy: .keepBoth, existingNames: ["报告.pdf"])
        XCTAssertEqual(name, "报告 副本.pdf")
    }

    func testKeepBothEscalatesCounter() {
        let existing: Set<String> = ["报告.pdf", "报告 副本.pdf", "报告 副本 2.pdf"]
        let name = ConflictResolver.resolvedName(for: "报告.pdf", strategy: .keepBoth, existingNames: existing)
        XCTAssertEqual(name, "报告 副本 3.pdf")
    }

    func testKeepBothDirectoryWithoutExtension() {
        let name = ConflictResolver.resolvedName(for: "资料", strategy: .keepBoth, existingNames: ["资料"])
        XCTAssertEqual(name, "资料 副本")
    }

    func testLeadingDotfileHandled() {
        // ".gitignore" 点在第一字符，不当扩展名切分
        let name = ConflictResolver.uniqueCopyName(for: ".gitignore", in: [".gitignore"])
        XCTAssertEqual(name, ".gitignore 副本")
    }
}
