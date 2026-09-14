import Foundation

/// 皮肤模型（Codable，格式按《开发手册》§3）。Core 层纯 Foundation，可单测。
/// 缺字段一律给默认值兜底，绝不崩溃（M4 边界要求）。
struct AppTheme: Codable, Identifiable, Hashable {
    var name: String
    var colors: ThemeColors
    var font: ThemeFont
    var directoryIconTint: String
    /// 配对的浅色/深色另一侧色板（跟随系统模式用）。nil = 固定配色主题。
    var lightColors: ThemeColors?

    var id: String { name }

    init(name: String, colors: ThemeColors = ThemeColors(), font: ThemeFont = ThemeFont(),
         directoryIconTint: String = "#4A9EFF", lightColors: ThemeColors? = nil) {
        self.name = name
        self.colors = colors
        self.font = font
        self.directoryIconTint = directoryIconTint
        self.lightColors = lightColors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名"
        colors = try c.decodeIfPresent(ThemeColors.self, forKey: .colors) ?? ThemeColors()
        font = try c.decodeIfPresent(ThemeFont.self, forKey: .font) ?? ThemeFont()
        directoryIconTint = try c.decodeIfPresent(String.self, forKey: .directoryIconTint) ?? "#4A9EFF"
        lightColors = try c.decodeIfPresent(ThemeColors.self, forKey: .lightColors)
    }
}

struct ThemeColors: Codable, Hashable {
    var background: String
    var paneBackground: String
    var alternateRow: String
    var selection: String
    var foreground: String
    var secondaryText: String
    var centerBarBackground: String
    var destructive: String
    // U1 双主题设计令牌（v2.2 设计稿）。缺字段给中性默认值兜底。
    var titleBackground: String
    var headerBackground: String
    var rowEven: String
    var rowOdd: String
    var selFolder: String
    var selFile: String
    var accent: String
    var hover: String
    var centerBtn: String
    var centerBtnHot: String
    var tabBarBackground: String
    var pathBarBackground: String
    var pathBarStroke: String
    var commandBarBackground: String
    var diskTrack: String
    var iconDoc: String
    var iconZip: String

