import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(\.theme) private var theme
    @StateObject private var model = BrowserModel()
    @ObservedObject private var services = AppServices.shared
    @State private var sidebarVisible = true
    @State private var quickLookObserver: (any NSObjectProtocol)?

    var body: some View {
        VStack(spacing: 0) {
            // U1.2 顶部工具栏：操作集中于此（ForkLift 风格），标题栏透明融入
            ToolbarView(model: model, sidebarVisible: $sidebarVisible)
            HStack(spacing: 0) {
                // U1.1 侧栏：设备/最近/收藏/标签/可展开文件夹树
                if sidebarVisible {
                    SidebarView(model: model, side: .left, services: services)
                        .frame(width: 170)
                    Rectangle().fill(theme.pathBarStroke).frame(width: 1)
                }
                DualSplitView(dividerPosition: $dividerPosition) {
                    PaneColumnView(group: model.leftGroup, side: .left, model: model, sidebarVisible: $sidebarVisible)
                } right: {
                    PaneColumnView(group: model.rightGroup, side: .right, model: model, sidebarVisible: $sidebarVisible)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 470)
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
            // U1.2：标题栏融合——系统标题栏跟随主题外观（消灭与内容脱节的黑带）
            applyWindowChrome()
            chromeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak themeStore] _ in
                    _ = themeStore   // 保持引用
                }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { applyWindowChromeAgain() }
            AppServices.shared.themeStore = themeStore
            let dividerBinding = self.$dividerPosition
            model.equalizeHandler = {
                guard let width = NSApp.keyWindow?.contentView?.bounds.width else { return }
                dividerBinding.wrappedValue = max(280, (width - (sidebarVisible ? 171 : 0)) / 2)
            }
            restoreLayout()
            setupKeyboardMonitor()
            // U1.1 右键"快速查看"桥接
            quickLookObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("DualVault.QuickLook"), object: nil, queue: .main) { [weak model] _ in
                model?.quickLookSelection()
            }
        }
        .onDisappear {
            saveLayout()
            if let obs = quickLookObserver { NotificationCenter.default.removeObserver(obs) }
            if AppServices.shared.model === model { AppServices.shared.model = nil }
            removeKeyboardMonitor()
        }
        .environment(\.theme, themeStore.values)
    }

    @StateObject private var themeStore = ThemeStore()
    @State private var dividerPosition: CGFloat = 500

    // MARK: - 窗口外观（U1.2：标题栏跟随主题）

    @State private var chromeObserver: (any NSObjectProtocol)?

    private func applyWindowChrome() {
        let dark = themeStore.isSystemDark && themeStore.mode == .system
            || themeStore.mode == .dark
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        for w in NSApp.windows {
            guard w.contentView != nil else { continue }
            w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.backgroundColor = NSColor(themeStore.values.background)
        }
    }

    /// SwiftUI 建窗晚于 onAppear，延迟再应用一次（幂等）。
    private func applyWindowChromeAgain() { applyWindowChrome() }

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
    @Binding var sidebarVisible: Bool

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
                    set: { model.focusedSide = $0 }),
                sidebarVisible: $sidebarVisible)
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
