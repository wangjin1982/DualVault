import SwiftUI

/// 冲突对话框：逐项展示源/目标的大小与日期对比，四策略 + 应用到全部。
/// 传输与解压共用（payload 无关，由 ConflictSession.onResolve 接回）。
struct ConflictDialogView: View {
    @Environment(\.theme) private var theme
    let session: ConflictSession
    let onCancel: () -> Void

    @State private var perName: [String: ConflictStrategy] = [:]
    @State private var applyToAll: ConflictStrategy? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 12) {
            Text("目标已存在同名项（\(session.entries.count)）")
                .font(.headline)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(session.entries, id: \.sourceName) { entry in
                        row(for: entry)
                    }
                }
            }
            .frame(maxHeight: 300)
            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("继续") {
                    session.onResolve(ConflictResolutions(perName: perName, applyToAll: applyToAll))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(session.entries.contains { perName[$0.sourceName] == nil && applyToAll == nil })
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    private func row(for entry: ConflictEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.sourceName).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 16) {
                comparison("源", size: entry.sourceSize, date: entry.sourceModified)
                Image(systemName: "arrow.right").foregroundColor(theme.secondaryText)
                comparison("目标", size: entry.destSize, date: entry.destModified)
            }
            HStack(spacing: 8) {
                ForEach([ConflictStrategy.keepBoth, .overwrite, .skip], id: \.self) { strategy in
                    if perName[entry.sourceName] == strategy {
                        Button(strategyLabel(strategy)) { perName[entry.sourceName] = strategy }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Button(strategyLabel(strategy)) { perName[entry.sourceName] = strategy }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Spacer()
                Button("应用到全部") { applyToAll = perName[entry.sourceName] ?? .keepBoth }
                    .buttonStyle(.borderless)
                    .foregroundColor(theme.secondaryText)
            }
        }
        .padding(8)
        .background(theme.paneBackground)
        .cornerRadius(6)
    }

    private func comparison(_ label: String, size: Int64, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(theme.secondaryText)
            Text("\(Theme.sizeString(size)) · \(Self.dateFormatter.string(from: date))")
                .font(.system(size: 11))
        }
    }

    private func strategyLabel(_ strategy: ConflictStrategy) -> String {
        switch strategy {
        case .keepBoth: return "保留两者"
        case .overwrite: return "覆盖"
        case .skip: return "跳过"
        }
    }
}
