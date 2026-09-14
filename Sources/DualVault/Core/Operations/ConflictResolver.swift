import Foundation

enum ConflictStrategy: Equatable {
    case overwrite   // 覆盖目标
    case skip        // 跳过该项
    case keepBoth    // 保留两者：自动加 " 副本" 后缀
}

enum ConflictResolver {

    /// 根据策略给出目标文件名；返回 nil 表示该项应被跳过。
    static func resolvedName(
        for sourceName: String,
        strategy: ConflictStrategy,
        existingNames: Set<String>
    ) -> String? {
        guard existingNames.contains(sourceName) else { return sourceName }
        switch strategy {
        case .overwrite:
            return sourceName
        case .skip:
            return nil
        case .keepBoth:
            return uniqueCopyName(for: sourceName, in: existingNames)
        }
    }

    /// "报告.pdf" → "报告 副本.pdf" → "报告 副本 2.pdf" → ...
    /// 目录名同理："资料" → "资料 副本"。
    static func uniqueCopyName(for name: String, in existing: Set<String>) -> String {
        let base: String
        let ext: String
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            base = String(name[name.startIndex..<dot])
            ext = String(name[dot...])
        } else {
            base = name
            ext = ""
        }
        var candidate = "\(base) 副本\(ext)"
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(base) 副本 \(counter)\(ext)"
            counter += 1
        }
        return candidate
    }
}
