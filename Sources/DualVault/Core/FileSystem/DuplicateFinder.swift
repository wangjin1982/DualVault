import Foundation

struct DuplicateGroup: Equatable {
    let size: Int64
    let files: [URL]   // ≥2，排序稳定
}

/// 重复文件查找：先按大小分组，同组再流式 SHA256（F1-B）。
enum DuplicateFinder {

    static func find(in roots: [URL],
                     isCancelled: () -> Bool = { false },
                     progress: @escaping (Int, Int) -> Void = { _, _ in }) throws -> [DuplicateGroup] {
        // 1. 收集全部文件
        var files: [URL] = []
        for root in roots {
            if isCancelled() { throw OperationError.cancelled }
            let tree = try DiffEngine.collectTree(root: root)
            files.append(contentsOf: tree.values.filter { !$0.isDirectory }.map(\.url))
        }
        progress(0, files.count)

        // 2. 按大小分组，只留 ≥2 的组
        var bySize: [Int64: [URL]] = [:]
        for f in files {
            let size = (try? FileManager.default.attributesOfItem(atPath: f.path))?[.size] as? Int64 ?? 0
            bySize[size, default: []].append(f)
        }

        // 3. 同组流式哈希，再按 hash 分组
        var byHash: [String: (size: Int64, files: [URL])] = [:]
        var done = 0
        for (size, group) in bySize where group.count > 1 {
            for url in group {
                if isCancelled() { throw OperationError.cancelled }
                if let hash = try? StreamingHasher.sha256(of: url) {
                    byHash[hash, default: (size, [])].files.append(url)
                }
                done += 1
                progress(done, files.count)
            }
        }

        return byHash.values
            .filter { $0.files.count > 1 }
            .map { DuplicateGroup(size: $0.size, files: $0.files.sorted { $0.path < $1.path }) }
            .sorted { $0.size > $1.size }
    }
}
