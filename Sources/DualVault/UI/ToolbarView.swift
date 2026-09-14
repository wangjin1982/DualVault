import SwiftUI

/// U1.2 顶部工具栏（ForkLift 风格）：透明标题栏融合 + 红绿灯让位，
/// 传输/同步/新建/删除集中在工具栏；双栏之间只留细分隔线（左右天然均衡）。
struct ToolbarView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: BrowserModel
    @Binding var sidebarVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 26)   // 红绿灯区（fullSizeContentView 让位）
            HStack(spacing: 2) {
                Color.clear.frame(width: 64)
                icon("sidebar.left", "显示/隐藏侧栏") { sidebarVisible.toggle() }
                sep()
                labeled("doc.on.doc", "复制到对侧") { model.requestTransfer(kind: .copy) }
                labeled("arrow.right.to.line.compact", "移动到对侧") { model.requestTransfer(kind: .move) }
                sep()
                icon("arrow.triangle.2.circlepath", "比较并同步两栏") { model.activeSheet = .compare }
                icon("arrow.left.arrow.right", "交换左右路径") { model.swapPaths() }
                icon("equal", "对侧栏设为当前路径") { model.equalizePaths() }
                sep()
                icon("folder.badge.plus", "新建文件夹（焦点栏）") { model.requestNewFolder() }
                icon("trash", "移到废纸篓") { model.deleteSelection() }
                    .disabled(model.focusedPane.selection.isEmpty)
                    .opacity(model.focusedPane.selection.isEmpty ? 0.35 : 1)
                Spacer()
                icon("terminal", "在此处打开终端") { model.openTerminal() }
                Color.clear.frame(width: 6)
            }
            .padding(.horizontal, 4)
            .frame(height: 34)
        }
        .background(theme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.pathBarStroke).frame(height: 1)
        }
    }

    private func sep() -> some View {
        Rectangle().fill(theme.pathBarStroke).frame(width: 1, height: 16).padding(.horizontal, 5)
    }

    private func icon(_ system: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13))
                .foregroundColor(theme.secondaryText)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.centerBtn))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func labeled(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: system).font(.system(size: 12))
                Text(label).font(.system(size: 12))
            }
            .foregroundColor(theme.accent)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.centerBtnHot))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("作用于焦点栏 → 对侧栏（方向自动）")
    }
}
