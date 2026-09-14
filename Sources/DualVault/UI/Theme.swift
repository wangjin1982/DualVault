import SwiftUI
import AppKit

/// 运行时皮肤值（SwiftUI Color）。唯一取色通道：SwiftUI 视图走 @Environment(\.theme)，
/// AppKit 桥接层走 AppServices.shared.themeStore.values。
struct ThemeValues {
    let background: Color
    let paneBackground: Color
    let alternateRow: Color
    let selection: Color
    let foreground: Color
    let secondaryText: Color
    let centerBarBackground: Color
    let destructive: Color
    let directoryIconTint: Color
    let fileListFontSize: Double
    let pathBarFontSize: Double
    // U1 v2.1 新令牌
    let titleBackground: Color
    let headerBackground: Color
    let rowEven: Color
    let rowOdd: Color
    let selFolder: Color
    let selFile: Color
    let accent: Color
    let hover: Color
    let centerBtn: Color
    let centerBtnHot: Color
    let tabBarBackground: Color
    let pathBarBackground: Color
    let pathBarStroke: Color
    let commandBarBackground: Color
    let diskTrack: Color
    let iconDoc: Color
    let iconZip: Color
    let statusBackground: Color

    static func from(_ t: AppTheme, isDark: Bool = true) -> ThemeValues {
        let c = resolvedColors(t, isDark: isDark)
        return ThemeValues(
            background: color(c.background, fallback: "#26262B"),
            paneBackground: color(c.paneBackground, fallback: "#1E1E23"),
            alternateRow: color(c.alternateRow, fallback: "#242429"),
            selection: color(c.selection, fallback: "#0A64C8"),
            foreground: color(c.foreground, fallback: "#E8E8ED"),
            secondaryText: color(c.secondaryText, fallback: "#8E8E96"),
            centerBarBackground: color(c.centerBarBackground, fallback: "#17171B"),
            destructive: color(c.destructive, fallback: "#FF453A"),
            directoryIconTint: color(t.directoryIconTint, fallback: "#4A9EFF"),
            fileListFontSize: t.font.fileList,
            pathBarFontSize: t.font.pathBar,
            titleBackground: color(c.titleBackground, fallback: "#1B1B22"),
            headerBackground: color(c.headerBackground, fallback: "#242430"),
            rowEven: color(c.rowEven, fallback: "#232334"),
            rowOdd: color(c.rowOdd, fallback: "#181825"),
            selFolder: color(c.selFolder, fallback: "#3A4A6B"),
            selFile: color(c.selFile, fallback: "#33415E"),
            accent: color(c.accent, fallback: "#89B4FA"),
            hover: color(c.hover, fallback: "#2A2B38"),
            centerBtn: color(c.centerBtn, fallback: "#1F1F2A"),
            centerBtnHot: color(c.centerBtnHot, fallback: "#2A2B38"),
            tabBarBackground: color(c.tabBarBackground, fallback: "#1B1B24"),
            pathBarBackground: color(c.pathBarBackground, fallback: "#11111B"),
            pathBarStroke: color(c.pathBarStroke, fallback: "#33334A"),
            commandBarBackground: color(c.commandBarBackground, fallback: "#0E0E15"),
            diskTrack: color(c.diskTrack, fallback: "#33334A"),
            iconDoc: color(c.iconDoc, fallback: "#8A9CF5"),
            iconZip: color(c.iconZip, fallback: "#E5C07B"),
            statusBackground: color(c.tabBarBackground, fallback: "#1E1F25"))
    }

    /// 跟随系统模式下取配对色板：Dark 主题带 lightColors；其余主题按当前侧取 colors。
    private static func resolvedColors(_ t: AppTheme, isDark: Bool) -> ThemeColors {
        if isDark { return t.colors }
        return t.lightColors ?? t.colors
    }

    static let fallback = ThemeValues.from(.builtIns[1]) // Dark

