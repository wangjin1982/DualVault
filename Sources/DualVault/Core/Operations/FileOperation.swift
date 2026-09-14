import Foundation

enum OperationError: Error, Equatable {
    case cancelled
    case writeFailed(String)   // 磁盘满/权限等，附可读描述
    case unexpected(String)
}

/// 一次文件系统写操作。所有复制/移动/删除的唯一抽象，经 OperationQueue 执行。
protocol FileOperation {
    /// 用户可见标题，如 "复制 3 项到 /tmp/dst"
    var title: String { get }
    /// 执行；progress 回调 (已完成文件数, 总文件数, 已写字节, 总字节)，随时检查 isCancelled。
    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws
    /// 撤销（⌘Z）。尽力恢复，失败抛出可读错误。
    func undo() throws
}

enum FileOperationKind: Equatable {
    case copy, move, delete
}
