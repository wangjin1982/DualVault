import SwiftUI

/// F2-B App 卸载器：扫描 → 关联收集（逐项勾选）→ 确认（总大小/数量/运行中警告）→ DeleteOperation。
struct UninstallerView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: BrowserModel
    let onClose: () -> Void

    @State private var apps: [InstalledApp] = []
    @State private var scanning = false
    @State private var selected: InstalledApp?
    @State private var related: [RelatedFile] = []
    @State private var checked: Set<URL> = []
    @State private var scanningRelated = false
    @State private var scanWork: DispatchWorkItem?

    private let appDirs = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("App 卸载器").font(.headline)
                Spacer()
                Button(scanning ? "扫描中…" : "重新扫描") { runScan() }
                    .disabled(scanning)
            }
            HSplitView {
                appList
                relatedPanel
            }
            .frame(minHeight: 320)
            HStack {
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                if let app = selected, !app.isSystem {
                    Button("卸载（\(AppScanner.uninstallTargets(app: app, related: chosenRelated).count) 项，\(Theme.sizeString(totalSize))）") {
                        confirmAndUninstall(app: app)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosenRelated.isEmpty && apps.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 460)
        .onAppear(perform: runScan)
    }

    private var chosenRelated: [RelatedFile] {
        related.filter { checked.contains($0.path) }
    }

    private var totalSize: Int64 {
        guard let app = selected else { return 0 }
        return AppScanner.totalSize(of: AppScanner.uninstallTargets(app: app, related: chosenRelated))
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("已安装应用").font(.caption).foregroundColor(theme.secondaryText)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(apps) { app in
                        Button(action: { select(app) }) {
                            HStack {
                                Text(app.name).lineLimit(1)
                                if app.isSystem {
                                    Text("系统").font(.caption2)
                                        .padding(.horizontal, 4)
                                        .background(theme.secondaryText.opacity(0.3))
                                        .cornerRadius(3)
                                }
                                Spacer()
                                Text(Theme.sizeString(app.size))
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.secondaryText)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(selected == app ? theme.selection.opacity(0.25) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 240)
    }

    private var relatedPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scanningRelated ? "正在扫描关联文件…" : "关联文件（勾选参与卸载）")
                .font(.caption).foregroundColor(theme.secondaryText)
            if let app = selected, app.isSystem {
                Text("系统应用只读，不参与卸载")
                    .foregroundColor(theme.secondaryText)
            } else if related.isEmpty && !scanningRelated {
                Text("选择左侧 App 后自动扫描 ~/Library 关联项")
                    .foregroundColor(theme.secondaryText)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(related) { item in
                            Toggle(isOn: Binding(
                                get: { checked.contains(item.path) },
                                set: { on in
                                    if on { checked.insert(item.path) } else { checked.remove(item.path) }
                                })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(item.path.pathComponents.suffix(2).joined(separator: "/"))
                                            .font(.system(size: 11, design: .monospaced))
                                            .lineLimit(1)
                                        Spacer()
                                        if item.confidence == .low {
                                            Text("低置信")
                                                .font(.caption2)
                                                .foregroundColor(theme.destructive)
                                        }
                                    }
                                    Text(item.kind)
                                        .font(.caption2)
                                        .foregroundColor(theme.secondaryText)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 6)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380)
    }

    private func runScan() {
        scanning = true
        selected = nil
        related = []
        scanWork?.cancel()
        let work = DispatchWorkItem {
            let result = AppScanner.scan(applicationsDirs: appDirs)
            DispatchQueue.main.async {
                apps = result
                scanning = false
            }
        }
        scanWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func select(_ app: InstalledApp) {
        selected = app
        related = []
        checked.removeAll()
        guard !app.isSystem else { return }
        scanningRelated = true
        scanWork?.cancel()
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"),
            URL(fileURLWithPath: "/Library"),
        ]
        let work = DispatchWorkItem {
            let result = AppScanner.relatedFiles(app: app, libraryRoots: roots)
            DispatchQueue.main.async {
                related = result
                checked = Set(result.map(\.path))
                scanningRelated = false
            }
        }
        scanWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func confirmAndUninstall(app: InstalledApp) {
        let targets = AppScanner.uninstallTargets(app: app, related: chosenRelated)
        let running = model.runningAppPaths.contains(app.bundleURL.path)
        let message = "将把 \(targets.count) 项移入废纸篓（可 ⌘Z 撤销）"
            + (running ? "。\n\n⚠️ 该 App 正在运行，卸载后请手动退出。" : "")
        let alert = NSAlert()
        alert.messageText = "卸载 \(app.name)？"
        alert.informativeText = message
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.runUninstall(app: app, related: chosenRelated)
            onClose()
        }
    }
}
