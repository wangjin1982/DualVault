import Foundation

enum SelectionFallback {

    /// 空选择回退到光标所在项（《开发手册》§6 用例 4）。
    /// cursor 为表格最近一次点击/键盘定位的行。
    static func effectiveSelection(selection: [URL], cursor: URL?) -> [URL] {
        if !selection.isEmpty { return selection }
        if let cursor = cursor { return [cursor] }
        return []
    }
}
