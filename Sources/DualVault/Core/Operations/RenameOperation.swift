import Foundation

/// 批量重命名操作：pairs (旧 URL, 新 URL)。undo = 逆序移回。
final class RenameOperation: FileOperation {
    let pairs: [(source: URL, destination: URL)]
    private(set) var applied: [(source: URL, destination: URL)] = []

    init(pairs: [(source: URL, destination: URL)]) {
        self.pairs = pairs
    }

    var title: String { "重命名 \(pairs.count) 项" }

    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws {
        let fm = FileManager.default
        let total = pairs.count
        for (index, pair) in pairs.enumerated() {
            if isCancelled() { throw OperationError.cancelled }
            do {
                try fm.moveItem(at: pair.source, to: pair.destination)
                applied.append(pair)
            } catch {
                throw OperationError.writeFailed("无法重命名 \(pair.source.lastPathComponent)：\(error.localizedDescription)")
            }
            progress(index + 1, total, 0, 0)
        }
    }

    func undo() throws {
        let fm = FileManager.default
        var failures: [String] = []
        for pair in applied.reversed() {
            guard !fm.fileExists(atPath: pair.source.path) else { continue }
            do { try fm.moveItem(at: pair.destination, to: pair.source) }
            catch { failures.append(pair.destination.lastPathComponent) }
        }
        applied.removeAll()
        if !failures.isEmpty {
            throw OperationError.unexpected("撤销重命名失败：\(failures.joined(separator: ", "))")
        }
    }
}

/// 文件夹大小后台计算：触发式（不自动递归全目录），可取消，回报进度。
enum FolderSizer {
    /// 返回 (总字节, 已统计文件数, 跳过不可读目录数)。
    static func compute(
        urls: [URL],
        isCancelled: () -> Bool,
        onProgress: (Int64, Int) -> Void
    ) -> (size: Int64, files: Int, skipped: Int) {
        var size: Int64 = 0
        var files = 0
        var skipped = 0

        func walk(_ url: URL) {
            if isCancelled() { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
            if isDir.boolValue {
                guard let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                    skipped += 1
                    return
                }
                for child in children {
                    if isCancelled() { return }
                    walk(url.appendingPathComponent(child))
                }
            } else {
                let s = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
                size += s
                files += 1
                onProgress(size, files)
            }
        }

        for url in urls { walk(url) }
        return (size, files, skipped)
    }
}
