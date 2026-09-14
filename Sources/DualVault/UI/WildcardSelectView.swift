import SwiftUI

/// E1-2 按通配符选择：选择 / 加入选择 / 反选匹配 / 取消选择。
struct WildcardSelectView: View {
    let onApply: (String, BrowserModel.WildcardMode) -> Void
    let onCancel: () -> Void

    @State private var pattern: String = "*."

    var body: some View {
        VStack(spacing: 14) {
            Text("按通配符选择").font(.headline)
            TextField("模式（* 任意长度，? 单字符）", text: $pattern)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { onApply(pattern, .select) }
            HStack(spacing: 10) {
                Button("选择") { onApply(pattern, .select) }
                Button("加入选择") { onApply(pattern, .addToSelection) }
                Button("反选匹配") { onApply(pattern, .invert) }
                Button("取消选择") { onApply(pattern, .deselect) }
            }
            Button("关闭", action: onCancel).keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }
}
