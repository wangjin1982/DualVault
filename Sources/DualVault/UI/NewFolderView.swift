import SwiftUI

/// F7 新建文件夹：输入名称。
struct NewFolderView: View {
    let side: PaneSide
    let onCreate: (String, PaneSide) -> Void
    let onCancel: () -> Void

    @State private var name: String = "未命名文件夹"

    var body: some View {
        VStack(spacing: 14) {
            Text("新建文件夹").font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { onCreate(name, side) }
            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("创建") { onCreate(name, side) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
