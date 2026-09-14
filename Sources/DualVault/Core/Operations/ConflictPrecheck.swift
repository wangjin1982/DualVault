import Foundation

/// 一个冲突条目：目标已存在同名项。
struct ConflictEntry: Equatable {
    let sourceName: String
    let sourceSize: Int64
    let sourceModified: Date
    let destExists: Bool
    let destSize: Int64
    let destModified: Date
}

/// 用户对冲突的决定：每项一个策略，或"应用到全部"。
struct ConflictResolutions: Equatable {
    var perName: [String: ConflictStrategy] = [:]
    var applyToAll: ConflictStrategy?

    func strategy(for name: String) -> ConflictStrategy? {
        // 逐项决策优先于"应用到全部"：先逐项设置的用户意图不被全局覆盖
        perName[name] ?? applyToAll
    }
}

enum ConflictPrecheck {

    /// 扫描计划中哪些源名在目标目录已存在。纯查询，无副作用，可单测。
    static func entries(for plan: TransferPlan) -> [ConflictEntry] {
        let fm = FileManager.default
        let destNames = (try? fm.contentsOfDirectory(atPath: plan.destination.path)) ?? []
        let existing = Set(destNames)
        return plan.sources
            .filter { existing.contains($0.lastPathComponent) }
            .map { source in
                let name = source.lastPathComponent
                let sAttrs = (try? fm.attributesOfItem(atPath: source.path)) ?? [:]
                let dAttrs = (try? fm.attributesOfItem(atPath: plan.destination.appendingPathComponent(name).path)) ?? [:]
                return ConflictEntry(
                    sourceName: name,
                    sourceSize: sAttrs[.size] as? Int64 ?? 0,
                    sourceModified: sAttrs[.modificationDate] as? Date ?? .distantPast,
                    destExists: true,
                    destSize: dAttrs[.size] as? Int64 ?? 0,
                    destModified: dAttrs[.modificationDate] as? Date ?? .distantPast)
            }
    }

    /// 应用决议得到最终目标名；返回 nil 表示该项跳过。目录内无同名时原样返回。
    static func destinationName(for sourceName: String, in plan: TransferPlan, resolutions: ConflictResolutions) -> String? {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: plan.destination.path)) ?? [])
        let strategy = resolutions.strategy(for: sourceName) ?? .keepBoth // 默认保留两者，不丢数据
        return ConflictResolver.resolvedName(for: sourceName, strategy: strategy, existingNames: existing)
    }
}
