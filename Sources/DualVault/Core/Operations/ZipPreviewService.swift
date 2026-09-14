import Foundation

/// F3-1：zip 内 QuickLook 支持——按需把选中条目解压到临时目录预览，用后清理。
/// 临时解压不算文件管理写路径（临时目录 + 用后即清）。
enum ZipPreviewService {

    /// 把 zip 内单条目解压到 tempRoot，返回临时文件 URL（调用方负责 cleanup）。
    static func stage(archive: URL, entry: String, tempRoot: URL) throws -> URL {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let trimmed = entry.hasSuffix("/") ? String(entry.dropLast()) : entry
        let op = ZipExtractOperation(archive: archive, destination: tempRoot,
                                     resolutions: ConflictResolutions(applyToAll: .overwrite),
                                     only: [trimmed])
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        let target = tempRoot.appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: target.path) else {
            cleanup(tempRoot: tempRoot)
            throw OperationError.unexpected("无法提取预览：\(entry)")
        }
        return target
    }

    /// 预览完成后清理临时目录（尽力而为 + 日志）。
    static func cleanup(tempRoot: URL) {
        do { try FileManager.default.removeItem(at: tempRoot) }
        catch { logCleanupFailure(error, context: "ZipPreviewService.cleanup") }
    }

    /// 默认临时根目录。
    static func defaultTempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DualVaultPreview-\(UUID().uuidString)")
    }
}
