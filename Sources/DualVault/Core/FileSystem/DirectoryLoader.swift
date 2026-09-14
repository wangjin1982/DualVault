import Foundation

enum DirectoryLoaderError: Error, Equatable {
    case notADirectory(URL)
    case unreadable(URL)
}

/// 目录枚举器：纯逻辑，可单测。目录不可读时抛错（显式失败，不静默）。
enum DirectoryLoader {

    /// 枚举目录内容。includeHidden=false 时过滤以 "." 开头的条目。
    /// 用 resourceValues 一次取齐属性，避免逐文件 stat（10 万文件目录的性能关键）。
    static func load(url: URL, includeHidden: Bool = false) throws -> [FileItem] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw DirectoryLoaderError.notADirectory(url)
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)
        } catch {
            throw DirectoryLoaderError.unreadable(url)
        }
        var items: [FileItem] = []
        items.reserveCapacity(urls.count)
        for child in urls {
            let values = try? child.resourceValues(forKeys: Set(keys))
            let item = FileItem(url: child, values: values)
            if item.isHidden && !includeHidden { continue }
            items.append(item)
        }
        return items
    }
}
