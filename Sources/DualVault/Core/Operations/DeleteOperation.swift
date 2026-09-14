import Foundation
import os

/// 删除操作：一律进废纸篓（红线）。undo 按记录的落地位置精确恢复。
/// trash 能力可注入：默认系统废纸篓，测试注入模拟实现。
final class DeleteOperation: FileOperation {
    let sources: [URL]
    private let trash: TrashBackend
    /// (原位置, 实际落入废纸篓的位置)——undo 按此精确恢复。
    private(set) var trashed: [(original: URL, landed: URL)] = []

    init(sources: [URL], trash: TrashBackend = FileManagerTrashBackend()) {
        self.sources = sources
        self.trash = trash
    }

    var title: String {
        "删除 \(sources.count) 项到废纸篓"
    }

    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws {
        let total = sources.count
        for (index, source) in sources.enumerated() {
            if isCancelled() { throw OperationError.cancelled }
            do {
                let landed = try trash.trash(source)
                trashed.append((original: source, landed: landed))
            } catch {
                throw OperationError.writeFailed("无法删除 \(source.lastPathComponent)：\(error.localizedDescription)")
            }
            progress(index + 1, total, 0, 0)
        }
    }

    func undo() throws {
        let fm = FileManager.default
        var failures: [String] = []
        for (original, landed) in trashed {
            guard !fm.fileExists(atPath: original.path) else { continue }
            do {
                try fm.moveItem(at: landed, to: original)
            } catch {
                logCleanupFailure(error, context: "DeleteOperation.undo \(original.lastPathComponent)")
                failures.append(original.lastPathComponent)
            }
        }
        if !failures.isEmpty {
            throw OperationError.unexpected("从废纸篓恢复失败：\(failures.joined(separator: ", "))")
        }
        trashed.removeAll()
    }
}
