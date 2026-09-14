import AppKit
import SwiftUI

/// 拦截 ⌘A 全选；其余按键走默认行为。
final class KeyTableView: NSTableView {
    var onSelectAll: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            onSelectAll?()
            return
        }
        super.keyDown(with: event)
    }
}

/// 右键菜单容器：弹出时按点击行重建菜单内容。
final class ContextMenuProvider: NSMenu {
    weak var coordinator: FileTableView.Coordinator?
    init(coordinator: FileTableView.Coordinator) {
        self.coordinator = coordinator
        super.init(title: "")
    }
    required init(coder: NSCoder) { fatalError("unsupported") }

    override func update() {
        removeAllItems()
        let row = coordinator?.table?.clickedRow ?? -1
        let rebuilt = coordinator?.menu(for: row) ?? NSMenu()
        for case let item as NSMenuItem in rebuilt.items {
            item.target = coordinator
            addItem(item)
        }
        if let coordinator = coordinator { coordinator.menuRow = coordinator.table?.clickedRow ?? -1 }
    }
}

/// U1 自绘行视图：交替行底色 / 选中两档（文件夹较深）/ 左缘强调条 / hover。
/// U1.1：选中态自动反色文字——选中底色较深时单元格文字切换为高对比色。
final class DualRowView: NSTableRowView {
    var baseColor: NSColor = .clear
    var selectedColor: NSColor = .clear
    var accentColor: NSColor = .clear
    var hoverColor: NSColor = .clear
    /// 选中态文字色（由 Coordinator 按主题亮度注入：浅色主题选中行用白字，深色用亮字）
    var selectedTextColor: NSColor = .white
    var normalTextColor: NSColor = .labelColor
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override var isSelected: Bool {
        didSet { syncTextColor() }
    }

    override var isEmphasized: Bool {
        get { false }              // U1.1：禁用系统焦点强调色（避免整行变系统蓝）
        set { }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // 选择底色已在 drawBackground 绘制（主题两档色），禁用系统选区
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncTextColor()
    }

    /// 遍历本行单元格文字，按选中态切换颜色。
    func syncTextColor() {
        let target = isSelected ? selectedTextColor : normalTextColor
        for case let field as NSTextField in subviews {
            field.textColor = target
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let color: NSColor
        if isSelected {
            color = selectedColor
        } else if isHovered {
            color = hoverColor
        } else {
            color = baseColor
        }
        color.setFill()
        dirtyRect.fill()
        if isSelected {
            accentColor.setFill()
            NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
        }
    }
}

/// NSTableView 桥接：承担 10 万行性能与原生多选交互。
/// U1：交替行 / 选中两档（文件夹较深）/ hover / 单击仅选中 / 双击打开。
struct FileTableView: NSViewRepresentable {
    @ObservedObject var pane: PaneState
    // U1：直接观察主题仓库，模式/主题变化必触发 updateNSView（不依赖父视图 diff）
    @ObservedObject var themeStore = AppServices.shared.themeStore ?? ThemeStore()

