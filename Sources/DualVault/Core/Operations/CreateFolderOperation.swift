import Foundation

/// 新建文件夹操作：经队列执行（遵守"UI 零直接 FileManager 写"约定），可撤销（进废纸篓）。
final class CreateFolderOperation: FileOperation {
    let directory: URL
    private let trash: TrashBackend
    private(set) var created: URL?

    init(directory: URL, trash: TrashBackend = FileManagerTrashBackend()) {
        self.directory = directory
        self.trash = trash
    }

    var title: String { "新建文件夹 \(directory.lastPathComponent)" }

    func execute(isCancelled: () -> Bool, progress: (Int, Int, Int64, Int64) -> Void) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            created = directory
        } catch {
            throw OperationError.writeFailed("无法创建文件夹：\(error.localizedDescription)")
        }
        progress(1, 1, 0, 0)
    }

    func undo() throws {
        guard let created = created else { return }
        do {
            try trash.trash(created)
        } catch {
            throw OperationError.unexpected("撤销新建文件夹失败：\(created.lastPathComponent)")
        }
        self.created = nil
    }
}
