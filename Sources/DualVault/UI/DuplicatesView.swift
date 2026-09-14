import SwiftUI

/// F1-B 重复文件查找结果：按组分栏展示，组内保留首项、其余删除（废纸篓 + 可撤销）。
struct DuplicatesView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: BrowserModel
    let onClose: () -> Void

    @State private var groups: [DuplicateGroup]?
    @State private var searching = false
    @State private var removed: Set<Int> = []
    @State private var keepChoice: [Int: URL] = [:]
    @State private var scanProgress: (done: Int, total: Int)?
    @State private var scanWork: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("重复文件查找（左栏 + 右栏子树）").font(.headline)
                Spacer()
                Button(searching ? "查找中…" : "开始查找") { runSearch() }
                    .disabled(searching)
                if searching {
                    if let p = scanProgress {
                        Text("\(p.done)/\(p.total)")
                            .font(.system(size: 10))
                            .foregroundColor(theme.secondaryText)
                    }
                    Button("取消") {
                        scanWork?.cancel()
                        searching = false
                    }
                    .font(.system(size: 10))
                }
            }
            if let groups = groups {
                if groups.isEmpty {
                    Text("未发现重复文件").foregroundColor(theme.secondaryText)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                                if !removed.contains(index) {
                                    groupRow(index: index, group: group)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 380)
                }
            }
            HStack {
                Spacer()
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 400)
    }

    private func groupRow(index: Int, group: DuplicateGroup) -> some View {
        let keep = keepChoice[index] ?? group.files[0]
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("组 \(index + 1)")
                    .font(.caption).foregroundColor(theme.secondaryText)
                Text(Theme.sizeString(group.size))
                    .font(.caption).foregroundColor(theme.secondaryText)
                Spacer()
                Button("保留所选，删除其余 \(group.files.count - 1) 个") {
                    model.deleteDuplicates(keeping: keep, in: group)
                    removed.insert(index)
                }
                .controlSize(.small)
            }
            ForEach(Array(group.files.enumerated()), id: \.offset) { i, url in
                HStack {
                    // F4-3：组内自选保留项
                    Button(action: { keepChoice[index] = url }) {
                        Image(systemName: url == keep ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(url == keep ? theme.directoryIconTint : theme.secondaryText)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    Text(url.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .foregroundColor(url == keep ? theme.foreground : theme.secondaryText)
                }
            }
        }
        .padding(8)
        .background(theme.paneBackground)
        .cornerRadius(6)
    }

    private func runSearch() {
        searching = true
        groups = nil
        removed.removeAll()
        keepChoice.removeAll()
        var cancelled = false
        let work = DispatchWorkItem {
            model.findDuplicates(progress: { done, total in
                scanProgress = (done, total)
            }) { result in
                searching = false
                scanProgress = nil
                switch result {
                case .success(let g): groups = g
                case .failure(let error):
                    groups = []
                    if (error as? OperationError) != .cancelled {
                        model.alertMessage = error.localizedDescription
                    }
                }
            }
        }
        scanWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}
