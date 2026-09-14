import XCTest
@testable import DualVault

final class TransferPlannerTests: XCTestCase {
    let leftURL = URL(fileURLWithPath: "/tmp/dv-left")
    let rightURL = URL(fileURLWithPath: "/tmp/dv-right")

    func file(_ n: Int) -> URL { leftURL.appendingPathComponent("f\(n).txt") }

    /// 方向矩阵：左焦/右焦 × 复制/移动 × 0/1/多选 = 12 组断言。
    func testDirectionMatrix() {
        // 左焦 + 复制
        let p0 = TransferPlanner.plan(from: .left, kind: .copy, selection: [], to: rightURL)
        XCTAssertEqual(p0.sourcePane, .left)
        XCTAssertEqual(p0.destinationPane, .right)
        XCTAssertEqual(p0.destination, rightURL)
        XCTAssertEqual(p0.kind, .copy)
        XCTAssertTrue(p0.isEmpty)

        let p1 = TransferPlanner.plan(from: .left, kind: .copy, selection: [file(1)], to: rightURL)
        XCTAssertEqual(p1.sources, [file(1)])
        XCTAssertFalse(p1.isEmpty)

        let pN = TransferPlanner.plan(from: .left, kind: .copy, selection: [file(1), file(2), file(3)], to: rightURL)
        XCTAssertEqual(pN.sources.count, 3)

        // 左焦 + 移动
        let m0 = TransferPlanner.plan(from: .left, kind: .move, selection: [], to: rightURL)
        XCTAssertEqual(m0.kind, .move)
        XCTAssertEqual(m0.destinationPane, .right)
        XCTAssertTrue(m0.isEmpty)

        let m1 = TransferPlanner.plan(from: .left, kind: .move, selection: [file(1)], to: rightURL)
        XCTAssertEqual(m1.sources, [file(1)])
        XCTAssertEqual(m1.destination, rightURL)

        let mN = TransferPlanner.plan(from: .left, kind: .move, selection: [file(1), file(2)], to: rightURL)
        XCTAssertEqual(mN.sources.count, 2)

        // 右焦 + 复制：方向反转
        let q0 = TransferPlanner.plan(from: .right, kind: .copy, selection: [], to: leftURL)
        XCTAssertEqual(q0.sourcePane, .right)
        XCTAssertEqual(q0.destinationPane, .left)
        XCTAssertEqual(q0.destination, leftURL)
        XCTAssertTrue(q0.isEmpty)

        let q1 = TransferPlanner.plan(from: .right, kind: .copy, selection: [file(9)], to: leftURL)
        XCTAssertEqual(q1.sources, [file(9)])
        XCTAssertEqual(q1.destination, leftURL)

        let qN = TransferPlanner.plan(from: .right, kind: .copy, selection: [file(8), file(9)], to: leftURL)
        XCTAssertEqual(qN.sources.count, 2)
        XCTAssertEqual(qN.destinationPane, .left)

        // 右焦 + 移动
        let r0 = TransferPlanner.plan(from: .right, kind: .move, selection: [], to: leftURL)
        XCTAssertEqual(r0.kind, .move)
        XCTAssertEqual(r0.destinationPane, .left)
        XCTAssertTrue(r0.isEmpty)

        let r1 = TransferPlanner.plan(from: .right, kind: .move, selection: [file(7)], to: leftURL)
        XCTAssertEqual(r1.sources, [file(7)])

        let rN = TransferPlanner.plan(from: .right, kind: .move, selection: [file(6), file(7)], to: leftURL)
        XCTAssertEqual(rN.sources.count, 2)
    }

    /// 计划是纯数据：相同输入得相同输出（Equatable）。
    func testPlanDeterministic() {
        let a = TransferPlanner.plan(from: .left, kind: .copy, selection: [file(1)], to: rightURL)
        let b = TransferPlanner.plan(from: .left, kind: .copy, selection: [file(1)], to: rightURL)
        XCTAssertEqual(a, b)
    }
}
