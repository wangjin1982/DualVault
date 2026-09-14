import Foundation

enum CompareMode: String, CaseIterable {
    case name = "仅名称", nameSize = "名称+大小", content = "名称+大小+内容"
}

enum DiffStatus: String, Equatable {
    case onlyInLeft = "仅左侧有"
    case onlyInRight = "仅右侧有"
    case different = "双侧不同"
    case same = "相同"
}

struct DiffEntry: Equatable {
    let relativePath: String
    let status: DiffStatus
    let leftSize: Int64
    let rightSize: Int64
}

/// 目录树比较（纯逻辑，可单测）。relativePath 用 "/" 分隔，目录以 "/" 结尾。
enum DiffEngine {

    static func compare(left: URL, right: URL, mode: CompareMode,
                        isCancelled: () -> Bool = { false },
                        onProgress: (Int, Int) -> Void = { _, _ in }) throws -> [DiffEntry] {
        let leftMap = try collectTree(root: left)
        let rightMap = try collectTree(root: right)
        var entries: [DiffEntry] = []
        let allPaths = Set(leftMap.keys).union(rightMap.keys).sorted()

        for (index, path) in allPaths.enumerated() {
            if isCancelled() { throw OperationError.cancelled }
            onProgress(index + 1, allPaths.count)
            let l = leftMap[path]
            let r = rightMap[path]
            let status: DiffStatus
            switch (l, r) {
            case (.some, .none): status = .onlyInLeft
            case (.none, .some): status = .onlyInRight
            case let (.some(a), .some(b)):
                if a.isDirectory != b.isDirectory {
                    status = .different
                } else if a.isDirectory {
                    status = .same
                } else {
                    status = filesEqual(a.url, b.url, sizeA: a.size, sizeB: b.size, mode: mode) ? .same : .different
                }
            default: status = .same
            }
            if status != .same || path.hasSuffix("/") == false {
                entries.append(DiffEntry(relativePath: path, status: status,
                                         leftSize: l?.size ?? 0, rightSize: r?.size ?? 0))
            }
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private static func filesEqual(_ a: URL, _ b: URL, sizeA: Int64, sizeB: Int64, mode: CompareMode) -> Bool {
        switch mode {
        case .name:
            return true // 名称模式只关心存在性
        case .nameSize:
            return sizeA == sizeB
        case .content:
            guard sizeA == sizeB else { return false }
            guard let ha = try? StreamingHasher.sha256(of: a),
                  let hb = try? StreamingHasher.sha256(of: b) else { return false }
            return ha == hb
        }
    }

    struct TreeItem {
        let url: URL
        let isDirectory: Bool
        let size: Int64
    }

    /// 收集整棵树为 相对路径 → 条目（目录条目以 / 结尾）。
    static func collectTree(root: URL) throws -> [String: TreeItem] {
        var result: [String: TreeItem] = [:]
        func walk(_ url: URL, _ relative: String) throws {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
            let item = TreeItem(url: url, isDirectory: isDir.boolValue, size: size)
            let key = relative.isEmpty ? url.lastPathComponent + (isDir.boolValue ? "/" : "")
                                       : relative + (isDir.boolValue ? "/" : "")
            result[key] = item
            if isDir.boolValue {
                guard let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return }
                for child in children.sorted() {
                    try walk(url.appendingPathComponent(child),
                             relative.isEmpty ? child : relative + "/" + child)
                }
            }
        }
        try walk(root, "")
        return result
    }
}
