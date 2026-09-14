import SwiftUI

struct StatusBarView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var pane: PaneState
    @ObservedObject var model: BrowserModel

    var body: some View {
        HStack(spacing: 12) {
            Text("共 \(pane.displayedItems.count) 项")
            if !pane.selection.isEmpty {
                Text("已选 \(pane.selection.count) 项，总大小 \(Theme.sizeString(pane.selectedTotalSize))")
            }
            if let error = pane.lastError {
                Text(error)
                    .foregroundColor(theme.destructive)
                    .lineLimit(1)
            }
            Spacer()
            // U1：磁盘余量迷你进度条（占用 >90% 变警示色）
            if let free = pane.freeSpaceString {
                if let usedRatio = pane.diskUsedRatio {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.diskTrack)
                            Capsule()
                                .fill(usedRatio > 0.9 ? theme.destructive : theme.accent)
                                .frame(width: max(4, geo.size.width * usedRatio))
                        }
                    }
                    .frame(width: 56, height: 5)
                }
                Text(free)
            }
            // E1-4 文件夹大小（触发式）
            if let result = model.folderSizeResult {
                Text(result)
                    .lineLimit(1)
                Button("清除") { model.cancelFolderSize() }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(theme.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.statusBackground)
    }
}