    init(background: String = "#1E1E2E", paneBackground: String = "#181825",
         alternateRow: String = "#232334", selection: String = "#89B4FA",
         foreground: String = "#CDD6F4", secondaryText: String = "#7F849C",
         centerBarBackground: String = "#11111B", destructive: String = "#F38BA8",
         titleBackground: String = "#1B1B22", headerBackground: String = "#242430",
         rowEven: String = "#232334", rowOdd: String = "#181825",
         selFolder: String = "#3A4A6B", selFile: String = "#33415E",
         accent: String = "#89B4FA", hover: String = "#2A2B38",
         centerBtn: String = "#1F1F2A", centerBtnHot: String = "#2A2B38",
         tabBarBackground: String = "#1B1B24", pathBarBackground: String = "#11111B",
         pathBarStroke: String = "#33334A", commandBarBackground: String = "#0E0E15",
         diskTrack: String = "#33334A", iconDoc: String = "#8A9CF5", iconZip: String = "#E5C07B") {
        self.background = background
        self.paneBackground = paneBackground
        self.alternateRow = alternateRow
        self.selection = selection
        self.foreground = foreground
        self.secondaryText = secondaryText
        self.centerBarBackground = centerBarBackground
        self.destructive = destructive
        self.titleBackground = titleBackground
        self.headerBackground = headerBackground
        self.rowEven = rowEven
        self.rowOdd = rowOdd
        self.selFolder = selFolder
        self.selFile = selFile
        self.accent = accent
        self.hover = hover
        self.centerBtn = centerBtn
        self.centerBtnHot = centerBtnHot
        self.tabBarBackground = tabBarBackground
        self.pathBarBackground = pathBarBackground
        self.pathBarStroke = pathBarStroke
        self.commandBarBackground = commandBarBackground
        self.diskTrack = diskTrack
        self.iconDoc = iconDoc
        self.iconZip = iconZip
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ThemeColors()
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? d.background
        paneBackground = try c.decodeIfPresent(String.self, forKey: .paneBackground) ?? d.paneBackground
        alternateRow = try c.decodeIfPresent(String.self, forKey: .alternateRow) ?? d.alternateRow
        selection = try c.decodeIfPresent(String.self, forKey: .selection) ?? d.selection
        foreground = try c.decodeIfPresent(String.self, forKey: .foreground) ?? d.foreground
        secondaryText = try c.decodeIfPresent(String.self, forKey: .secondaryText) ?? d.secondaryText
        centerBarBackground = try c.decodeIfPresent(String.self, forKey: .centerBarBackground) ?? d.centerBarBackground
        destructive = try c.decodeIfPresent(String.self, forKey: .destructive) ?? d.destructive
        titleBackground = try c.decodeIfPresent(String.self, forKey: .titleBackground) ?? d.titleBackground
        headerBackground = try c.decodeIfPresent(String.self, forKey: .headerBackground) ?? d.headerBackground
        rowEven = try c.decodeIfPresent(String.self, forKey: .rowEven) ?? d.rowEven
        rowOdd = try c.decodeIfPresent(String.self, forKey: .rowOdd) ?? d.rowOdd
        selFolder = try c.decodeIfPresent(String.self, forKey: .selFolder) ?? d.selFolder
        selFile = try c.decodeIfPresent(String.self, forKey: .selFile) ?? d.selFile
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? d.accent
        hover = try c.decodeIfPresent(String.self, forKey: .hover) ?? d.hover
        centerBtn = try c.decodeIfPresent(String.self, forKey: .centerBtn) ?? d.centerBtn
        centerBtnHot = try c.decodeIfPresent(String.self, forKey: .centerBtnHot) ?? d.centerBtnHot
        tabBarBackground = try c.decodeIfPresent(String.self, forKey: .tabBarBackground) ?? d.tabBarBackground
        pathBarBackground = try c.decodeIfPresent(String.self, forKey: .pathBarBackground) ?? d.pathBarBackground
        pathBarStroke = try c.decodeIfPresent(String.self, forKey: .pathBarStroke) ?? d.pathBarStroke
        commandBarBackground = try c.decodeIfPresent(String.self, forKey: .commandBarBackground) ?? d.commandBarBackground
        diskTrack = try c.decodeIfPresent(String.self, forKey: .diskTrack) ?? d.diskTrack
        iconDoc = try c.decodeIfPresent(String.self, forKey: .iconDoc) ?? d.iconDoc
        iconZip = try c.decodeIfPresent(String.self, forKey: .iconZip) ?? d.iconZip
    }
}

struct ThemeFont: Codable, Hashable {
    var fileList: Double
    var pathBar: Double

    init(fileList: Double = 13, pathBar: Double = 12) {
        self.fileList = fileList
        self.pathBar = pathBar
    }
}

// MARK: - Hex 解析（UI 层转 Color 用；非法格式返回 nil → 扫描层标记加载失败）

enum HexColor {
    static func rgba(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: UInt64
        if s.count == 6 {
            r = (value >> 16) & 0xFF; g = (value >> 8) & 0xFF; b = value & 0xFF; a = 0xFF
        } else {
            r = (value >> 24) & 0xFF; g = (value >> 16) & 0xFF; b = (value >> 8) & 0xFF; a = value & 0xFF
        }
        return (Double(r) / 255, Double(g) / 255, Double(b) / 255, Double(a) / 255)
    }

    /// 主题是否合法：所有颜色字段都能解析。
    static func validate(_ theme: AppTheme) -> Bool {
        let all = [theme.colors.background, theme.colors.paneBackground, theme.colors.alternateRow,
                   theme.colors.selection, theme.colors.foreground, theme.colors.secondaryText,
                   theme.colors.centerBarBackground, theme.colors.destructive, theme.directoryIconTint]
        return all.allSatisfy { rgba($0) != nil }
    }
}

