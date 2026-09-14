import XCTest
@testable import DualVault

final class SelectionFallbackTests: XCTestCase {

    func testNonEmptySelectionPassesThrough() {
        let urls = [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]
        XCTAssertEqual(SelectionFallback.effectiveSelection(selection: urls, cursor: URL(fileURLWithPath: "/c")), urls)
    }

    func testEmptySelectionFallsBackToCursor() {
        let cursor = URL(fileURLWithPath: "/a/x.txt")
        XCTAssertEqual(SelectionFallback.effectiveSelection(selection: [], cursor: cursor), [cursor])
    }

    func testEmptySelectionNoCursorYieldsEmpty() {
        XCTAssertTrue(SelectionFallback.effectiveSelection(selection: [], cursor: nil).isEmpty)
    }
}

final class MoveStrategyTests: XCTestCase {

    func testSameVolumeUsesAtomicMove() {
        XCTAssertEqual(MoveOperation.strategy(sourceVolumeEqualsDest: true), "move")
    }

    func testCrossVolumeDegradesToCopyVerifyRemove() {
        XCTAssertEqual(MoveOperation.strategy(sourceVolumeEqualsDest: false), "copy-verify-remove")
    }
}
