import Foundation
import Darwin

enum CopyEngineError: Error, Equatable {
    case sourceVanished(String)
    case verifyFailed(String)
}

/// 底层复制引擎：文件按块复制以支持进度与取消；目录递归。
enum CopyEngine {

    static let bufferSize = 1 << 20 // 1MB

    /// 源和目标是否同一卷（同卷移动可用 moveItem 原子完成，跨卷必须 复制+验证+删源）。
    static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        var sa = statfs()
        var sb = statfs()
        guard statfs(a.path, &sa) == 0, statfs(b.path, &sb) == 0 else { return false }
        return sa.f_fsid.val.0 == sb.f_fsid.val.0 && sa.f_fsid.val.1 == sb.f_fsid.val.1
    }

    /// 递归计算总字节数（确认窗"共 X GB"用）。
    static func totalSize(of urls: [URL]) -> Int64 {
        totalSizeDetailed(of: urls).size
    }

    /// 带不可读项统计的版本：skipped > 0 时确认窗加"部分不可读"标注。
    static func totalSizeDetailed(of urls: [URL]) -> (size: Int64, skipped: Int) {
        var total: Int64 = 0
        var skipped = 0
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                    skipped += 1
                    fileOpsLogger.error("totalSize 跳过不可读目录：\(url.path, privacy: .public)")
                    continue
                }
                let sub = totalSizeDetailed(of: children.map { url.appendingPathComponent($0) })
                total += sub.size
                skipped += sub.skipped
            } else {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
                total += size
            }
        }
        return (total, skipped)
    }

    /// 递归统计文件数（进度分母用）。
    static func countFiles(under url: URL) -> Int {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        guard isDir.boolValue else { return 1 }
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return 0 }
        return children.reduce(0) { $0 + countFiles(under: url.appendingPathComponent($1)) }
    }

    /// 复制文件（按块，回报进度，可取消）。取消时清理半成品文件。
    static func copyFile(
        from source: URL, to destination: URL,
        isCancelled: () -> Bool,
        onBytes: (Int64) -> Void
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw CopyEngineError.sourceVanished(source.lastPathComponent)
        }
        if fm.fileExists(atPath: destination.path) {
            do { try fm.removeItem(at: destination) } // 调用方已处理冲突策略，这里保证落点干净
            catch { logCleanupFailure(error, context: "copyFile 落点清理") }
        }
        fm.createFile(atPath: destination.path, contents: nil)
        guard let read = FileHandle(forReadingAtPath: source.path),
              let write = FileHandle(forWritingAtPath: destination.path) else {
            throw OperationError.writeFailed("无法打开文件：\(source.lastPathComponent)")
        }
        defer { try? read.close(); try? write.close() }
        let total = (try? fm.attributesOfItem(atPath: source.path))?[.size] as? Int64 ?? 0
        var written: Int64 = 0
        while written < total {
            if isCancelled() {
                do { try fm.removeItem(at: destination) }
                catch { logCleanupFailure(error, context: "copyFile 取消清理") }
                throw OperationError.cancelled
            }
            let chunk = try read.read(upToCount: bufferSize) ?? Data()
            if chunk.isEmpty { break }
            try write.write(contentsOf: chunk)
            written += Int64(chunk.count)
            onBytes(Int64(chunk.count))
        }
        // 验证大小，防止静默损坏
        let destSize = (try? fm.attributesOfItem(atPath: destination.path))?[.size] as? Int64 ?? -1
        guard destSize == total else {
            do { try fm.removeItem(at: destination) }
            catch { logCleanupFailure(error, context: "copyFile 验证失败清理") }
            throw CopyEngineError.verifyFailed(source.lastPathComponent)
        }
    }

    /// 递归复制目录/文件。返回复制的文件数。
    @discardableResult
    static func copyItem(
        from source: URL, to destination: URL,
        isCancelled: () -> Bool,
        onFile: () -> Void,
        onBytes: (Int64) -> Void
    ) throws -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else {
            throw CopyEngineError.sourceVanished(source.lastPathComponent)
        }
        if !isDir.boolValue {
            try copyFile(from: source, to: destination, isCancelled: isCancelled, onBytes: onBytes)
            onFile()
            return 1
        }
        if isCancelled() { throw OperationError.cancelled }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let children = try? fm.contentsOfDirectory(atPath: source.path) else { return 0 }
        var count = 0
        for child in children {
            count += try copyItem(
                from: source.appendingPathComponent(child),
                to: destination.appendingPathComponent(child),
                isCancelled: isCancelled,
                onFile: onFile,
                onBytes: onBytes)
        }
        return count
    }
}
