import SwiftUI

@main
struct DualVaultApp: App {
    @StateObject private var services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandMenu("皮肤") {
                if let store = AppServices.shared.themeStore {
                    // U1：三态模式（跟随系统/浅色/深色）
                    Menu("主题模式") {
                        ForEach(ThemeMode.allCases, id: \.self) { m in
                            Button(store.mode == m ? "✓ \(m.label)" : m.label) {
                                store.mode = m
                            }
                        }
                    }
                    Divider()
                    ForEach(store.themes) { theme in
                        Button(theme.name == store.currentName ? "✓ \(theme.name)" : theme.name) {
                            store.select(theme.name)
                        }
                    }
                    if !store.failedNames.isEmpty {
                        Divider()
                        ForEach(store.failedNames, id: \.self) { name in
                            Button("⚠ \(name) 加载失败——点击移除") {
                                store.removeFailed(name)
                            }
                        }
                    }
                } else {
                    Text("皮肤不可用")
                }
                Divider()
                Button("重载用户主题（⌃⌘R）") {
                    AppServices.shared.themeStore?.reload()
                }
            }
            CommandMenu("工具") {
                Button("批量重命名…") { services.model?.requestRename() }
                    .disabled(services.model == nil)
                Button("按通配符选择…") { services.model?.activeSheet = .wildcard }
                    .disabled(services.model == nil)
                Button("计算文件夹大小") { services.model?.computeFolderSize() }
                    .disabled(services.model == nil)
                Button("校验和…") { services.model?.requestChecksum() }
                    .disabled(services.model == nil)
                Divider()
                Button("分割文件…") { services.model?.requestSplitDialog() }
                    .disabled(services.model == nil)
                Button("合并分卷") { services.model?.requestJoin() }
                    .disabled(services.model == nil)
                Button("修改日期…") { services.model?.requestTouchDialog() }
                    .disabled(services.model == nil)
                Divider()
                Button("查找重复文件…") { services.model?.requestDuplicates() }
                    .disabled(services.model == nil)
                Button("App 卸载器…") { services.model?.requestUninstall() }
                    .disabled(services.model == nil)
                Divider()
                Toggle("同步浏览", isOn: Binding(
                    get: { services.model?.syncBrowse ?? false },
                    set: { services.model?.syncBrowse = $0 }))
                Divider()
                Button("目录热列表（⌘D）") { services.model?.requestHotlist() }
                    .disabled(services.model == nil)
            }
            CommandMenu("前往") {
                Button("添加当前目录到收藏（⌘D 热列表）") {
                    services.model?.addCurrentToFavorites()
                }
                .disabled(services.model == nil)

                if !services.favorites.isEmpty {
                    Divider()
                    ForEach(Array(services.favorites.enumerated()), id: \.offset) { _, url in
                        Button(url.path) {
                            services.model?.visit(url)
                        }
                    }
                    Divider()
                    Button("清除全部收藏") {
                        services.favorites.removeAll()
                    }
                }

                if let recent = services.model?.focusedPane.visitHistory.prefix(10), !recent.isEmpty {
                    Divider()
                    Menu("最近访问") {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, url in
                            Button(url.path) {
                                services.model?.visit(url)
                            }
                        }
                    }
                }
            }
            CommandGroup(after: .newItem) {
                Button("新建标签（⌘T）") {
                    services.model?.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}
