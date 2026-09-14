import SwiftUI

/// 中央按钮栏（U1 v2.2）：9 按钮 = 复制×2 / 移动×2 / 同步 / 交换 / 同路径 / 新建文件夹 / 删除。
/// 全部操作经 BrowserModel（TransferPlanner 唯一方向入口 + OperationQueue）。
/// F5–F8 已移除，这是上述操作的唯一入口。
struct CenterActionBar: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(spacing: 10) {
            Group {
                actionButton(icon: "arrow.left", label: "从右向左复制", hot: true)
                    { model.requestTransfer(kind: .copy) }
                actionButton(icon: "arrow.right", label: "从左向右复制", hot: true)
                    { model.requestTransfer(kind: .copy) }
                actionButton(icon: "arrow.left.to.line.compact", label: "从右向左移动")
                    { model.requestTransfer(kind: .move) }
                actionButton(icon: "arrow.right.to.line.compact", label: "从左向右移动")
                    { model.requestTransfer(kind: .move) }
            }
            separator()
            Group {
                actionButton(icon: "arrow.triangle.2.circlepath", label: "比较并同步两栏")
                    { model.activeSheet = .compare }
                actionButton(icon: "arrow.left.arrow.right", label: "交换左右路径")
                    { model.swapPaths() }
                actionButton(icon: "equal", label: "对侧栏设为当前路径")
                    { model.equalizePaths() }
            }
            separator()
            Group {
                actionButton(icon: "folder.badge.plus", label: "新建文件夹（焦点栏）", hot: true)
                    { model.requestNewFolder() }
                actionButton(icon: "trash", label: "删除到废纸篓")
                    { model.deleteSelection() }
                    .disabled(model.focusedPane.selection.isEmpty)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(width: 56)
        .background(theme.centerBarBackground)
    }

    private func separator() -> some View {
        Rectangle()
            .fill(theme.pathBarStroke)
            .frame(width: 32, height: 1)
    }

    private func actionButton(icon: String, label: String, hot: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(hot ? theme.foreground : theme.secondaryText)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(hot ? theme.centerBtnHot : theme.centerBtn))
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}