    private static func color(_ hex: String, fallback: String) -> Color {
        guard let rgba = HexColor.rgba(hex) ?? HexColor.rgba(fallback) else { return .gray }
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeValues.fallback
}

extension EnvironmentValues {
    var theme: ThemeValues {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 工具（非颜色）：集中放这里保持单一来源。
enum Theme {
    static func sizeString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// 主题模式：跟随系统（默认）/ 浅色 / 深色（U1 需求变更 1）。
enum ThemeMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 皮肤仓库：内置 4 套 + 用户目录扫描（启动 + ⌃⌘R 重载），非法 JSON 跳过并标注。
/// U1：三态模式（跟随系统/浅色/深色），跟随系统监听系统外观实时切换。
final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [AppTheme] = []
    @Published private(set) var failedNames: [String] = []
    @Published private(set) var isSystemDark = true
    @Published var mode: ThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "theme.mode")
            resolve()
        }
    }
    @Published var currentName: String {
        didSet {
            UserDefaults.standard.set(currentName, forKey: "theme.current")
            resolve()
        }
    }
    @Published private(set) var values: ThemeValues

    private var appearanceObserver: (any NSObjectProtocol)?
    let userThemesDir: URL

    init(userThemesDir: URL? = nil) {
        let base = userThemesDir
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("DualVault/Themes", isDirectory: true)
        self.userThemesDir = base
        let saved = UserDefaults.standard.string(forKey: "theme.current") ?? AppTheme.builtIns[1].name
        self.currentName = saved
        let savedMode = UserDefaults.standard.string(forKey: "theme.mode")
            .flatMap(ThemeMode.init(rawValue:)) ?? .system
        self.mode = savedMode
        self.values = ThemeValues.fallback
        reload()
        // 保存的名字可能已不存在（主题文件被删），回退 Dark
        if theme(named: currentName) == nil {
            currentName = AppTheme.builtIns[1].name
        }
        resolve()
        observeSystemAppearance()
    }

    deinit {
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func theme(named: String) -> AppTheme? {
        themes.first { $0.name == named }
    }

    func select(_ name: String) {
        guard theme(named: name) != nil else { return }
        currentName = name
    }

    /// 删除加载失败的主题文件并重新扫描。
    func removeFailed(_ fileName: String) {
        try? FileManager.default.removeItem(at: userThemesDir.appendingPathComponent(fileName))
        reload()
    }

    /// 扫描用户主题目录。合法 → 加入列表；非法 → 记入 failedNames，绝不崩溃。
    func reload() {
        var result = AppTheme.builtIns
        var failed: [String] = []
        if let files = try? FileManager.default.contentsOfDirectory(atPath: userThemesDir.path) {
            for file in files where file.hasSuffix(".json") {
                let url = userThemesDir.appendingPathComponent(file)
                guard let data = try? Data(contentsOf: url),
                      let theme = try? JSONDecoder().decode(AppTheme.self, from: data),
                      HexColor.validate(theme) else {
                    failed.append(file)
                    continue
                }
                result.append(theme)
            }
        }
        themes = result
        failedNames = failed
        resolve()
    }

    // MARK: - 跟随系统（U1）

    private func observeSystemAppearance() {
        // 系统外观变化由系统分发（沙盒安全，无需 KVO NSApp）
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChanged"),
            object: nil, queue: .main) { [weak self] _ in
                self?.resolve()
            }
    }

    private func systemIsDark() -> Bool {
        // 单测等无 NSApplication 环境下 NSApp 为 nil → 默认深色，不崩溃
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func resolve() {
        let theme = theme(named: currentName) ?? .builtIns[1]
        switch mode {
        case .dark:
            isSystemDark = true
            values = .from(theme, isDark: true)
        case .light:
            isSystemDark = false
            values = .from(theme, isDark: false)
        case .system:
            isSystemDark = systemIsDark()
            values = .from(theme, isDark: isSystemDark)
        }
    }
}
