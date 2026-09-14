import AppKit
import Foundation
import SwiftUI

/// 待确认的传输草稿。
struct TransferDraft {
    let kind: TransferKind
    let plan: TransferPlan
    let totalBytes: Int64
    let totalFiles: Int
    /// 补充提示（如"部分目录不可读"）。
    let note: String?
    /// F2：zip 提取源（非 nil = 从 zip 复制出，而非文件系统互传）。
    let zipSource: (archive: URL, entries: Set<String>)?

    var directionArrow: String {
        plan.sourcePane == .left ? "→" : "←"
    }
}

/// 冲突会话：条目 + 完成回调（传输与解压共用）。
struct ConflictSession {
    let entries: [ConflictEntry]
    let onResolve: (ConflictResolutions) -> Void
}

/// 当前弹出的工作表。
enum ActiveSheet: Identifiable {
    case confirm(TransferDraft)
    case conflict(ConflictSession)
    case newFolder(PaneSide)
    case progress(String)
    case rename([FileItem])            // E1-3 批量重命名
    case wildcard                       // E1-2 通配符选择
    case checksum(URL)                  // E1-5 校验和
    case hotlist                        // E1-6 目录热列表
    case compare                        // F1-A 比较与同步
    case duplicates                     // F1-B 重复文件查找
    case uninstall                      // F2-B App 卸载器
    case split(URL)                     // F3-5 分割文件
    case touch(URL)                     // F3-5 修改日期

    var id: String {
        switch self {
        case .confirm: return "confirm"
        case .conflict: return "conflict"
        case .newFolder: return "newfolder"
        case .progress: return "progress"
        case .rename: return "rename"
        case .wildcard: return "wildcard"
        case .checksum: return "checksum"
        case .hotlist: return "hotlist"
        case .compare: return "compare"
        case .duplicates: return "duplicates"
        case .uninstall: return "uninstall"
        case .split: return "split"
        case .touch: return "touch"
        }
    }
}

/// 窗口级指挥中心：双栏标签组、焦点、对话框流转、操作队列、撤销栈、快捷键分发。
final class BrowserModel: ObservableObject {
    @Published var leftGroup: PaneGroupModel
    @Published var rightGroup: PaneGroupModel
    @Published var focusedSide: PaneSide = .left
    @Published var activeSheet: ActiveSheet?
    @Published var alertMessage: String?

    let queue = OperationQueue()
    private var undoStack: [FileOperation] = []

    /// E1-7 同步浏览开关。
    @Published var syncBrowse = false {
        didSet { UserDefaults.standard.set(syncBrowse, forKey: "syncBrowse") }
    }
    /// E1 文件夹大小计算结果（状态栏展示）。
    @Published var folderSizeResult: String?
    /// E1 ⌘⇧0 均分栏宽回调（MainWindowView 注入）。
    var equalizeHandler: (() -> Void)?
    private var folderSizeWork: DispatchWorkItem?

