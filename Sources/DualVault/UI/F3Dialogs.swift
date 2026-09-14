import SwiftUI

/// F3-5 分割文件：指定每卷大小（MB）。
struct SplitDialogView: View {
    let file: URL
    let onApply: (Int) -> Void
    let onCancel: () -> Void

    @State private var sizeMB: String = "10"

    var body: some View {
        VStack(spacing: 14) {
            Text("分割 \(file.lastPathComponent)").font(.headline)
            HStack {
                Text("每卷大小（MB）：")
                TextField("10", text: $sizeMB)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            Text("将生成 \(file.lastPathComponent).part1、.part2…（同目录）")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("分割") {
                    if let mb = Int(sizeMB), mb > 0 { onApply(mb) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Int(sizeMB) == nil || Int(sizeMB)! <= 0)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// F3-5 修改日期。
struct TouchDialogView: View {
    let file: URL
    let onApply: (Date) -> Void
    let onCancel: () -> Void

    @State private var date: Date = Date()

    var body: some View {
        VStack(spacing: 14) {
            Text("修改日期").font(.headline)
            Text(file.lastPathComponent).foregroundColor(.secondary)
            DatePicker("修改日期", selection: $date)
                .labelsHidden()
            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("应用") { onApply(date) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
