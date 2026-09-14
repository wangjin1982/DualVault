import Foundation

struct InstalledApp: Equatable, Identifiable {
    let bundleURL: URL
    let name: String
    let version: String
    let size: Int64
    let bundleID: String
    /// /System/Applications 等系统目录：只读标注，不参与卸载。
    let isSystem: Bool
    var id: URL { bundleURL }
}

struct RelatedFile: Equatable, Identifiable {
    let path: URL
    let kind: String
    /// 高 = bundle id 精确匹配；低 = 按可执行名/应用名猜测。
    let confidence: Confidence
    enum Confidence: String, Equatable {
        case high = "高置信", low = "低置信"
    }
    var id: URL { path }
}

/// App 扫描与关联文件收集（纯逻辑，目录全部可注入单测）。
enum AppScanner {

    /// 安全红线：这些前缀一律不碰。
    static let excludedPrefixes = ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/Library/Extensions"]

    // MARK: - 扫描已安装 App

    static func scan(applicationsDirs: [URL]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let fm = FileManager.default
        for dir in applicationsDirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".app") {
                let bundleURL = dir.appendingPathComponent(name)
                let info = readInfoPlist(bundleURL: bundleURL)
                let appName = info?["CFBundleName"] as? String
                    ?? info?["CFBundleDisplayName"] as? String
                    ?? name.replacingOccurrences(of: ".app", with: "")
                let version = info?["CFBundleShortVersionString"] as? String ?? "?"
                let bundleID = info?["CFBundleIdentifier"] as? String ?? ""
                apps.append(InstalledApp(
                    bundleURL: bundleURL,
                    name: appName,
                    version: version,
                    size: CopyEngine.totalSize(of: [bundleURL]),
                    bundleID: bundleID,
                    isSystem: dir.path.hasPrefix("/System")))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func readInfoPlist(bundleURL: URL) -> [String: Any]? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plist) as? [String: Any]
    }

    // MARK: - 关联文件收集

    /// Library 下扫描的子目录（相对路径）。
    static let librarySubdirs = [
        "Preferences", "Caches", "Application Support",
        "Containers", "Group Containers", "Saved Application State",
        "Logs", "LaunchAgents",
    ]

    static func relatedFiles(app: InstalledApp, libraryRoots: [URL]) -> [RelatedFile] {
        guard !app.isSystem else { return [] }        // 系统 App 不卸载
        let fm = FileManager.default
        var results: [RelatedFile] = []
        var seen: Set<String> = []

        func consider(_ url: URL, kind: String) {
            let path = url.path
            guard !seen.contains(path) else { return }
            // 安全红线
            guard !excludedPrefixes.contains(where: { path.hasPrefix($0) }) else { return }
            // 匹配规则：bundle id 精确 > 应用名前缀
            let base = url.lastPathComponent
            if !app.bundleID.isEmpty && base.hasPrefix(app.bundleID) {
                seen.insert(path)
                results.append(RelatedFile(path: url, kind: kind, confidence: .high))
            } else if base.hasPrefix(app.name) || base.hasPrefix(app.name.replacingOccurrences(of: " ", with: "")) {
                seen.insert(path)
                results.append(RelatedFile(path: url, kind: kind, confidence: .low))
            }
        }

        for root in libraryRoots {
            for sub in librarySubdirs {
                let dir = root.appendingPathComponent(sub)
                guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                for name in names {
                    consider(dir.appendingPathComponent(name), kind: sub)
                }
            }
        }
        return results.sorted { $0.path.path < $1.path.path }
    }

    /// 卸载计划 = App bundle + 勾选关联文件。供确认窗展示。
    static func uninstallTargets(app: InstalledApp, related: [RelatedFile]) -> [URL] {
        [app.bundleURL] + related.map(\.path)
    }

    /// 总大小。
    static func totalSize(of urls: [URL]) -> Int64 {
        CopyEngine.totalSize(of: urls)
    }
}
