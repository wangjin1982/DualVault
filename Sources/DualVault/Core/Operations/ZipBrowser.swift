import Foundation

/// zip 只读浏览：基于 ZipEngine 解析的虚拟目录树（元数据级，不解压到磁盘）。
enum ZipBrowser {

    /// 解析结果缓存：同一 zip 反复导航不重复解析。
    private static var cache: [URL: (entries: [ZipEngine.ZipEntry], loaded: Date)] = [:]

    static func allEntries(of archive: URL) throws -> [ZipEngine.ZipEntry] {
        if let cached = cache[archive], Date().timeIntervalSince(cached.loaded) < 30 {
            return cached.entries
        }
        let entries = try ZipEngine.entries(of: archive)
        cache[archive] = (entries, Date())
        return entries
    }

    /// 某虚拟目录的直接子项。innerPath 形如 "a/b/"（根 = ""）。
    /// 返回的 FileItem.url 为 压缩包路径 + 虚拟路径（仅作标识/展示，非真实文件位置）。
    static func children(of archive: URL, innerPath: String) throws -> [FileItem] {
        let entries = try allEntries(of: archive)
        let prefix = innerPath
        var seen: [String: FileItem] = [:]

        for entry in entries {
            // 目录条目的尾斜杠在 sanitize 时丢失，补回以恢复目录语义
            var sanitized = ZipEngine.sanitize(entry.name) ?? ""
            if entry.isDirectory && !sanitized.hasSuffix("/") { sanitized += "/" }
            guard !sanitized.isEmpty else { continue }
            // 去掉前缀，取第一级
            guard sanitized.hasPrefix(prefix) else { continue }
            let remainder = String(sanitized.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }
            let firstComponent: String
            let isDir: Bool
            if let slash = remainder.firstIndex(of: "/") {
                firstComponent = String(remainder[remainder.startIndex..<slash])
                isDir = true
            } else {
                firstComponent = remainder
                isDir = false
            }
            let childPath = prefix + firstComponent + (isDir ? "/" : "")
            // 目录条目优先取目录自己的元数据，否则合成
            if seen[childPath] == nil || !isDir {
                let fakeURL = archive.appendingPathComponent(childPath)
                let item = FileItem(url: fakeURL, name: firstComponent,
                                    size: isDir ? 0 : Int64(entry.uncompSize),
                                    modified: entry.modified,
                                    isDirectory: isDir,
                                    isHidden: firstComponent.hasPrefix("."))
                seen[childPath] = item
            }
        }
        return seen.values.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 虚拟路径 → zip 条目路径集合（选中目录 = 其下全部条目）。
    static func entryPaths(under archive: URL, virtualPath: String) throws -> [String] {
        let entries = try allEntries(of: archive)
        let target = virtualPath
        return entries.compactMap { entry in
            let sanitized = ZipEngine.sanitize(entry.name)
            guard let name = sanitized else { return nil }
            if name == target || name.hasPrefix(target.hasSuffix("/") ? target : target + "/") {
                return name
            }
            return nil
        }
    }
}
