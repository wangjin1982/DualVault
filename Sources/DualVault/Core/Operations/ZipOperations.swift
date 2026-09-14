import Foundation

/// 压缩操作（⌘K）：选中项压为同目录 名称.zip。undo = 废纸篓回收该 zip。
final class ZipCompressOperation: FileOperation {
    let sources: [URL]
    let destination: URL
    private let trash: TrashBackend
    private(set) var createdArchive: URL?

    init(sources: [URL], destination: URL, trash: TrashBackend = FileManagerTrashBackend()) {
        self.sources = sources
        self.destination = destination
        self.trash = trash
    }

    var title: String { "压缩 \(sources.count) 项为 \(destination.lastPathComponent)" }

    func execute(isCancelled: () -> Bool, progress: (Int, Int, Int64, Int64) -> Void) throws {
        try ZipEngine.zip(sources, to: destination, isCancelled: isCancelled)
        createdArchive = destination
        progress(1, 1, 0, 0)
    }

    func undo() throws {
        guard let url = createdArchive else { return }
        do { try trash.trash(url) } catch {
            throw OperationError.unexpected("撤销压缩失败：\(url.lastPathComponent)")
        }
        createdArchive = nil
    }
}

/// 解压操作（⌘⇧K）：zip 解到当前目录，冲突经 ConflictResolver 命名。undo = 废纸篓回收解压产物。
final class ZipExtractOperation: FileOperation {
    let archive: URL
    let destination: URL
    private let resolutions: ConflictResolutions
    private let trash: TrashBackend
    /// F2：只解压这些条目路径（nil = 全部）。
    private let only: Set<String>?
    private(set) var written: [URL] = []

    init(archive: URL, destination: URL, resolutions: ConflictResolutions,
         only: Set<String>? = nil,
         trash: TrashBackend = FileManagerTrashBackend()) {
        self.archive = archive
        self.destination = destination
        self.resolutions = resolutions
        self.only = only
        self.trash = trash
    }

    var title: String {
        only == nil ? "解压 \(archive.lastPathComponent)" : "从 \(archive.lastPathComponent) 提取 \(only!.count) 项"
    }

    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws {
        let filter = only.map { Set($0.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }) }
        func selected(_ name: String) -> Bool {
            let trimmed = name.hasSuffix("/") ? String(name.dropLast()) : name
            return filter?.contains(trimmed) ?? true
        }
        let entries = try ZipEngine.entries(of: archive).filter { selected($0.name) }
        try ZipEngine.unzip(archive, to: destination, isCancelled: isCancelled) { name in
            let trimmed = name.hasSuffix("/") ? String(name.dropLast()) : name
            // 选中过滤：未选中且非选中项祖先目录的条目一律跳过
            if let filter = filter, !filter.contains(trimmed) {
                let isAncestor = filter.contains { trimmed.hasPrefix($0 + "/") }
                if !isAncestor { return nil }
                return name
            }
            let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: self.destination.path)) ?? [])
            let resolved = ConflictResolver.resolvedName(for: name, strategy: self.resolutions.strategy(for: name) ?? .keepBoth, existingNames: existing)
            if let r = resolved, !r.isEmpty { self.written.append(self.destination.appendingPathComponent(r)) }
            return resolved
        }
        progress(entries.count, entries.count, 0, 0)
    }

    func undo() throws {
        var failures: [String] = []
        for url in written.reversed() {
            do { try trash.trash(url) } catch { failures.append(url.lastPathComponent) }
        }
        written.removeAll()
        if !failures.isEmpty {
            throw OperationError.unexpected("撤销解压失败：\(failures.joined(separator: ", "))")
        }
    }
}

/// 解压前的冲突预检：扫描 zip 条目与目标目录同名项。only = 只看选中条目（F2 zip 提取）。
enum ZipConflictPrecheck {
    static func entries(archive: URL, destination: URL, only: Set<String>? = nil) -> [ConflictEntry] {
        let fm = FileManager.default
        let destNames = Set((try? fm.contentsOfDirectory(atPath: destination.path)) ?? [])
        return (try? ZipEngine.entries(of: archive))?
            .filter { entry in
                guard !entry.isDirectory else { return false }
                guard let only = only else { return true }
                let trimmed = entry.name.hasSuffix("/") ? String(entry.name.dropLast()) : entry.name
                return only.contains(trimmed) || only.contains { $0.hasPrefix(trimmed + "/") }
            }
            .filter { destNames.contains($0.name) }
            .map { entry in
                let dAttrs = (try? fm.attributesOfItem(atPath: destination.appendingPathComponent(entry.name).path)) ?? [:]
                return ConflictEntry(
                    sourceName: entry.name,
                    sourceSize: Int64(entry.uncompSize),
                    sourceModified: entry.modified,
                    destExists: true,
                    destSize: dAttrs[.size] as? Int64 ?? 0,
                    destModified: dAttrs[.modificationDate] as? Date ?? .distantPast)
            } ?? []
    }
}
