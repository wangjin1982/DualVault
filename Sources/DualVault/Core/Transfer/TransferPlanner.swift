import Foundation

enum PaneSide: Equatable {
    case left, right

    /// 对侧栏。
    var opposite: PaneSide {
        switch self {
        case .left: return .right
        case .right: return .left
        }
    }
}

enum TransferKind: Equatable {
    case copy, move
}

/// 一次左右互传的操作计划（M1 只生成计划，不执行）。
struct TransferPlan: Equatable {
    let kind: TransferKind
    let sourcePane: PaneSide
    let destinationPane: PaneSide
    let sources: [URL]
    let destination: URL

    /// 空选择（0 项）时生成的计划为"空操作"，UI 应忽略。
    var isEmpty: Bool { sources.isEmpty }
}

/// 方向感知规划器：全应用唯一的方向逻辑来源。
/// 规则：焦点栏 → 对侧栏。焦点在左 = 左→右；焦点在右 = 右→左。
enum TransferPlanner {

    /// - Parameters:
    ///   - focusPane: 当前焦点所在的栏
    ///   - selection: 焦点栏中已选中的条目
    ///   - otherPaneURL: 对侧栏当前目录（目标目录）
    static func plan(
        from focusPane: PaneSide,
        kind: TransferKind,
        selection: [URL],
        to otherPaneURL: URL
    ) -> TransferPlan {
        TransferPlan(
            kind: kind,
            sourcePane: focusPane,
            destinationPane: focusPane.opposite,
            sources: selection,
            destination: otherPaneURL
        )
    }
}
