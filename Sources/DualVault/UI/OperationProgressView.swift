import SwiftUI

/// 操作进度窗：文件进度 + 字节进度 + 取消。
struct OperationProgressView: View {
    @Environment(\.theme) private var theme
    let title: String
    @ObservedObject var queue: OperationQueue
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline).lineLimit(2)
            ProgressView(value: fraction)
                .frame(width: 320)
            HStack {
                Text("\(queue.progressFiles.done)/\(queue.progressFiles.total) 项")
                Spacer()
                Text("\(Theme.sizeString(queue.progressBytes.done)) / \(Theme.sizeString(queue.progressBytes.total))")
            }
            .font(.system(size: 11))
            .foregroundColor(theme.secondaryText)
            Button("取消") { onCancel() }
        }
        .padding(24)
        .frame(minWidth: 400)
    }

    private var fraction: Double {
        let (_, total) = queue.progressBytes
        guard total > 0 else { return 0 }
        return min(1, Double(queue.progressBytes.done) / Double(total))
    }
}