    func makeCoordinator() -> Coordinator {
        Coordinator(pane: pane)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyTableView()
        let coordinator = context.coordinator
        table.onSelectAll = { [weak coordinator] in
            coordinator?.pane.selectAll()
        }
        table.delegate = coordinator
        table.dataSource = coordinator
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.style = .plain
        table.rowSizeStyle = .small
        table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        table.selectionHighlightStyle = .regular // 绘制完全由 DualRowView 接管
        table.doubleAction = #selector(Coordinator.doubleClickRow)
        table.target = context.coordinator
        context.coordinator.table = table
        context.coordinator.modelProxy = AppServices.shared.model
        // U1.1 右键菜单：动态生成（点击行 = 行操作菜单；空白 = 新建文件夹）
        let menuProvider = ContextMenuProvider(coordinator: context.coordinator)
        context.coordinator.menuProvider = menuProvider
        table.menu = menuProvider
        applyTheme(to: table, coordinator: coordinator)

        // hover 追踪：可见矩形内自动跟随滚动
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeAlways],
            owner: coordinator, userInfo: nil)
        table.addTrackingArea(tracking)

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("name", "名称", 320), ("size", "大小", 90),
            ("modified", "修改日期", 150), ("kind", "种类", 80),
        ]
        for col in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            column.title = col.title
            column.width = col.width
            column.minWidth = 40
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: col.id,
                ascending: true,
                comparator: { _, _ in .orderedSame } // 真正排序在 Coordinator 里做
            )
            table.addTableColumn(column)
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pane = pane
        coordinator.modelProxy = AppServices.shared.model
        guard let table = scroll.documentView as? KeyTableView else { return }

        // 主题变化 → 刷新表与全部行的颜色
        applyTheme(to: table, coordinator: coordinator)

        if coordinator.lastItemCount != pane.displayedItems.count || coordinator.needsReload {
            coordinator.needsReload = false
            coordinator.lastItemCount = pane.displayedItems.count
            table.reloadData()
        }

        // 同步选择状态（程序侧 → 表格），防止委托回调造成回环
        coordinator.isSyncingSelection = true
        let selected = pane.displayedItems.enumerated()
            .filter { pane.selection.contains($0.element.url) }
            .map(\.offset)
        let indexSet = IndexSet(selected)
        if table.selectedRowIndexes != indexSet {
            table.selectRowIndexes(indexSet, byExtendingSelection: false)
        }
        coordinator.isSyncingSelection = false
    }

    /// 主题色注入表与滚动视图。指纹 = 主题名 + 模式 + 系统侧（确定性，避免 Color.description 不稳定）。
    private func applyTheme(to table: KeyTableView, coordinator: Coordinator) {
        let store = themeStore
        let fingerprint = "\(store.currentName)|\(store.mode.rawValue)|\(store.isSystemDark)"
        coordinator.theme = store.values
        guard coordinator.lastThemeFingerprint != fingerprint else { return }
        coordinator.lastThemeFingerprint = fingerprint

        table.backgroundColor = NSColor(store.values.rowOdd)
        coordinator.needsReload = true
        table.reloadData()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var pane: PaneState
        weak var table: KeyTableView?
        weak var menuProvider: ContextMenuProvider?
        var lastItemCount = -1
        var needsReload = true
        var isSyncingSelection = false
        var lastThemeFingerprint = ""
        var theme = ThemeValues.fallback
        private var hoverRow: Int? { didSet { refreshHover(old: oldValue, new: hoverRow) } }

        private let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return f
        }()

        init(pane: PaneState) {
            self.pane = pane
        }

        private func refreshHover(old: Int?, new: Int?) {
            let table = table
            for row in [old, new].compactMap({ $0 }) {
                (table?.rowView(atRow: row, makeIfNecessary: false) as? DualRowView)?.needsDisplay = true
            }
        }

        // MARK: hover（NSEvent 路由，tracking area .inVisibleRect）

        func mouseMoved(with event: NSEvent) {
            guard let table = table else { return }
            let point = table.convert(event.locationInWindow, from: nil)
            let row = table.row(at: point)
            hoverRow = (row >= 0 && row < pane.displayedItems.count) ? row : nil
            let rowView = (row >= 0) ? table.rowView(atRow: row, makeIfNecessary: false) : nil
            (rowView as? DualRowView)?.isHovered = (row == hoverRow)
        }

        func mouseExited(with event: NSEvent) {
            hoverRow = nil
        }

        // MARK: DataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            pane.displayedItems.count
        }

        // MARK: 行视图（U1：交替行 / 选中两档 / 强调条）

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < pane.displayedItems.count else { return nil }
            let item = pane.displayedItems[row]
            let view = DualRowView()
            view.baseColor = NSColor(row % 2 == 0 ? theme.rowEven : theme.rowOdd)
            view.selectedColor = NSColor(item.isDirectory ? theme.selFolder : theme.selFile)
            view.accentColor = NSColor(theme.accent)
            view.hoverColor = NSColor(theme.hover)
            // U1.1 对比度修复：选中底色（蓝系）较深 → 选中行文字用白色；普通行按主题
            view.selectedTextColor = NSColor(theme.selText)
            view.normalTextColor = NSColor(theme.foreground)
            DispatchQueue.main.async { view.syncTextColor() }
            return view
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            true // 单击 = 选中（⌘/⇧ 由表格原生处理），打开动作只在双击
        }

        // MARK: 单元格

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let id = tableColumn?.identifier.rawValue, row < pane.displayedItems.count else { return nil }
            let item = pane.displayedItems[row]
            let cellID = NSUserInterfaceItemIdentifier("cell-\(id)")
            let cell = (tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView) ?? NSTableCellView()
            cell.identifier = cellID

            // HOTFIX-2（名称列遮挡修复）：图标与文字在创建时一次性布局到位，
            // 不再依赖复用后二次查找约束（原实现对复用单元格首字符被图标覆盖）。
            var icon = cell.subviews.compactMap { $0 as? NSImageView }.first
            var text = cell.subviews.compactMap { $0 as? NSTextField }.first
            if icon == nil || text == nil {
                for sub in cell.subviews { sub.removeFromSuperview() }
                let newIcon = NSImageView()
                newIcon.translatesAutoresizingMaskIntoConstraints = false
                let newText = NSTextField(labelWithString: "")
                newText.isBordered = false
                newText.backgroundColor = .clear
                newText.lineBreakMode = .byTruncatingMiddle
                newText.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(newIcon)
                cell.addSubview(newText)
                NSLayoutConstraint.activate([
                    newIcon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    newIcon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    newIcon.widthAnchor.constraint(equalToConstant: 16),
                    newIcon.heightAnchor.constraint(equalToConstant: 16),
                    newText.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
                    newText.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    newText.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                icon = newIcon
                text = newText
            }
            guard let icon = icon, let text = text else { return cell }

            switch id {
            case "name":
                // F3-2：分支视图显示相对路径
                text.stringValue = pane.branchMode
                    ? BranchFlattener.displayName(for: item, root: pane.url)
                    : item.name
                text.font = item.isDirectory ? .systemFont(ofSize: 12, weight: .medium) : .systemFont(ofSize: 12)
                // F3-4：缩略图开关 + 图片扩展名
                let image: NSImage = (pane.showThumbnails && !item.isDirectory)
                    ? IconStore.thumbnail(for: item.url.path)
                    : IconStore.icon(for: item.url.path)
                icon.image = image
                icon.isHidden = false
                setTextLeading(4 + 20, for: text)   // 让位图标
            case "size":
                text.stringValue = item.isDirectory ? "—" : Theme.sizeString(item.size)
                text.font = .systemFont(ofSize: 12)
                icon.isHidden = true
                setTextLeading(4, for: text)
            case "modified":
                text.stringValue = dateFormatter.string(from: item.modified)
                text.font = .systemFont(ofSize: 12)
                icon.isHidden = true
                setTextLeading(4, for: text)
            case "kind":
                text.stringValue = item.kind
                text.font = .systemFont(ofSize: 12)
                icon.isHidden = true
                setTextLeading(4, for: text)
            default:
                break
            }
            text.textColor = NSColor(theme.foreground)
            return cell
        }

        /// 调整文字到单元格左缘的间距（复用单元格幂等：只改 constant，不叠加约束）。
        private func setTextLeading(_ constant: CGFloat, for text: NSTextField) {
            let leading = text.constraints.first {
                $0.firstAnchor == text.leadingAnchor && $0.secondAnchor == nil
            }
            leading?.constant = constant
        }

        // MARK: Delegate

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection,
                  let table = notification.object as? NSTableView else { return }
            let rows = table.selectedRowIndexes.filter { $0 < pane.displayedItems.count }
            pane.selection = Set(rows.map { pane.displayedItems[$0].url })
            // 光标项 = 选择锚点（最后一个选中的行）
            if let last = rows.max(), last < pane.displayedItems.count {
                pane.cursorItem = pane.displayedItems[last].url
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = SortKey(rawValue: descriptor.key ?? "") else { return }
            pane.applySort(key: key, ascending: descriptor.ascending)
            needsReload = true
        }

        // MARK: 右键菜单（U1.1 需求 3）

        /// 构建右键菜单。点击空白处时 menuSourceRow = -1，仅显示新建文件夹。
        func menu(for row: Int) -> NSMenu {
            let m = NSMenu()
            let inRange = row >= 0 && row < pane.displayedItems.count
            let item = inRange ? pane.displayedItems[row] : nil

            func add(_ title: String, _ sel: Selector, _ enabled: Bool = true) {
                let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                mi.isEnabled = enabled
                mi.target = self
                m.addItem(mi)
            }

            if let item = item {
                if item.isDirectory {
                    add("打开", #selector(menuOpenFolder(_:)))
                } else {
                    add("打开", #selector(menuOpenFile(_:)))
                }
                add("快速查看", #selector(menuQuickLook(_:)))
                m.addItem(.separator())
                add("复制到对侧栏", #selector(menuCopy(_:)))
                add("移动到对侧栏", #selector(menuMove(_:)))
                m.addItem(.separator())
            }
            add("新建文件夹", #selector(menuNewFolder(_:)))
            if let item = item {
                add("重命名…", #selector(menuRename(_:)))
                if !item.isDirectory {
                    m.addItem(.separator())
                    add("压缩为 zip", #selector(menuCompress(_:)))
                    add("校验和…", #selector(menuChecksum(_:)))
                }
                m.addItem(.separator())
                add("拷贝路径", #selector(menuCopyPath(_:)))
                add("移到废纸篓", #selector(menuTrash(_:)))
            }
            return m
        }

        private func focusedRowURL(_ sender: NSMenuItem) -> URL? {
            guard menuRow >= 0, menuRow < pane.displayedItems.count else { return nil }
            return pane.displayedItems[menuRow].url
        }

        var menuRow = -1

        @objc func menuOpenFolder(_ s: NSMenuItem) { if let u = focusedRowURL(s) { pane.navigate(to: u) } }
        @objc func menuOpenFile(_ s: NSMenuItem) { if let u = focusedRowURL(s) { NSWorkspace.shared.open(u) } }
        @objc func menuQuickLook(_ s: NSMenuItem) {
            guard let u = focusedRowURL(s) else { return }
            pane.selection = [u]; pane.cursorItem = u
            NotificationCenter.default.post(name: .init("DualVault.QuickLook"), object: nil)
        }
        @objc func menuCopy(_ s: NSMenuItem) { modelProxy?.requestTransfer(kind: .copy) }
        @objc func menuMove(_ s: NSMenuItem) { modelProxy?.requestTransfer(kind: .move) }
        @objc func menuNewFolder(_ s: NSMenuItem) { modelProxy?.requestNewFolder() }
        @objc func menuRename(_ s: NSMenuItem) {
            guard let u = focusedRowURL(s) else { return }
            pane.selection = [u]
            modelProxy?.requestRename()
        }
        @objc func menuCompress(_ s: NSMenuItem) {
            guard let u = focusedRowURL(s) else { return }
            pane.selection = [u]
            modelProxy?.requestCompress()
        }
        @objc func menuChecksum(_ s: NSMenuItem) {
            guard let u = focusedRowURL(s) else { return }
            pane.selection = [u]
            modelProxy?.requestChecksum()
        }
        @objc func menuCopyPath(_ s: NSMenuItem) {
            guard let u = focusedRowURL(s) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(u.path, forType: .string)
        }
        @objc func menuTrash(_ s: NSMenuItem) { modelProxy?.deleteSelection() }

        /// 弱引用 BrowserModel（避免循环持有）；由 makeNSView 注入。
        weak var modelProxy: BrowserModel?

        // 双击 = 打开：文件夹进入目录；zip 进入只读浏览；其余文件用系统默认程序打开（U1 交互）
        @objc func doubleClickRow() {
            guard let table = table else { return }
            let row = table.clickedRow
            guard row >= 0, row < pane.displayedItems.count else { return }
            let item = pane.displayedItems[row]
            if item.isDirectory {
                pane.navigate(to: item.url)
            } else if !pane.isZipBrowsing && item.url.pathExtension.lowercased() == "zip" {
                pane.navigate(to: item.url) // navigate 自动进入 zip 浏览模式
            } else if !pane.isZipBrowsing {
                NSWorkspace.shared.open(item.url)
            }
        }
    }
}
