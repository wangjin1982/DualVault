import Foundation
import SwiftUI

enum SortKey: String {
    case name, size, modified, kind
}

/// 单栏状态：当前目录、条目、选择、排序、前进/后退历史。
final class PaneState: ObservableObject {
    @Published private(set) var url: URL
    @Published private(set) var items: [FileItem] = []
    @Published var selection: Set<URL> = []
    @Published var editablePath: String
    @Published var cursorItem: URL?   // 空选择回退的光标项（最近一次点击/定位）
    @Published var includeHidden: Bool = false
    @Published var lastError: String?

    private(set) var sortKey: SortKey = .name
    private(set) var sortAscending: Bool = true

    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    /// 最近访问（前往菜单用），新→旧，上限 20。
    private(set) var visitHistory: [URL] = []
    /// 输入即过滤（E1）：按名字包含过滤，空 = 不过滤。
    @Published var filter: String = ""
    /// F2：zip 只读浏览模式。非 nil = 正在浏览该压缩包，zipInner 为包内虚拟路径（根 = ""）。
    @Published private(set) var zipArchive: URL?
    @Published private(set) var zipInner: String = ""
    var isZipBrowsing: Bool { zipArchive != nil }
    /// F3-2：分支视图（拍平子树）。
    @Published var branchMode = false
    /// F3-4：图片缩略图。
    @Published var showThumbnails: Bool {
        didSet { UserDefaults.standard.set(showThumbnails, forKey: "thumbnails.\(sideName)") }
    }
    private let sideName: String
    /// 同步浏览钩子（BrowserModel 注入）：成功进入 target 后回调。
    var navigateHook: ((URL) -> Void)?

    init(url: URL, sideName: String = "") {
        self.url = url.standardizedFileURL
        self.sideName = sideName
        self.showThumbnails = UserDefaults.standard.bool(forKey: "thumbnails.\(sideName)")
        self.editablePath = url.path
        reload()
    }

    // MARK: - 导航

    func navigate(to newURL: URL, pushHistory: Bool = true) {
        var target = newURL.standardizedFileURL
        // F2：zip 浏览模式内的导航（目标仍在压缩包路径下 = 包内移动）
        if let archive = zipArchive, target.path.hasPrefix(archive.path) {
            let inner = String(target.path.dropFirst(archive.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let previous = url
            zipInner = inner
            editablePath = displayPath
            recordVisit(url)
            reload()
            if previous != url { navigateHook?(url) }
            return
        }
        // 走出压缩包：退出 zip 模式，回到正常文件系统导航
        zipArchive = nil
        zipInner = ""
        // 允许输入文件路径时自动跳到其所在目录
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
            // F2：双击/进入 zip = 只读浏览
            if target.pathExtension.lowercased() == "zip" {
                enterZip(target)
                return
            }
            target = target.deletingLastPathComponent()
        }
        guard target != url else { return }
        if pushHistory { backStack.append(url) }
        forwardStack.removeAll()
        let previous = url
        url = target
        editablePath = target.path
        recordVisit(target)
        reload()
        if previous != target { navigateHook?(target) }
    }

    private func recordVisit(_ visited: URL) {
        visitHistory.removeAll { $0 == visited }
        visitHistory.insert(visited, at: 0)
        if visitHistory.count > 20 { visitHistory.removeLast() }
    }

    /// zip 浏览模式下：条目的虚拟路径（相对压缩包，目录带尾斜杠）。
    func virtualPath(for itemURL: URL) -> String {
        guard let archive = zipArchive else { return "" }
        var inner = String(itemURL.path.dropFirst(archive.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let item = items.first(where: { $0.url == itemURL }), item.isDirectory {
            inner += "/"
        }
        return inner
    }

    /// F2：进入 zip 只读浏览。
    func enterZip(_ archive: URL) {
        let previous = url
        zipArchive = archive
        zipInner = ""
        recordVisit(url)
        reload()
        if previous != url { navigateHook?(url) }
    }

    /// zip 模式下的展示路径（虚拟路径）。
    var displayPath: String {
        if let archive = zipArchive {
            return zipInner.isEmpty ? archive.path + "/" : archive.path + "/" + zipInner
        }
        return url.path
    }

    func goUp() {
        // F2：zip 内上级；在包根再上级 = 退出到压缩包所在目录
        if zipArchive != nil {
            if zipInner.isEmpty {
                let containing = zipArchive!.deletingLastPathComponent()
                zipArchive = nil
                navigate(to: containing)
            } else {
                zipInner = zipInner.components(separatedBy: "/").dropLast().joined(separator: "/")
                editablePath = displayPath
                reload()
            }
            return
        }
        let parent = url.deletingLastPathComponent()
        guard parent != url else { return }
        navigate(to: parent)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(url)
        url = previous
        editablePath = previous.path
        reload()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(url)
        url = next
        editablePath = next.path
        reload()
    }

    // MARK: - 加载与排序

    func reload() {
        do {
            // F2：zip 浏览模式
            if let archive = zipArchive {
                items = sortItems(try ZipBrowser.children(of: archive, innerPath: zipInner.isEmpty ? "" : zipInner + "/"))
                editablePath = displayPath
                lastError = nil
                return
            }
            let loaded = try DirectoryLoader.load(url: url, includeHidden: includeHidden)
            items = sortItems(loaded)
            lastError = nil
        } catch ZipEngine.ZipError.encrypted {
            items = []
            lastError = "加密 zip，无法预览内容"
        } catch {
            lastError = "无法读取目录：\(url.path)"
            // 显式失败：保留旧列表，不静默清空
        }
    }

    func toggleHiddenFiles() {
        includeHidden.toggle()
        reload()
    }

    func applySort(key: SortKey, ascending: Bool) {
        sortKey = key
        sortAscending = ascending
        items = sortItems(items)
    }

    /// 目录优先，其余按键排序。
    private func sortItems(_ input: [FileItem]) -> [FileItem] {
        input.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let result: Bool
            switch sortKey {
            case .name: result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size: result = lhs.size < rhs.size
            case .modified: result = lhs.modified < rhs.modified
            case .kind: result = lhs.kind.localizedStandardCompare(rhs.kind) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    // MARK: - 选择辅助（状态栏用）

    var selectedItems: [FileItem] {
        items.filter { selection.contains($0.url) }
    }

    var selectedTotalSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    /// 展示用条目：分支视图（F3-2，拍平）→ 过滤 → 普通列表。
    var displayedItems: [FileItem] {
        let source = branchMode ? BranchFlattener.flatten(root: url, includeHidden: includeHidden) : items
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sortItems(source) }
        return sortItems(source.filter { $0.name.localizedCaseInsensitiveContains(trimmed) })
    }

    /// 磁盘剩余空间（状态栏显示，取不到返回 nil）。
    var freeSpaceString: String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let free = values.volumeAvailableCapacity else { return nil }
        return "可用 \(Theme.sizeString(Int64(free)))"
    }

    /// 磁盘占用比例 0–1（U1 状态栏迷你进度条；取不到返回 nil）。
    var diskUsedRatio: Double? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return min(1, max(0, Double(total - Int(free)) / Double(total)))
    }

    func selectAll() {
        selection = Set(items.map(\.url))
    }
}
