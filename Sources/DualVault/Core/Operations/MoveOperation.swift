import Foundation

/// 移动操作：同卷走 moveItem 原子移动；跨卷降级为 复制+验证+删源，失败时源必须完好。
final class MoveOperation: FileOperation {
    let plan: TransferPlan
    let resolutions: ConflictResolutions
    /// 移动后各源的目标位置（undo 用）。
    private(set) var movedDestinations: [(source: URL, dest: URL)] = []
    private let sameVolume: Bool

    init(plan: TransferPlan, resolutions: ConflictResolutions, sameVolume: Bool? = nil) {
        self.plan = plan
        self.resolutions = resolutions
        self.sameVolume = sameVolume ?? CopyEngine.isSameVolume(plan.sources.first ?? plan.destination, plan.destination)
    }

    var title: String {
        "移动 \(plan.sources.count) 项到 \(plan.destination.path)"
    }

    /// 纯决策函数（可单测）：移动策略 = 同卷原子移动 / 跨卷复制后删源。
    static func strategy(sourceVolumeEqualsDest: Bool) -> String {
        sourceVolumeEqualsDest ? "move" : "copy-verify-remove"
    }

    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws {
        let fm = FileManager.default
        let totalFiles = plan.sources.reduce(0) { $0 + CopyEngine.countFiles(under: $1) }
        let totalBytes = CopyEngine.totalSize(of: plan.sources)
        var doneFiles = 0
        var doneBytes: Int64 = 0
        var stagedCopies: [(source: URL, dest: URL)] = [] // 跨卷：删源前的已验证副本

        do {
            for source in plan.sources {
                if isCancelled() { throw OperationError.cancelled }
                let name = source.lastPathComponent
                guard let destName = ConflictPrecheck.destinationName(for: name, in: plan, resolutions: resolutions) else {
                    doneFiles += CopyEngine.countFiles(under: source)
                    continue
                }
                let dest = plan.destination.appendingPathComponent(destName)
                if sameVolume {
                    try fm.moveItem(at: source, to: dest)
                } else {
                    // 跨卷：复制 → 验证 → 删源。任何一步失败，源保持不动。
                    try CopyEngine.copyItem(from: source, to: dest, isCancelled: isCancelled, onFile: {
                        doneFiles += 1
                        progress(doneFiles, totalFiles, doneBytes, totalBytes)
                    }, onBytes: { n in
                        doneBytes += n
                        progress(doneFiles, totalFiles, doneBytes, totalBytes)
                    })
                    stagedCopies.append((source, dest))
                    try verifyAndRemoveSource(source: source, dest: dest)
                }
                movedDestinations.append((source, dest))
                progress(doneFiles, totalFiles, doneBytes, totalBytes)
            }
        } catch {
            // 取消或失败：跨卷场景已删的源不可逆（已验证），未删的源完好；已写副本保留。
            throw mapError(error)
        }
    }

    private func verifyAndRemoveSource(source: URL, dest: URL) throws {
        let fm = FileManager.default
        let sSize = (try? fm.attributesOfItem(atPath: source.path))?[.size] as? Int64 ?? -1
        let dSize = (try? fm.attributesOfItem(atPath: dest.path))?[.size] as? Int64 ?? -2
        guard sSize == dSize else {
            do { try fm.removeItem(at: dest) }
            catch { logCleanupFailure(error, context: "MoveOperation 验证失败清理") }
            throw OperationError.unexpected("移动验证失败（大小不一致），源文件未删除：\(source.lastPathComponent)")
        }
        try fm.removeItem(at: source)
    }

    private func mapError(_ error: Error) -> Error {
        if let opError = error as? OperationError { return opError }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == ENOSPC {
            return OperationError.writeFailed("磁盘空间不足")
        }
        return OperationError.writeFailed(ns.localizedDescription)
    }

    func undo() throws {
        let fm = FileManager.default
        var failures: [String] = []
        for (source, dest) in movedDestinations.reversed() {
            // 源位置被占用则跳过该项，其余照撤
            if fm.fileExists(atPath: source.path) { continue }
            do { try fm.moveItem(at: dest, to: source) }
            catch { failures.append(dest.lastPathComponent) }
        }
        if !failures.isEmpty {
            throw OperationError.unexpected("撤销移动失败：\(failures.joined(separator: ", "))")
        }
        movedDestinations.removeAll()
    }
}
