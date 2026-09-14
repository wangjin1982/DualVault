import Foundation

/// 布局记忆持久化（Codable + UserDefaults，§6 用例 14）。唯一出口，不散落。
struct LayoutState: Codable, Equatable {
    var windowWidth: Double = 1100
    var windowHeight: Double = 700
    var dividerPosition: Double = 500
    var focusedSide: String = "left"
    var themeName: String = "Dark"
    var left = PaneGroupSnapshot()
    var right = PaneGroupSnapshot()
}

struct PaneGroupSnapshot: Codable, Equatable {
    var selectedTab: Int = 0
    var tabs: [PaneSnapshot] = []
}

struct PaneSnapshot: Codable, Equatable {
    var path: String
    var sortKey: String = "name"
    var sortAscending: Bool = true
    var includeHidden: Bool = false
}

enum LayoutStore {
    private static let key = "layout.state"

    static func save(_ state: LayoutState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> LayoutState? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(LayoutState.self, from: data) else { return nil }
        return state
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
