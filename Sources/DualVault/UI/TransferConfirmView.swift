import SwiftUI

/// 传输确认窗：方向、N 项、总大小（C8）。
struct TransferConfirmView: View {
    @Environment(\.theme) private var theme
    let draft: TransferDraft
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(draft.kind == .copy ? "复制" : "移动")
                .font(.headline)
            HStack(spacing: 8) {
                paneLabel(draft.plan.sourcePane, path: draft.plan.sources.first?.deletingLastPathComponent().path ?? "")
                Image(systemName: draft.directionArrow == "→" ? "arrow.right" : "arrow.left")
                    .foregroundColor(theme.selection)
                paneLabel(draft.plan.destinationPane, path: draft.plan.destination.path)
            }
            Text("\(draft.totalFiles) 项，共 \(Theme.sizeString(draft.totalBytes))")
                .foregroundColor(theme.secondaryText)
            if let note = draft.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundColor(theme.destructive)
            }
            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("确认", action: onConfirm).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private func paneLabel(_ side: PaneSide, path: String) -> some View {
        VStack {
            Text(side == .left ? "左栏" : "右栏")
                .font(.caption)
                .foregroundColor(theme.secondaryText)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180)
        }
    }
}
