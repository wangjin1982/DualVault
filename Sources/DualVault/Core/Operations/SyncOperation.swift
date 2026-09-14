import Foundation

enum SyncMode: String, CaseIterable {
    case copyNewToRight = "补齐右侧（左→右）"
    case copyNewBothWays = "双向补齐"
    case mirrorLeftToRight = "镜像（右侧 = 左侧）"
}

struct SyncAction: Equatable {
    enum Kind: String, Equatable {
        case copyToRight, copyToLeft, trashOnRight
    }
    let kind: Kind
    let source: URL        // copy 的源（trash 时为待删文件）
    let destination: URL   // copy 的目标完整路径
    let relativePath: String
}

/// 从差异列表生成同步计划（纯逻辑，可单测；干跑预览与实际执行共用同一份计划）。
enum SyncPlan {

    /// 目标完整路径 = 对侧根 + 相对路径。
    static func make(entries: [DiffEntry], mode: SyncMode, leftRoot: URL, rightRoot: URL) -> [SyncAction] {
        var actions: [SyncAction] = []
        for entry in entries {
            let rel = entry.relativePath
            guard !rel.hasSuffix("/") else { continue } // 目录本身由文件操作隐式创建/随文件处理
            let leftURL = leftRoot.appendingPathComponent(rel)
            let rightURL = rightRoot.appendingPathComponent(rel)
            switch entry.status {
            case .onlyInLeft:
                actions.append(SyncAction(kind: .copyToRight, source: leftURL, destination: rightURL, relativePath: rel))
            case .onlyInRight:
                if mode == .copyNewBothWays {
                    actions.append(SyncAction(kind: .copyToLeft, source: rightURL, destination: leftURL, relativePath: rel))
                } else if mode == .mirrorLeftToRight {
                    actions.append(SyncAction(kind: .trashOnRight, source: rightURL, destination: rightURL, relativePath: rel))
                }
                // copyNewToRight：右侧多出的不处理
            case .different:
                if mode != .copyNewBothWays {
                    // 以左侧为准同步到右侧；双向模式下"双侧不同"无明确方向，跳过
                    actions.append(SyncAction(kind: .copyToRight, source: leftURL, destination: rightURL, relativePath: rel))
                }
            case .same:
                break
            }
        }
        return actions.sorted { $0.relativePath < $1.relativePath }
    }
}

/// 同步执行器：唯一允许的"按计划批量写两侧"路径（F1 红线：不得绕过 Operation 体系）。
/// 复制走 CopyEngine；镜像删除走 TrashBackend（可撤销）。取消时清理本次已复制的半成品。
final class SyncOperation: FileOperation {
    let actions: [SyncAction]
    private let trash: TrashBackend
    private(set) var copied: [URL] = []        // undo = trash 这些
    private(set) var trashed: [(original: URL, landed: URL)] = [] // undo = 移回

    init(actions: [SyncAction], trash: TrashBackend = FileManagerTrashBackend()) {
        self.actions = actions
        self.trash = trash
    }

    var title: String { "同步 \(actions.count) 个动作" }

    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws {
        let total = actions.count
        for (index, action) in actions.enumerated() {
            if isCancelled() {
                cleanupPartial()
                throw OperationError.cancelled
            }
            switch action.kind {
            case .copyToRight, .copyToLeft:
                // 覆盖前先把目标旧文件移入废纸篓——undo 时能还原"被覆盖前的右侧"，而非只删副本
                if FileManager.default.fileExists(atPath: action.destination.path) {
                    let landed = try trash.trash(action.destination)
                    trashed.append((original: action.destination, landed: landed))
                }
                try FileManager.default.createDirectory(at: action.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try CopyEngine.copyItem(from: action.source, to: action.destination,
                                        isCancelled: isCancelled, onFile: {}, onBytes: { _ in })
                copied.append(action.destination)
            case .trashOnRight:
                let landed = try trash.trash(action.source)
                trashed.append((original: action.source, landed: landed))
            }
            progress(index + 1, total, 0, 0)
        }
    }

    private func cleanupPartial() {
        let fm = FileManager.default
        for url in copied {
            do { try fm.removeItem(at: url) }
            catch { logCleanupFailure(error, context: "SyncOperation 取消清理") }
        }
        copied.removeAll()
    }

    func undo() throws {
        let fm = FileManager.default
        var failures: [String] = []
        let restored = Set(trashed.map(\.original))
        // 1. 给待还原的原文件腾路：把占着同一路径的副本先移走
        for url in copied where restored.contains(url) {
            guard fm.fileExists(atPath: url.path) else { continue }
            do { try fm.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(".dualvault-undo-\(url.lastPathComponent)")) }
            catch { failures.append(url.lastPathComponent) }
        }
        // 2. 还原被覆盖/被删的对侧原文件（恢复"同步前的对侧"）
        for (original, landed) in trashed.reversed() {
            guard !fm.fileExists(atPath: original.path) else { continue }
            do { try fm.moveItem(at: landed, to: original) }
            catch { failures.append(original.lastPathComponent) }
        }
        // 3. 撤掉本次新建产生的副本（同路径副本在第 1 步已改名，这里清掉）
        for url in copied.reversed() {
            let staged = url.deletingLastPathComponent().appendingPathComponent(".dualvault-undo-\(url.lastPathComponent)")
            let target = fm.fileExists(atPath: staged.path) ? staged : url
            guard fm.fileExists(atPath: target.path) else { continue }
            do { _ = try trash.trash(target) } catch { failures.append(url.lastPathComponent) }
        }
        trashed.removeAll()
        copied.removeAll()
        if !failures.isEmpty {
            throw OperationError.unexpected("撤销同步失败：\(failures.joined(separator: ", "))")
        }
    }
}