    init() {
        let fm = FileManager.default
        leftGroup = PaneGroupModel(side: .left, initialURL: fm.homeDirectoryForCurrentUser)
        rightGroup = PaneGroupModel(side: .right, initialURL: fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
        syncBrowse = UserDefaults.standard.bool(forKey: "syncBrowse")
        installSyncHooks()
    }

    // MARK: - E1-7 同步浏览

    private func installSyncHooks() {
        for group in [leftGroup, rightGroup] {
            group.onTabCreated = { [weak self] pane in
                guard let self = self else { return }
                let side = group.side
                pane.navigateHook = { [weak self] target in
                    self?.syncFollow(side: side, target: target)
                }
            }
            for tab in group.tabs { group.onTabCreated?(tab.state) }
        }
    }

    /// 一侧进入子目录时，另一侧尝试进入同名子目录（不存在则不动）。
    private func syncFollow(side: PaneSide, target: URL) {
        guard syncBrowse, !queue.isRunning else { return }
        let source = side == .left ? leftGroup.selectedPane : rightGroup.selectedPane
        let other = side == .left ? rightGroup.selectedPane : leftGroup.selectedPane
        guard target.deletingLastPathComponent() == source.url else { return } // 仅"进入子目录"
        let candidate = other.url.appendingPathComponent(target.lastPathComponent)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue,
              candidate != other.url else { return }
        other.navigate(to: candidate)
    }

    var focusedGroup: PaneGroupModel { focusedSide == .left ? leftGroup : rightGroup }
    var otherGroup: PaneGroupModel { focusedSide == .left ? rightGroup : leftGroup }
    var focusedPane: PaneState { focusedGroup.selectedPane }
    var otherPane: PaneState { otherGroup.selectedPane }

    // MARK: - 标签页（⌘T / ⌘W）

    func newTab() { focusedGroup.newTab() }

    /// U1.1 侧栏：在指定栏以给定目录新开标签并切换。
    func newTab(in side: PaneSide, at url: URL) {
        let group = side == .left ? leftGroup : rightGroup
        group.newTab()
        group.selectedPane.navigate(to: url)
        focusedSide = side
    }

    func closeTab(in group: PaneGroupModel, id: UUID) {
        if !group.closeTab(id: id) {
            alertMessage = "最后一个标签不可关闭"
        }
    }

    // MARK: - 传输（F5/F6 + 中央按钮的唯一入口）

    /// 方向感知传输：焦点栏 → 对侧栏。空选择回退光标项。F2：zip 内只允许复制出。
    func requestTransfer(kind: TransferKind) {
        guard !queue.isRunning else { return }
        // F2：zip 只读浏览模式
        if let archive = focusedPane.zipArchive {
            guard kind == .copy else {
                alertMessage = "zip 内为只读，只能复制出文件"
                return
            }
            let selection = effectiveSelection()
            guard !selection.isEmpty, let archive = focusedPane.zipArchive else { return }
            var entries: Set<String> = []
            for item in selection {
                let inner = focusedPane.virtualPath(for: item)
                if let paths = try? ZipBrowser.entryPaths(under: archive, virtualPath: inner) {
                    entries.formUnion(paths)
                }
            }
            guard !entries.isEmpty else { return }
            let draft = TransferDraft(
                kind: .copy,
                plan: TransferPlanner.plan(from: focusedSide, kind: .copy, selection: selection, to: otherPane.url),
                totalBytes: 0, totalFiles: entries.count,
                note: "将从压缩包提取 \(entries.count) 个条目",
                zipSource: (archive, entries))
            activeSheet = .confirm(draft)
            return
        }
        let selection = effectiveSelection()
        let plan = TransferPlanner.plan(
            from: focusedSide, kind: kind,
            selection: selection, to: otherPane.url)
        guard !plan.isEmpty else { return }
        let sized = CopyEngine.totalSizeDetailed(of: selection)
        let draft = TransferDraft(
            kind: kind, plan: plan,
            totalBytes: sized.size,
            totalFiles: selection.reduce(0) { $0 + CopyEngine.countFiles(under: $1) },
            note: sized.skipped > 0 ? "部分目录不可读，总大小为已统计部分" : nil,
            zipSource: nil)
        activeSheet = .confirm(draft)
    }

    private func effectiveSelection() -> [URL] {
        SelectionFallback.effectiveSelection(
            selection: focusedPane.selectedItems.map(\.url),
            cursor: focusedPane.cursorItem)
    }

    /// 确认窗确认后：先查冲突，有冲突进冲突对话框，无则直接执行。F2：zip 提取走 ZipExtractOperation。
    func confirmTransfer(_ draft: TransferDraft) {
        if let zip = draft.zipSource {
            let entries = ZipConflictPrecheck.entries(archive: zip.archive, destination: draft.plan.destination, only: zip.entries)
            if entries.isEmpty {
                run(ZipExtractOperation(archive: zip.archive, destination: draft.plan.destination,
                                        resolutions: ConflictResolutions(), only: zip.entries))
            } else {
                activeSheet = .conflict(ConflictSession(entries: entries) { [weak self] resolutions in
                    self?.run(ZipExtractOperation(archive: zip.archive, destination: draft.plan.destination,
                                                  resolutions: resolutions, only: zip.entries))
                })
            }
            return
        }
        let entries = ConflictPrecheck.entries(for: draft.plan)
        if entries.isEmpty {
            executeTransfer(draft, resolutions: ConflictResolutions())
        } else {
            activeSheet = .conflict(ConflictSession(entries: entries) { [weak self] resolutions in
                self?.executeTransfer(draft, resolutions: resolutions)
            })
        }
    }

    private func executeTransfer(_ draft: TransferDraft, resolutions: ConflictResolutions) {
        let operation: FileOperation = draft.kind == .copy
            ? CopyOperation(plan: draft.plan, resolutions: resolutions)
            : MoveOperation(plan: draft.plan, resolutions: resolutions)
        run(operation)
    }

    // MARK: - 压缩 / 解压（⌘K / ⌘⇧K）

    func requestCompress() {
        guard !queue.isRunning else { return }
        let selection = effectiveSelection()
        guard !selection.isEmpty else { return }
        let baseName = selection.first!.lastPathComponent + ".zip"
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: focusedPane.url.path)) ?? [])
        let name = ConflictResolver.resolvedName(for: baseName, strategy: .keepBoth, existingNames: existing) ?? baseName
        let destination = focusedPane.url.appendingPathComponent(name)
        run(ZipCompressOperation(sources: selection, destination: destination))
    }

    func requestExtract() {
        guard !queue.isRunning else { return }
        let selection = effectiveSelection().filter { $0.pathExtension.lowercased() == "zip" }
        guard let archive = selection.first else { return }
        let destination = focusedPane.url
        let entries = ZipConflictPrecheck.entries(archive: archive, destination: destination)
        if entries.isEmpty {
            run(ZipExtractOperation(archive: archive, destination: destination, resolutions: ConflictResolutions()))
        } else {
            activeSheet = .conflict(ConflictSession(entries: entries) { [weak self] resolutions in
                self?.run(ZipExtractOperation(archive: archive, destination: destination, resolutions: resolutions))
            })
        }
    }

    // MARK: - 删除 / 新建（F7/F8）

    func deleteSelection() {
        guard !queue.isRunning else { return }
        guard !focusedPane.isZipBrowsing else { alertMessage = "zip 内为只读"; return }
        let selection = effectiveSelection()
        guard !selection.isEmpty else { return }
        run(DeleteOperation(sources: selection))
    }

    func requestNewFolder() {
        guard !focusedPane.isZipBrowsing else { alertMessage = "zip 内为只读"; return }
        activeSheet = .newFolder(focusedSide)
    }

    func createFolder(named name: String, in side: PaneSide) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !queue.isRunning else { return }
        let pane = side == .left ? leftGroup.selectedPane : rightGroup.selectedPane
        run(CreateFolderOperation(directory: pane.url.appendingPathComponent(trimmed)))
    }

    // MARK: - 中央按钮：交换 / 同路径

    func swapPaths() {
        let l = leftGroup.selectedPane.url
        leftGroup.selectedPane.navigate(to: rightGroup.selectedPane.url, pushHistory: false)
        rightGroup.selectedPane.navigate(to: l, pushHistory: false)
    }

    func equalizePaths() {
        otherGroup.selectedPane.navigate(to: focusedPane.url, pushHistory: true)
    }

    // MARK: - 快捷操作（B 组）

    func copyPaths(mode: PathCopyMode) {
        let urls = effectiveSelection()
        guard !urls.isEmpty else { return }
        let text: String
        switch mode {
        case .posix: text = PathCopyService.posixPaths(urls)
        case .fileURL: text = PathCopyService.fileURLs(urls)
        case .fileName: text = PathCopyService.fileNames(urls)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func toggleHiddenFiles() {
        focusedPane.toggleHiddenFiles()
    }

    func openTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", focusedPane.url.path]
        do {
            try process.run()
        } catch {
            fileOpsLogger.error("打开终端失败：\(error.localizedDescription, privacy: .public)")
            alertMessage = "无法打开终端：\(error.localizedDescription)"
        }
    }

    func quickLookSelection() {
        // F3-1：zip 内 = 临时解压到临时目录再预览，面板关闭后清理
        if let archive = focusedPane.zipArchive {
            guard let item = effectiveSelection().first else { return }
            let inner = focusedPane.virtualPath(for: item)
            let tempRoot = ZipPreviewService.defaultTempRoot()
            do {
                let staged = try ZipPreviewService.stage(archive: archive, entry: inner, tempRoot: tempRoot)
                PreviewBridge.shared.preview([staged])
                // 面板关闭即清理
                NotificationCenter.default.addObserver(forName: NSNotification.Name("QLPreviewPanelWillCloseNotification"), object: nil, queue: .main) { _ in
                    ZipPreviewService.cleanup(tempRoot: tempRoot)
                }
            } catch {
                alertMessage = error.localizedDescription
            }
            return
        }
        let urls = effectiveSelection()
        guard !urls.isEmpty else { return }
        PreviewBridge.shared.preview(urls)
    }

    // MARK: - E1 批量重命名 / 通配符选择 / 校验和 / 热列表 / 文件夹大小

    func requestRename() {
        let items = focusedPane.selectedItems
        guard !items.isEmpty else { return }
        activeSheet = .rename(items)
    }

    /// 应用重命名计划（预览中无冲突的条目）。
    func applyRename(_ entries: [RenamePlanEntry], in pane: PaneState) {
        let pairs = entries
            .filter { !$0.conflict && $0.original != $0.renamed }
            .map { (pane.url.appendingPathComponent($0.original), pane.url.appendingPathComponent($0.renamed)) }
        guard !pairs.isEmpty else { return }
        run(RenameOperation(pairs: pairs))
    }

    enum WildcardMode {
        case select, addToSelection, invert, deselect
    }

    func selectByWildcard(pattern: String, mode: WildcardMode) {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let pane = focusedPane
        let matched = Set(pane.items.filter {
            WildcardMatcher.matches($0.name, pattern: trimmed)
        }.map(\.url))
        switch mode {
        case .select: pane.selection = matched
        case .addToSelection: pane.selection.formUnion(matched)
        case .invert:
            pane.selection = pane.selection.symmetricDifference(matched)
        case .deselect: pane.selection.subtract(matched)
        }
    }

    func requestChecksum() {
        guard let url = effectiveSelection().first else { return }
        activeSheet = .checksum(url)
    }

    /// E1-6：⌘D 改为弹出热列表。
    func requestHotlist() {
        activeSheet = .hotlist
    }

    /// E1-4：触发式后台计算选中目录大小，可取消，结果显示在状态栏。
    func computeFolderSize() {
        folderSizeWork?.cancel()
        let urls = effectiveSelection()
        guard !urls.isEmpty else { return }
        folderSizeResult = "计算中…"
        let work = DispatchWorkItem { [weak self] in
            var cancelled = false
            let result = FolderSizer.compute(urls: urls, isCancelled: { cancelled }) { _, _ in }
            DispatchQueue.main.async {
                guard let self = self, !cancelled else { return }
                let skippedNote = result.skipped > 0 ? "，\(result.skipped) 个目录不可读" : ""
                self.folderSizeResult = "\(Theme.sizeString(result.size))（\(result.files) 个文件\(skippedNote)）"
            }
        }
        folderSizeWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    func cancelFolderSize() {
        folderSizeWork?.cancel()
        folderSizeResult = nil
    }

    /// F1-B：查找重复文件（两栏子树，后台 + 可取消）。
    func findDuplicates(progress: ((Int, Int) -> Void)? = nil,
                        completion: @escaping (Result<[DuplicateGroup], Error>) -> Void) {
        let roots = [leftGroup.selectedPane.url, rightGroup.selectedPane.url]
        folderSizeWork?.cancel()
        let work = DispatchWorkItem {
            var cancelled = false
            do {
                let groups = try DuplicateFinder.find(in: roots, isCancelled: { cancelled }) { done, total in
                    DispatchQueue.main.async { progress?(done, total) }
                }
                DispatchQueue.main.async { completion(.success(groups)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        folderSizeWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    func requestDuplicates() {
        activeSheet = .duplicates
    }

    /// F1-B：组内保留指定项，其余删除（已 deprecated 保留首项入口，见 deleteDuplicates(keeping:in:)）。
    func deleteDuplicatesKeepingFirst(_ group: DuplicateGroup) {
        guard let first = group.files.first else { return }
        deleteDuplicates(keeping: first, in: group)
    }

    /// F1-A：执行同步计划（唯一合法批量写路径）。
    func runSync(_ actions: [SyncAction]) {
        guard !actions.isEmpty else { return }
        run(SyncOperation(actions: actions))
    }

    func requestUninstall() {
        activeSheet = .uninstall
    }

    /// F2-B：执行卸载 = App bundle + 勾选关联文件，全部走 DeleteOperation（废纸篓 + 可撤销）。
    func runUninstall(app: InstalledApp, related: [RelatedFile]) {
        let targets = AppScanner.uninstallTargets(app: app, related: related)
        guard !targets.isEmpty else { return }
        run(DeleteOperation(sources: targets))
    }

    /// 当前运行中的 App 路径集合（卸载确认窗警告用）。
    var runningAppPaths: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
    }

    /// F3-5：打开分割对话框（选中文件）。
    func requestSplitDialog() {
        guard !focusedPane.isZipBrowsing else { alertMessage = "zip 内为只读"; return }
        guard let file = effectiveSelection().first, !focusedPane.selectedItems.first!.isDirectory else {
            alertMessage = "请先选中一个文件"
            return
        }
        activeSheet = .split(file)
    }

    /// F3-5：打开修改日期对话框。
    func requestTouchDialog() {
        guard !focusedPane.isZipBrowsing else { alertMessage = "zip 内为只读"; return }
        guard let file = effectiveSelection().first else { return }
        activeSheet = .touch(file)
    }

    /// F3-5：分割选中文件。
    func requestSplit(partSizeMB: Int) {
        guard !focusedPane.isZipBrowsing else { alertMessage = "zip 内为只读"; return }
        guard let file = effectiveSelection().first else { return }
        run(SplitOperation(file: file, partSize: Int64(partSizeMB) * 1_048_576))
    }

    /// F4-1：合并选中 partN 分卷，产物名冲突走冲突对话框（收口唯一绕过冲突的写路径）。
    func requestJoin() {
        let parts = effectiveSelection().filter { $0.pathExtension.hasPrefix("part") }
        guard parts.count >= 2 else {
            alertMessage = "请选中至少两个 .partN 分卷文件"
            return
        }
        let baseName = parts[0].deletingPathExtension().lastPathComponent
        let destination = parts[0].deletingLastPathComponent().appendingPathComponent(baseName)
        let fm = FileManager.default
        var existingSize: Int64 = 0
        if let attrs = try? fm.attributesOfItem(atPath: destination.path) {
            existingSize = attrs[.size] as? Int64 ?? 0
        }
        let partsTotal = parts.reduce(Int64(0)) {
            $0 + (((try? fm.attributesOfItem(atPath: $1.path)) ?? [:])[.size] as? Int64 ?? 0)
        }
        guard fm.fileExists(atPath: destination.path) else {
            run(JoinOperation(parts: parts, destination: destination))
            return
        }
        // 产物已存在：冲突对话框
        let entry = ConflictEntry(sourceName: baseName, sourceSize: partsTotal,
                                  sourceModified: Date(), destExists: true,
                                  destSize: existingSize, destModified: Date())
        activeSheet = .conflict(ConflictSession(entries: [entry]) { [weak self] resolutions in
            self?.run(JoinOperation(parts: parts, destination: destination, resolutions: resolutions))
        })
    }

    /// F4-3：重复组内自选保留项——保留 keep，其余走废纸篓（可撤销）。
    func deleteDuplicates(keeping keep: URL, in group: DuplicateGroup) {
        let rest = group.files.filter { $0 != keep }
        guard !rest.isEmpty else { return }
        run(DeleteOperation(sources: rest))
    }

    /// F3-5：touch 修改日期。
    func requestTouch(_ date: Date) {
        guard !focusedPane.isZipBrowsing else { alertMessage = "zip 内为只读"; return }
        guard let file = effectiveSelection().first else { return }
        run(SetDateOperation(target: file, newDate: date))
    }

    // MARK: - 收藏夹（前往菜单 + E1 热列表共用）

    func addCurrentToFavorites() {
        AppServices.shared.addFavorite(focusedPane.url)
    }

    func removeFavorite(_ url: URL) {
        AppServices.shared.removeFavorite(url)
    }

    func visit(_ url: URL) {
        focusedPane.navigate(to: url)
    }

    // MARK: - 撤销（⌘Z）

    var canUndo: Bool { !undoStack.isEmpty && !queue.isRunning }

    func undo() {
        guard canUndo, let operation = undoStack.popLast() else { return }
        run(operation, isUndo: true)
    }

    // MARK: - 队列执行

    private func run(_ operation: FileOperation, isUndo: Bool = false) {
        if !isUndo { undoStack.append(operation) }
        activeSheet = .progress(operation.title)
        queue.enqueue(UndoOperation(inner: operation, isUndo: isUndo)) { [weak self] result in
            guard let self = self else { return }
            self.activeSheet = nil
            if case .failure(let error) = result {
                self.alertMessage = (error as? OperationError) == .cancelled
                    ? "已取消" : error.localizedDescription
            }
            self.reloadPanes()
        }
    }

    func cancelRunningOperation() {
        queue.cancel()
    }

    func reloadPanes() {
        leftGroup.selectedPane.reload()
        rightGroup.selectedPane.reload()
    }

    // MARK: - 布局记忆（D5）

    func makeLayout(themeName: String, windowSize: NSSize, dividerPosition: CGFloat) -> LayoutState {
        var state = LayoutState()
        state.windowWidth = Double(windowSize.width)
        state.windowHeight = Double(windowSize.height)
        state.dividerPosition = Double(dividerPosition)
        state.focusedSide = focusedSide == .left ? "left" : "right"
        state.themeName = themeName
        state.left = leftGroup.snapshot()
        state.right = rightGroup.snapshot()
        return state
    }

    func applyLayout(_ state: LayoutState) {
        leftGroup.restore(from: state.left)
        rightGroup.restore(from: state.right)
        focusedSide = state.focusedSide == "right" ? .right : .left
    }

    // MARK: - 快捷键分发。返回 true 表示事件已消费。

    func handleKey(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let opt = flags.contains(.option)
        let ctrl = flags.contains(.control)
        let chars = event.charactersIgnoringModifiers?.lowercased()

        switch event.keyCode {
        // U1 需求变更 0：F5–F8 功能键拦截移除，操作走中央按钮栏。⌘ 系标准键与 Tab 保留。
        case 17 where cmd && !opt: newTab(); return true                // ⌘T
        case 13 where cmd && !opt: closeTab(in: focusedGroup, id: focusedGroup.selectedTabID); return true // ⌘W
        case 48 where !cmd: focusedSide = focusedSide.opposite; return true // Tab
        case 6 where cmd && !opt && !isEditingText: undo(); return true // ⌘Z
        case 47 where cmd && shift: toggleHiddenFiles(); return true    // ⌘⇧.
        case 40 where cmd && !opt: requestCompress(); return true       // ⌘K
        case 40 where cmd && opt: requestExtract(); return true         // ⌘⌥K（备用）
        case 40 where cmd && shift: requestExtract(); return true       // ⌘⇧K
        case 50 where ctrl && !cmd: openTerminal(); return true         // ⌃`
        case 2 where cmd && opt: copyPaths(mode: .posix); return true   // ⌥⌘C
        case 32 where cmd && opt: copyPaths(mode: .fileURL); return true // ⌥⌘U
        case 45 where cmd && opt: copyPaths(mode: .fileName); return true // ⌥⌘N
        case 2 where cmd && !opt && !shift && !isEditingText: requestHotlist(); return true // ⌘D 热列表
        case 11 where cmd && shift && !isEditingText:                        // ⌘⇧B 分支视图
            focusedPane.branchMode.toggle()
            focusedPane.reload()
            return true
        case 29 where cmd && shift: equalizeHandler?(); return true                        // ⌘⇧0 均分栏宽
        case 53:                                                                            // Esc
            if focusedPane.branchMode { focusedPane.branchMode = false; focusedPane.reload(); return true }
            if !focusedPane.filter.isEmpty { focusedPane.filter = ""; return true }
            return false
        case 15 where cmd && opt && ctrl:                    // ⌃⌘R 皮肤重载
            AppServices.shared.themeStore?.reload(); return true
        case 15 where cmd && !opt: reloadPanes(); return true // ⌘R 刷新
        case 49 where !cmd && !ctrl && !isEditingText: quickLookSelection(); return true // 空格
        default:
            return false
        }
    }

    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
            || NSApp.keyWindow?.firstResponder is NSTextField
    }
}

enum PathCopyMode {
    case posix, fileURL, fileName
}

/// 包装撤销动作的队列操作。
private struct UndoOperation: FileOperation {
    let inner: FileOperation
    let isUndo: Bool
    var title: String { isUndo ? "撤销：\(inner.title)" : inner.title }
    func execute(isCancelled: () -> Bool, progress: @escaping (Int, Int, Int64, Int64) -> Void) throws {
        if isUndo { try inner.undo() } else { try inner.execute(isCancelled: isCancelled, progress: progress) }
    }
    func undo() throws {} // 撤销不可再撤销
}