// MARK: - 内置 4 套

extension AppTheme {
    /// U1 v2.1 设计稿：深色主色板
    private static let darkPalette = ThemeColors(
        background: "#1B1C21", paneBackground: "#202127",
        alternateRow: "#232329", selection: "#33415E",
        foreground: "#E6E8EE", secondaryText: "#9DA3B0",
        centerBarBackground: "#17181B", destructive: "#F38BA8",
        titleBackground: "#232429", headerBackground: "#26272E",
        rowEven: "#232329", rowOdd: "#202125",
        selFolder: "#3A4A6B", selFile: "#33415E",
        accent: "#4E8CFF", hover: "#2A2B33",
        centerBtn: "#1F2026", centerBtnHot: "#2A2B33",
        tabBarBackground: "#1E1F25", pathBarBackground: "#17181D",
        pathBarStroke: "#33343D", commandBarBackground: "#141519",
        diskTrack: "#2C2D35", iconDoc: "#8A9CF5", iconZip: "#E5C07B")

    /// U1 v2.1 设计稿：浅色主色板（偶数行浅灰间隔）
    private static let lightPalette = ThemeColors(
        background: "#F5F6F8", paneBackground: "#FFFFFF",
        alternateRow: "#F2F3F5", selection: "#C9D2DE",
        foreground: "#3A3F4A", secondaryText: "#6B7180",
        centerBarBackground: "#E9EAEE", destructive: "#D70015",
        titleBackground: "#ECEEF1", headerBackground: "#F0F1F4",
        rowEven: "#F2F3F5", rowOdd: "#FFFFFF",
        selFolder: "#C9D2DE", selFile: "#E2E6EB",
        accent: "#3E7BFA", hover: "#DDE1E7",
        centerBtn: "#F7F8FA", centerBtnHot: "#DDE1E7",
        tabBarBackground: "#F0F1F4", pathBarBackground: "#FFFFFF",
        pathBarStroke: "#D5D9DF", commandBarBackground: "#FFFFFF",
        diskTrack: "#D5D9DF", iconDoc: "#7C6BD6", iconZip: "#B8860B")

    static let builtIns: [AppTheme] = [
        AppTheme(name: "Light",
                 colors: lightPalette,
                 directoryIconTint: "#3E7BFA"),
        // Dark 携带配对浅色板：跟随系统模式下按系统外观自动切换
        AppTheme(name: "Dark",
                 colors: darkPalette,
                 directoryIconTint: "#6AA7FF",
                 lightColors: lightPalette),
        AppTheme(name: "TC-Classic",
                 colors: ThemeColors(background: "#000080", paneBackground: "#000080",
                                     alternateRow: "#0000A0", selection: "#008080",
                                     foreground: "#FFFF00", secondaryText: "#C0C000",
                                     centerBarBackground: "#000060", destructive: "#FF4040",
                                     titleBackground: "#000080", headerBackground: "#000090",
                                     rowEven: "#0000A0", rowOdd: "#000080",
                                     selFolder: "#006080", selFile: "#005070",
                                     accent: "#00FFFF", hover: "#0000B0",
                                     centerBtn: "#000070", centerBtnHot: "#0000C0",
                                     tabBarBackground: "#000070", pathBarBackground: "#000060",
                                     pathBarStroke: "#0040A0", commandBarBackground: "#000040",
                                     diskTrack: "#003080", iconDoc: "#C0C000", iconZip: "#FFA000"),
                 directoryIconTint: "#00FFFF"),
        AppTheme(name: "Midnight",
                 colors: ThemeColors(), // §3 样例值即默认
                 directoryIconTint: "#89B4FA"),
    ]
}
