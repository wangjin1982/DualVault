import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(\.theme) private var theme
    @StateObject private var model = BrowserModel()

    var body: some View {
        DualSplitView(
            dividerPosition: $dividerPosition,
            centerWidth: 56) {
            PaneColumnView(group: model.leftGroup, side: .left, model: model)
        } center: {
            CenterActionBar(model: model)
        } right: {
            PaneColumnView(group: model.rightGroup, side: .right, model: model)
        }
        .frame(minWidth: 760, minHeight: 470)
        .background(theme.background)
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .confirm(let draft):
                TransferConfirmView(
                    draft: draft,
                    onConfirm: { model.confirmTransfer(draft) },
                    onCancel: { model.activeSheet = nil })
            case .conflict(let session):
                ConflictDialogView(
                    session: session,
                    onCancel: { model.activeSheet = nil })
            case .newFolder(let side):
                NewFolderView(
                    side: side,
                    onCreate: { name, side in
                        model.createFolder(named: name, in: side)
                        model.activeSheet = nil
                    },
                    onCancel: { model.activeSheet = nil })
            case .progress(let title):
                OperationProgressView(
                    title: title,
                    queue: model.queue,
                    onCancel: model.cancelRunningOperation)
            case .rename(let items):
                RenameDialogView(
                    items: items,
                    pane: model.focusedPane,
                    onApply: { entries in
                        model.applyRename(entries, in: model.focusedPane)
                        model.activeSheet = nil
                    },
                    onCancel: { model.activeSheet = nil })
            case .wildcard:
                WildcardSelectView(
                    onApply: { pattern, mode in
                        model.selectByWildcard(pattern: pattern, mode: mode)
                    },
                    onCancel: { model.activeSheet = nil })
            case .checksum(let url):
                ChecksumView(url: url, onClose: { model.activeSheet = nil })
            case .hotlist:
                HotlistView(
                    onVisit: { url in
                        model.visit(url)
                        model.activeSheet = nil
                    },
                    onClose: { model.activeSheet = nil })
            case .compare:
                CompareView(model: model, onClose: { model.activeSheet = nil })
            case .duplicates:
                DuplicatesView(model: model, onClose: { model.activeSheet = nil })
            case .uninstall:
                UninstallerView(model: model, onClose: { model.activeSheet = nil })
            case .touch(let file):
                TouchDialogView(
                    file: file,
                    onApply: { date in
                        model.requestTouch(date)
                        model.activeSheet = nil
                    },
                    onCancel: { model.activeSheet = nil })
            case .split(let file):
                SplitDialogView(
                    file: file,
                    onApply: { mb in
                        model.requestSplit(partSizeMB: mb)
                        model.activeSheet = nil
                    },
                    onCancel: { model.activeSheet = nil })
            }
        }
        .alert("提示", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear {
            AppServices.shared.model = model
            // U1：标题栏融入（透明 + 全尺寸内容）
            DispatchQueue.main.async {
                NSApp.windows.first?.titlebarAppearsTransparent = true
            }
            AppServices.shared.themeStore = themeStore
            let dividerBinding = self.$dividerPosition
            model.equalizeHandler = {
                guard let width = NSApp.keyWindow?.contentView?.bounds.width else { return }
                dividerBinding.wrappedValue = max(320, (width - 56) / 2)
            }
            restoreLayout()
            setupKeyboardMonitor()
        }
        .onDisappear {
            saveLayout()
            if AppServices.shared.model === model { AppServices.shared.model = nil }
            removeKeyboardMonitor()
        }
        .environment(\.theme, themeStore.values)
    }

    @StateObject private var themeStore = ThemeStore()
    @State private var dividerPosition: CGFloat = 500

    // MARK: - 布局记忆（D5）

    private func restoreLayout() {
        guard let state = LayoutStore.load() else { return }
        themeStore.select(state.themeName)
        model.applyLayout(state)
        dividerPosition = state.dividerPosition
        let size = NSSize(width: state.windowWidth, height: state.windowHeight)
        DispatchQueue.main.async {
            NSApp.windows.first?.setContentSize(size)
        }
    }

    private func saveLayout() {
        let size = NSApp.keyWindow?.frame.size ?? NSSize(width: 1100, height: 700)
        LayoutStore.save(model.makeLayout(themeName: themeStore.currentName,
                                          windowSize: size,
                                          dividerPosition: dividerPosition))
    }

    // MARK: - 本地键盘监听（F5–F8 / ⌘T/⌘W / Tab / ⌘Z / B 组快捷键）

    private func setupKeyboardMonitor() {
        KeyboardMonitor.shared.install { event in
            model.handleKey(event) ? nil : event
        }
    }

    private func removeKeyboardMonitor() {
        KeyboardMonitor.shared.remove()
    }
}

/// 单侧栏容器：标签栏 + 当前标签的 PaneView。
struct PaneColumnView: View {
    @ObservedObject var group: PaneGroupModel
    let side: PaneSide
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(group: group) { id in
                model.closeTab(in: group, id: id)
            }
            PaneView(
                pane: group.selectedPane,
                model: model,
                side: side,
                focusedSide: Binding(
                    get: { model.focusedSide },
                    set: { model.focusedSide = $0 }))
        }
    }
}

/// 窗口级本地事件监视器。模型消费事件时返回 nil 吞掉。
final class KeyboardMonitor {
    static let shared = KeyboardMonitor()
    private var monitor: Any?

    func install(handler: @escaping (NSEvent) -> NSEvent?) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func remove() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
