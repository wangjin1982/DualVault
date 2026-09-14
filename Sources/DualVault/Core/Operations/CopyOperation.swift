import Foundation

/// 复制操作：plan.sources → plan.destination，冲突按 resolutions 处理。
final class CopyOperation: FileOperation {
    let plan: TransferPlan
    let resolutions: ConflictResolutions
    /// 实际落到目标的路径（undo 用），execute 后填充。
    private(set) var writtenURLs: [URL] = []

    init(plan: TransferPlan, resolutions: ConflictResolutions) {
        self.plan = plan
        self.resolutions = resolutions
    }

    var title: String {
        "复制 \(plan.sources.count) 项到 \(plan.destination.path)"
    }

    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws {
        let totalFiles = plan.sources.reduce(0) { $0 + CopyEngine.countFiles(under: $1) }
        let totalBytes = CopyEngine.totalSize(of: plan.sources)
        var doneFiles = 0
        var doneBytes: Int64 = 0

        for source in plan.sources {
            if isCancelled() { cleanupPartial(); throw OperationError.cancelled }
            let name = source.lastPathComponent
            guard let destName = ConflictPrecheck.destinationName(for: name, in: plan, resolutions: resolutions) else {
                doneFiles += CopyEngine.countFiles(under: source)
                continue // 跳过
            }
            let dest = plan.destination.appendingPathComponent(destName)
            try CopyEngine.copyItem(from: source, to: dest, isCancelled: isCancelled, onFile: {
                doneFiles += 1
                progress(doneFiles, totalFiles, doneBytes, totalBytes)
            }, onBytes: { n in
                doneBytes += n
                progress(doneFiles, totalFiles, doneBytes, totalBytes)
            })
            writtenURLs.append(dest)
            progress(doneFiles, totalFiles, doneBytes, totalBytes)
        }
    }

    /// 取消/失败时清理已写入的半成品（仅限本次操作创建的顶层项）。
    func cleanupPartial() {
        let fm = FileManager.default
        for url in writtenURLs {
            do { try fm.removeItem(at: url) }
            catch { logCleanupFailure(error, context: "cleanupPartial \(url.lastPathComponent)") }
        }
        writtenURLs.removeAll()
    }

    func undo() throws {
        let fm = FileManager.default
        var failures: [String] = []
        for url in writtenURLs {
            do { try fm.trashItem(at: url, resultingItemURL: nil) }
            catch { failures.append(url.lastPathComponent) }
        }
        if !failures.isEmpty {
            throw OperationError.unexpected("撤销复制失败：\(failures.joined(separator: ", "))")
        }
        writtenURLs.removeAll()
    }
}
