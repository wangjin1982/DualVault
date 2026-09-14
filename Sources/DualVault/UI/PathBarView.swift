import SwiftUI

struct PathBarView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var pane: PaneState

    var body: some View {
        HStack(spacing: 4) {
            Button(action: pane.goUp) {
                Image(systemName: "arrow.up.to.line")
            }
            .buttonStyle(.borderless)
            .help("上级目录")

            Button(action: pane.goBack) {
                Image(systemName: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .disabled(pane.backStack.isEmpty)
            .help("后退")

            Button(action: pane.goForward) {
                Image(systemName: "chevron.forward")
            }
            .buttonStyle(.borderless)
            .disabled(pane.forwardStack.isEmpty)
            .help("前进")

            // E1-1 输入即过滤
            if pane.isZipBrowsing {
                Text(pane.displayPath)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(theme.pathBarBackground)
                    .cornerRadius(4)
                    .help("zip 内路径只读")
            } else {
                TextField("路径", text: $pane.editablePath, onCommit: commitPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
            }

            // F3-4 缩略图开关（每栏独立）
            Button(action: { pane.showThumbnails.toggle() }) {
                Image(systemName: pane.showThumbnails ? "photo.fill" : "photo")
                    .font(.system(size: 12))
                    .foregroundColor(pane.showThumbnails ? theme.selection : theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("图片缩略图开关")

            // E1-1 输入即过滤
            HStack(spacing: 2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText)
                TextField("过滤", text: $pane.filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 110)
                if !pane.filter.isEmpty {
                    Button(action: { pane.filter = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(theme.pathBarBackground)
            .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.headerBackground)
    }

    private func commitPath() {
        let expanded = (pane.editablePath as NSString).expandingTildeInPath
        guard !expanded.isEmpty else {
            pane.editablePath = pane.url.path
            return
        }
        let url = URL(fileURLWithPath: expanded)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            pane.lastError = "路径不存在：\(expanded)"
            pane.editablePath = pane.url.path
            return
        }
        pane.navigate(to: url)
    }
}
