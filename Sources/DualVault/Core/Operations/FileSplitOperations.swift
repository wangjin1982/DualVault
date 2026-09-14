import Foundation

/// F3-5：文件分割/合并 + 修改日期。本单唯一新增写路径，走 OperationQueue。
enum FileSplitter {

    /// 把 file 按 partSize 分割为 名称.part1、名称.part2…（同目录），返回 parts。
    static func split(_ file: URL, partSize: Int64, isCancelled: () -> Bool) throws -> [URL] {
        guard partSize > 0 else { throw OperationError.unexpected("分割大小必须大于 0") }
        let fm = FileManager.default
        let total = (try fm.attributesOfItem(atPath: file.path))[.size] as? Int64 ?? 0
        guard let read = FileHandle(forReadingAtPath: file.path) else {
            throw OperationError.writeFailed("无法读取：\(file.lastPathComponent)")
        }
        defer { try? read.close() }

        var parts: [URL] = []
        var index = 1
        var remaining = total
        while remaining > 0 {
            if isCancelled() { throw OperationError.cancelled }
            let chunk = try read.read(upToCount: Int(min(partSize, remaining))) ?? Data()
            if chunk.isEmpty { break }
            let part = file.appendingPathExtension("part\(index)")
            try chunk.write(to: part)
            parts.append(part)
            remaining -= Int64(chunk.count)
            index += 1
        }
        return parts
    }

    /// 按 partN 顺序合并 parts 到 destination；校验总大小一致。
    static func join(parts: [URL], to destination: URL, isCancelled: () -> Bool) throws {
        let fm = FileManager.default
        let ordered = parts.sorted { partNumber($0) < partNumber($1) }
        let total = ordered.reduce(Int64(0)) {
            $0 + ((try? fm.attributesOfItem(atPath: $1.path))?[.size] as? Int64 ?? 0)
        }
        fm.createFile(atPath: destination.path, contents: nil)
        guard let write = FileHandle(forWritingAtPath: destination.path) else {
            throw OperationError.writeFailed("无法写入：\(destination.lastPathComponent)")
        }
        defer { try? write.close() }
        var written: Int64 = 0
        for part in ordered {
            if isCancelled() {
                try? fm.removeItem(at: destination)
                throw OperationError.cancelled
            }
            guard let data = try? Data(contentsOf: part) else { continue }
            try write.write(contentsOf: data)
            written += Int64(data.count)
        }
        guard written == total else {
            try? fm.removeItem(at: destination)
            throw OperationError.unexpected("合并大小校验失败（\\(written) ≠ \\(total)）")
        }
    }

    static func partNumber(_ url: URL) -> Int {
        let ext = url.pathExtension          // "part3"
        return Int(ext.dropFirst(4)) ?? 0
    }
}

/// 分割操作：undo = 废纸篓回收各 part。
final class SplitOperation: FileOperation {
    let file: URL
    let partSize: Int64
    private let trash: TrashBackend
    private(set) var parts: [URL] = []

    init(file: URL, partSize: Int64, trash: TrashBackend = FileManagerTrashBackend()) {
        self.file = file
        self.partSize = partSize
        self.trash = trash
    }

    var title: String { "分割 \\(file.lastPathComponent)" }

    func execute(isCancelled: () -> Bool, progress: (Int, Int, Int64, Int64) -> Void) throws {
        parts = try FileSplitter.split(file, partSize: partSize, isCancelled: isCancelled)
        progress(1, 1, 0, 0)
    }

    func undo() throws {
        var failures: [String] = []
        for part in parts {
            do { _ = try trash.trash(part) } catch { failures.append(part.lastPathComponent) }
        }
        parts.removeAll()
        if !failures.isEmpty {
            throw OperationError.unexpected("撤销分割失败：\(failures.joined(separator: ", "))")
        }
    }
}

/// 合并操作：成功后 parts 进废纸篓（undo = 还原 parts + 回收合并产物）。
/// F4：产物名冲突走既有 ConflictResolver 体系（收口唯一绕过冲突的写路径）。
final class JoinOperation: FileOperation {
    let parts: [URL]
    let destination: URL
    private let resolutions: ConflictResolutions
    private let trash: TrashBackend
    private(set) var trashedParts: [(original: URL, landed: URL)] = []
    private(set) var overwritten: (original: URL, landed: URL)?
    private(set) var produced: URL?

