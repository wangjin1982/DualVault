import Foundation
import SwiftUI

/// 一个标签 = 一个完整 PaneState（路径/历史/选择/过滤全部独立）。
final class PaneTab: Identifiable {
    let id = UUID()
    let state: PaneState
    init(state: PaneState) { self.state = state }
}

/// 单侧栏的标签组。
final class PaneGroupModel: ObservableObject {
    let side: PaneSide
    /// E1-7：新标签创建时回调（BrowserModel 注入同步浏览钩子）。
    var onTabCreated: ((PaneState) -> Void)?
    @Published var tabs: [PaneTab]
    @Published var selectedTabID: UUID

    init(side: PaneSide, initialURL: URL) {
        self.side = side
        let tab = PaneTab(state: PaneState(url: initialURL, sideName: side == .left ? "left" : "right"))
        self.tabs = [tab]
        self.selectedTabID = tab.id
    }

    var selectedTab: PaneTab {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }

    var selectedPane: PaneState { selectedTab.state }

    /// ⌘T：继承当前目录新建标签。
    @discardableResult
    func newTab() -> PaneTab {
        let tab = PaneTab(state: PaneState(url: selectedPane.url, sideName: side == .left ? "left" : "right"))
        tabs.append(tab)
        selectedTabID = tab.id
        onTabCreated?(tab.state)
        return tab
    }

    /// 关闭标签；最后一个不可关（返回 false）。
    @discardableResult
    func closeTab(id: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[max(0, index - 1)].id
        }
        return true
    }

    func select(id: UUID) {
        if tabs.contains(where: { $0.id == id }) { selectedTabID = id }
    }

    /// 从快照重建标签组（启动恢复）。路径已失效的条目回退到家目录。
    func restore(from snapshot: PaneGroupSnapshot) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var restored: [PaneTab] = snapshot.tabs.map { snap in
            let url = URL(fileURLWithPath: snap.path)
            var isDir: ObjCBool = false
            let valid = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            let state = PaneState(url: valid ? url : home, sideName: side == .left ? "left" : "right")
            state.applySort(key: SortKey(rawValue: snap.sortKey) ?? .name, ascending: snap.sortAscending)
            if snap.includeHidden && !state.includeHidden { state.toggleHiddenFiles() }
            return PaneTab(state: state)
        }
        if restored.isEmpty {
            restored = [PaneTab(state: PaneState(url: home))]
        }
        tabs = restored
        selectedTabID = tabs[min(max(snapshot.selectedTab, 0), tabs.count - 1)].id
        for tab in tabs { onTabCreated?(tab.state) }
    }

    func snapshot() -> PaneGroupSnapshot {
        PaneGroupSnapshot(
            selectedTab: tabs.firstIndex { $0.id == selectedTabID } ?? 0,
            tabs: tabs.map { tab in
                PaneSnapshot(path: tab.state.url.path,
                             sortKey: tab.state.sortKey.rawValue,
                             sortAscending: tab.state.sortAscending,
                             includeHidden: tab.state.includeHidden)
            })
    }
}
