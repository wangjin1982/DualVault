import SwiftUI
import AppKit

// MARK: - 侧栏数据模型（U1.1：参照 ForkLift —— 设备/最近/标签/收藏夹 + 可展开文件夹树）

/// 侧栏条目。
struct SidebarItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case root(URL)          // 固定入口（设备/最近/收藏夹）
        case folder(URL)        // 可展开的文件夹树节点
    }
    let id: URL
    let name: String
    let kind: Kind
    let systemIcon: String
}

/// 文件夹树子目录枚举（过滤隐藏与包）。
enum FolderTree {
    static func children(of url: URL) -> [SidebarItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { SidebarItem(id: $0, name: $0.lastPathComponent, kind: .folder($0),
                               systemIcon: "folder") }
    }
}

// MARK: - 侧栏视图

struct SidebarView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: BrowserModel
    let side: PaneSide
    @ObservedObject var services: AppServices

    @State private var expanded: Set<String> = []
    @State private var treeCache: [String: [SidebarItem]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarSection(title: "设备", icon: "desktopcomputer") {
                    sidebarRow(SidebarItem(id: URL(fileURLWithPath: "/"),
                                           name: "Macintosh HD", kind: .root(URL(fileURLWithPath: "/")),
                                           systemIcon: "internaldrive"))
                    ForEach(devices, id: \.id) { vol in
                        sidebarRow(vol)
                    }
                }
                sidebarSection(title: "最近", icon: "clock") {
                    if let recents = services.model?.focusedPane.visitHistory.prefix(8), !recents.isEmpty {
                        ForEach(Array(recents.enumerated()), id: \.offset) { _, url in
                            sidebarRow(SidebarItem(id: url, name: url.lastPathComponent,
                                                   kind: .root(url), systemIcon: "clock"))
                        }
                    } else {
                        emptyHint("暂无最近访问")
                    }
                }
                sidebarSection(title: "收藏夹", icon: "star") {
                    if services.favorites.isEmpty {
                        emptyHint("⌘D 添加当前目录")
                    } else {
                        ForEach(services.favorites, id: \.path) { url in
                            sidebarRow(SidebarItem(id: url, name: url.lastPathComponent,
                                                   kind: .root(url), systemIcon: "star"))
                        }
                    }
                }
                sidebarSection(title: "标签", icon: "tag") {
                    ForEach(colorTags, id: \.name) { tag in
                        tagRow(tag)
                    }
                }
                sidebarSection(title: "位置", icon: "folder") {
                    folderTreeRow(URL(fileURLWithPath: NSHomeDirectory()), name: "主目录", depth: 0)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 150)
        .background(theme.paneBackground)
    }

    // MARK: 区块标题

    private func sidebarSection(title: String, icon: String,
                                @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(theme.secondaryText)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 3)
            content()
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(theme.secondaryText.opacity(0.6))
            .padding(.horizontal, 24)
            .padding(.vertical, 3)
    }

    // MARK: 行（AnyView 打断 body ↔ folderTreeRow 的递归类型推断）

    private func sidebarRow(_ item: SidebarItem) -> AnyView {
        AnyView(sidebarRowContent(item))
    }

    private func sidebarRowContent(_ item: SidebarItem) -> some View {
        let isCurrent = model.focusedPane.url.standardizedFileURL == item.id.standardizedFileURL
        return HStack(spacing: 5) {
            Image(systemName: item.systemIcon)
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryText)
                .frame(width: 14)
            Text(item.name)
                .font(.system(size: 11))
                .foregroundColor(theme.foreground)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(isCurrent ? theme.selFolder : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { navigate(item) }
        .contextMenu { sidebarMenu(for: item.id) }
    }

    /// 可展开文件夹树节点（U1.1：除双击外查看文件夹内容的第二种方式）。
    private func folderTreeRow(_ url: URL, name: String, depth: Int) -> AnyView {
        AnyView(folderTreeRowContent(url, name: name, depth: depth))
    }

    private func folderTreeRowContent(_ url: URL, name: String, depth: Int) -> some View {
        let key = url.path
        let isExpanded = expanded.contains(key)
        let isCurrent = model.focusedPane.url.standardizedFileURL == url.standardizedFileURL
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 10)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(url) }
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundColor(theme.accent)
                    .frame(width: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(url) }
                Text(name)
                    .font(.system(size: 11))
                    .foregroundColor(theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 14 + 4)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? theme.selFolder : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture { model.visit(url); model.focusedSide = side }
            .contextMenu { sidebarMenu(for: url) }

            if isExpanded {
                let children = treeCache[url.path] ?? []
                if children.isEmpty {
                    Text("（无子文件夹）")
                        .font(.system(size: 9))
                        .foregroundColor(theme.secondaryText.opacity(0.5))
                        .padding(.leading, CGFloat(depth) * 14 + 34)
                        .padding(.vertical, 2)
                } else {
                    ForEach(children) { child in
                        folderTreeRow(child.id, name: child.name, depth: depth + 1)
                    }
                }
            }
        }
    }

    private func toggle(_ url: URL) {
        let key = url.path
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
            treeCache[key] = FolderTree.children(of: url)
        }
    }

    private func navigate(_ item: SidebarItem) {
        model.visit(item.id)
        model.focusedSide = side
    }

    // MARK: 设备与标签

    private var devices: [SidebarItem] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.filter { $0.path != "/" }.map {
            SidebarItem(id: $0, name: $0.lastPathComponent, kind: .root($0),
                        systemIcon: "externaldrive")
        }
    }

    private struct ColorTag { let name: String; let color: Color }
    private var colorTags: [ColorTag] {
        [ColorTag(name: "红", color: Color.red), ColorTag(name: "橙", color: Color.orange),
         ColorTag(name: "黄", color: Color.yellow), ColorTag(name: "绿", color: Color.green),
         ColorTag(name: "蓝", color: Color.blue), ColorTag(name: "紫", color: Color.purple),
         ColorTag(name: "灰", color: Color.gray)]
    }

    private func tagRow(_ tag: ColorTag) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tag.color).frame(width: 9, height: 9)
            Text(tag.name)
                .font(.system(size: 11))
                .foregroundColor(theme.foreground)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help("标签过滤（规划中）")
    }

    // MARK: 右键菜单（U1.1 需求 3）

    @ViewBuilder
    private func sidebarMenu(for url: URL) -> some View {
        Button("在新标签打开") {
            model.newTab(in: side, at: url)
        }
        Button("添加到收藏夹") { services.addFavorite(url) }
        Divider()
        Button("在此处打开终端") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Terminal", url.path]
            try? process.run()
        }
        Divider()
        Button("拷贝路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }
}
