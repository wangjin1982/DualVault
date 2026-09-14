import Foundation

/// 废纸篓能力抽象：返回实际落入位置（trashItem 的 resultingItemURL），
/// undo 按记录的位置精确恢复——废除"同名/前缀猜测"（同名多次删除会找错文件）。
protocol TrashBackend {
    func trash(_ url: URL) throws -> URL
}

/// 默认实现：macOS 系统废纸篓。
struct FileManagerTrashBackend: TrashBackend {
    func trash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let landed = result as URL? else {
            throw OperationError.unexpected("废纸篓未返回落地位置：\(url.lastPathComponent)")
        }
        return landed
    }
}