    init(parts: [URL], destination: URL,
         resolutions: ConflictResolutions = ConflictResolutions(),
         trash: TrashBackend = FileManagerTrashBackend()) {
        self.parts = parts
        self.destination = destination
        self.resolutions = resolutions
        self.trash = trash
    }

    var title: String { "合并 \(parts.count) 个分卷为 \(destination.lastPathComponent)" }

    /// 冲突决议后的实际产物路径（纯计算，可单测）。
    static func resolvedDestination(_ destination: URL, existingNames: Set<String>, resolutions: ConflictResolutions) -> URL? {
        let name = destination.lastPathComponent
        guard let resolved = ConflictResolver.resolvedName(for: name, strategy: resolutions.strategy(for: name) ?? .keepBoth, existingNames: existingNames) else {
            return nil // 用户选择跳过
        }
        return destination.deletingLastPathComponent().appendingPathComponent(resolved)
    }

    func execute(isCancelled: () -> Bool, progress: (Int, Int, Int64, Int64) -> Void) throws {
        let fm = FileManager.default
        let dirNames = Set((try? fm.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)) ?? [])
        guard let target = Self.resolvedDestination(destination, existingNames: dirNames, resolutions: resolutions) else {
            throw OperationError.cancelled // 用户选择跳过
        }
        // overwrite：先把已存在的产物移入废纸篓（undo 可还原）
        if target.path == destination.path, fm.fileExists(atPath: target.path) {
            let landed = try trash.trash(target)
            overwritten = (original: target, landed: landed)
        }
        try FileSplitter.join(parts: parts, to: target, isCancelled: isCancelled)
        produced = target
        for part in parts {
            let landed = try trash.trash(part)
            trashedParts.append((original: part, landed: landed))
        }
        progress(1, 1, 0, 0)
    }

    func undo() throws {
        let fm = FileManager.default
        var failures: [String] = []
        // 1. 回收合并产物
        if let produced = produced, fm.fileExists(atPath: produced.path) {
            do { _ = try trash.trash(produced) } catch { failures.append(produced.lastPathComponent) }
        }
        // 2. 还原被覆盖的旧产物
        if let overwritten = overwritten, !fm.fileExists(atPath: overwritten.original.path) {
            do { try fm.moveItem(at: overwritten.landed, to: overwritten.original) }
            catch { failures.append(overwritten.original.lastPathComponent) }
        }
        // 3. 还原 parts
        for (original, landed) in trashedParts.reversed() {
            guard !fm.fileExists(atPath: original.path) else { continue }
            do { try fm.moveItem(at: landed, to: original) }
            catch { failures.append(original.lastPathComponent) }
        }
        trashedParts.removeAll()
        produced = nil
        overwritten = nil
        if !failures.isEmpty {
            throw OperationError.unexpected("撤销合并失败：\(failures.joined(separator: ", "))")
        }
    }
}

/// touch 修改日期：undo = 恢复原日期。
final class SetDateOperation: FileOperation {
    let target: URL
    let newDate: Date
    private(set) var oldDate: Date?

    init(target: URL, newDate: Date) {
        self.target = target
        self.newDate = newDate
    }

    var title: String { "修改日期 \\(target.lastPathComponent)" }

    func execute(isCancelled: () -> Bool, progress: (Int, Int, Int64, Int64) -> Void) throws {
        let fm = FileManager.default
        oldDate = (try? fm.attributesOfItem(atPath: target.path))?[.modificationDate] as? Date
        do {
            try fm.setAttributes([.modificationDate: newDate], ofItemAtPath: target.path)
        } catch {
            throw OperationError.writeFailed("无法修改日期：\\(error.localizedDescription)")
        }
        progress(1, 1, 0, 0)
    }

    func undo() throws {
        guard let oldDate = oldDate else { return }
        try? FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: target.path)
        self.oldDate = nil
    }
}
