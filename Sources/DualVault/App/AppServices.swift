import Foundation

/// 收藏夹 + 全局模型引用（菜单命令用）。UserDefaults 持久化。
final class AppServices: ObservableObject {
    static let shared = AppServices()

    /// 当前窗口的 BrowserModel（MainWindowView 挂载时设置）
    weak var model: BrowserModel?

    /// 当前窗口的皮肤仓库（AppKit 桥接层取色用）
    weak var themeStore: ThemeStore?

    @Published var favorites: [URL] {
        didSet {
            let paths = favorites.map(\.path)
            UserDefaults.standard.set(paths, forKey: "favorites")
        }
    }

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: "favorites") ?? []
        favorites = paths.map { URL(fileURLWithPath: $0) }
    }

    func addFavorite(_ url: URL) {
        guard !favorites.contains(url) else { return }
        favorites.append(url)
    }

    func removeFavorite(_ url: URL) {
        favorites.removeAll { $0 == url }
    }
}
