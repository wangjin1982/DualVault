import Foundation

/// 大小写转换。
enum CaseTransform: String, Codable, CaseIterable {
    case none, upper, lower, capitalized

    func apply(_ s: String) -> String {
        switch self {
        case .none: return s
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .capitalized: return s.capitalized
        }
    }
}

/// 批量重命名规则。
struct RenameRules: Equatable {
    var find: String = ""
    var replace: String = ""
    var prefix: String = ""
    var suffix: String = ""
    /// 序号模板：{name} = 当前基础名，{N} = 序号（如 "照片 ({N})"）。空 = 不启用模板。
    var template: String = ""
    var startNumber: Int = 1
    var caseTransform: CaseTransform = .none
    /// F3：find 按正则解释（NSRegularExpression，replace 支持 $1 捕获组）。
    var useRegex = false
    /// F3：true = 扩展名不参与变换（默认）；false = 全名参与。
    var preserveExtension = true

    /// F3：正则合法性检查；nil = 合法。
    func regexError() -> String? {
        guard useRegex, !find.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: find)
            return nil
        } catch {
            return "非法正则：\(error.localizedDescription)"
        }
    }
}

/// 一条重命名计划：原名 → 新名，conflict 标记（与现有名或彼此冲突）。
struct RenamePlanEntry: Equatable {
    let original: String
    let renamed: String
    let conflict: Bool
}

enum BatchRename {

    /// 生成重命名计划（纯函数，可单测）。F3：useRegex 时正则非法会抛错。
    /// - Parameter existingNames: 目标目录中除本次涉及文件外的现有名（冲突检测用）。
    static func plan(names: [String], rules: RenameRules, existingNames: Set<String>) throws -> [RenamePlanEntry] {
        if let error = rules.regexError() {
            throw OperationError.unexpected(error)
        }
        var seen: [String: Int] = [:]   // 新名 → 出现次数（互相冲突检测）
        var entries: [RenamePlanEntry] = []

        for (index, original) in names.enumerated() {
            let renamed = try newName(for: original, rules: rules, index: index)
            var conflict = false
            if renamed != original {
                if existingNames.contains(renamed) { conflict = true }
                if seen[renamed, default: 0] > 0 { conflict = true }
            }
            seen[renamed, default: 0] += 1
            entries.append(RenamePlanEntry(original: original, renamed: renamed, conflict: conflict))
        }
        return entries
    }

    /// 单名变换：大小写 → 查找替换（字面量或正则）→ 模板 → 前后缀。
    /// preserveExtension（默认 true）时扩展名永不参与变换。
    static func newName(for original: String, rules: RenameRules, index: Int) throws -> String {
        var base = original
        var ext = ""
        if rules.preserveExtension, let dot = original.lastIndex(of: "."), dot != original.startIndex {
            base = String(original[original.startIndex..<dot])
            ext = String(original[dot...])
        }
        base = rules.caseTransform.apply(base)
        if !rules.find.isEmpty {
            if rules.useRegex {
                let regex = try NSRegularExpression(pattern: rules.find)
                let range = NSRange(base.startIndex..., in: base)
                base = regex.stringByReplacingMatches(in: base, range: range, withTemplate: rules.replace)
            } else {
                base = base.replacingOccurrences(of: rules.find, with: rules.replace)
            }
        }
        if !rules.template.isEmpty {
            let number = rules.startNumber + index
            base = rules.template
                .replacingOccurrences(of: "{name}", with: base)
                .replacingOccurrences(of: "{N}", with: String(number))
        }
        return rules.prefix + base + rules.suffix + ext
    }

    /// 计划是否包含实际变更（无变更时 UI 禁用应用按钮）。
    static func hasChanges(_ entries: [RenamePlanEntry]) -> Bool {
        entries.contains { $0.original != $0.renamed }
    }

    /// 计划中是否有冲突。
    static func hasConflicts(_ entries: [RenamePlanEntry]) -> Bool {
        entries.contains { $0.conflict }
    }
}
