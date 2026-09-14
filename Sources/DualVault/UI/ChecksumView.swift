import SwiftUI

/// E1-5 校验和：MD5/SHA256 展示 + 粘贴比对。CryptoKit 计算，后台线程。
struct ChecksumView: View {
    @Environment(\.theme) private var theme
    let url: URL
    let onClose: () -> Void

    @State private var md5: String = "计算中…"
    @State private var sha256: String = "计算中…"
    @State private var pasted: String = ""
    @State private var compareResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(url.lastPathComponent).font(.headline)
            checksumRow("MD5", value: md5)
            checksumRow("SHA-256", value: sha256)

            TextField("粘贴 hash 比对", text: $pasted)
                .textFieldStyle(.roundedBorder)
                .onChange(of: pasted) { value in
                    compare(value)
                }
            if let result = compareResult {
                Text(result)
                    .foregroundColor(result.hasPrefix("✓") ? theme.foreground : theme.destructive)
            }
            HStack {
                Button("复制 SHA-256") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sha256, forType: .string)
                }
                .disabled(sha256.hasPrefix("计算"))
                Spacer()
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: compute)
    }

    private func checksumRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func compute() {
        DispatchQueue.global(qos: .userInitiated).async {
            let m = (try? ChecksumAlgorithm.md5.compute(of: url)) ?? "计算失败"
            let s = (try? ChecksumAlgorithm.sha256.compute(of: url)) ?? "计算失败"
            DispatchQueue.main.async {
                md5 = m; sha256 = s
            }
        }
    }

    private func compare(_ input: String) {
        let cleaned = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard ChecksumAlgorithm.isValidHex(cleaned) else {
            compareResult = cleaned.isEmpty ? nil : "不是合法的 hash 字符串"
            return
        }
        if cleaned == md5.lowercased() {
            compareResult = "✓ 与 MD5 匹配"
        } else if cleaned == sha256.lowercased() {
            compareResult = "✓ 与 SHA-256 匹配"
        } else {
            compareResult = "✗ 与文件不匹配"
        }
    }
}
