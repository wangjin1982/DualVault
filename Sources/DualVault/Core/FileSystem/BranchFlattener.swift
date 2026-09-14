import Foundation

/// F3-2 分支视图：把目录整棵子树拍平为文件列表（TC 经典 ⌘⇧B）。
/// 返回真实路径的 FileItem（name 为相对路径，url 为真实位置）——
/// 因此视图内选择后 F5/F6 等搬运机制零改动直接可用。
enum BranchFlattener {

    static func flatten(root: URL, includeHidden: Bool) -> [FileItem] {
        var result: [FileItem] = []
        // 根目录自身不作为条目（TC 分支视图不列 "."）
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        for child in children.sorted() {
            walk(root.appendingPathComponent(child), root, includeHidden, &result)
        }
        return result
    }

    private static func walk(_ url: URL, _ root: URL, _ includeHidden: Bool, _ out: inout [FileItem]) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        let name = url.lastPathComponent
        let hidden = name.hasPrefix(".")
        if !isDir.boolValue {
            if hidden && !includeHidden { return }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            out.append(FileItem(url: url, name: name,
                                size: Int64(values?.fileSize ?? 0),
                                modified: values?.contentModificationDate ?? .distantPast,
                                isDirectory: false, isHidden: hidden))
            return
        }
        // 目录本身也作为分支条目出现（TC 风格），但不递归不可读目录
        if hidden && !includeHidden { return }
        out.append(FileItem(url: url, name: name + "/", size: 0, modified: .distantPast,
                            isDirectory: true, isHidden: hidden))
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return }
        for child in children.sorted() {
            walk(url.appendingPathComponent(child), root, includeHidden, &out)
        }
    }

    /// 分支条目展示名 = 相对根的路径。
    static func displayName(for item: FileItem, root: URL) -> String {
        let rel = item.url.path.hasPrefix(root.path)
            ? String(item.url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : item.url.lastPathComponent
        return item.isDirectory ? rel + "/" : rel
    }
}
