import SwiftUI

/// F1-A 文件夹比较与同步：比较模式 → 差异列表（按状态过滤）→ 同步计划干跑预览（逐项排除）→ 执行。
struct CompareView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: BrowserModel
    let onClose: () -> Void

    @State private var compareMode: CompareMode = .nameSize
    @State private var entries: [DiffEntry]?
    @State private var comparing = false
    @State private var compareProgress: (done: Int, total: Int)?
    @State private var compareWork: DispatchWorkItem?
    @State private var statusFilter: DiffStatus?
    @State private var syncMode: SyncMode = .copyNewToRight
    @State private var plan: [SyncAction]?
    @State private var excluded: Set<String> = []

    private var leftRoot: URL { model.leftGroup.selectedPane.url }
    private var rightRoot: URL { model.rightGroup.selectedPane.url }

    var body: some View {
        VStack(spacing: 12) {
            header
            if let plan = plan {
                planPreview(plan)
            } else if let entries = entries {
                diffList(entries)
            } else {
                Text("比较左栏「\(leftRoot.lastPathComponent)」与右栏「\(rightRoot.lastPathComponent)」")
                    .foregroundColor(theme.secondaryText)
            }
            HStack {
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                if plan != nil {
                    Button("返回差异") { self.plan = nil }
                    Button("执行同步（\(finalPlan.count) 个动作）") {
                        model.runSync(finalPlan)
                        onClose()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(finalPlan.isEmpty)
                } else if entries != nil {
                    Button("生成同步计划") { generatePlan() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 440)
    }

    private var finalPlan: [SyncAction] {
        (plan ?? []).filter { !excluded.contains($0.relativePath) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("文件夹比较").font(.headline)
            Picker("比较模式", selection: $compareMode) {
                ForEach(CompareMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(entries != nil || comparing)
            Button(comparing ? "比较中…" : "比较") { runCompare() }
                .disabled(comparing)
            if comparing, let progress = compareProgress {
                ProgressView(value: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0)
                    .frame(width: 100)
                Text("\(progress.done)/\(progress.total)")
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText)
                Button("取消") { cancelCompare() }
                    .font(.system(size: 10))
            }
            if entries != nil && plan == nil {
                Picker("同步", selection: $syncMode) {
                    ForEach(SyncMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func runCompare() {
        comparing = true
        compareProgress = nil
        entries = nil
        let mode = compareMode
        let l = leftRoot, r = rightRoot
        var cancelled = false
        let work = DispatchWorkItem {
            do {
                let result = try DiffEngine.compare(left: l, right: r, mode: mode,
                                                    isCancelled: { cancelled }) { done, total in
                    DispatchQueue.main.async { compareProgress = (done, total) }
                }
                DispatchQueue.main.async {
                    comparing = false
                    compareProgress = nil
                    entries = result
                }
            } catch {
                DispatchQueue.main.async {
                    comparing = false
                    compareProgress = nil
                    if (error as? OperationError) != .cancelled {
                        model.alertMessage = error.localizedDescription
                    }
                }
            }
        }
        compareWork = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func cancelCompare() {
        compareWork?.cancel()
        comparing = false
        compareProgress = nil
    }

    private func generatePlan() {
        guard let entries = entries else { return }
        plan = SyncPlan.make(entries: entries, mode: syncMode, leftRoot: leftRoot, rightRoot: rightRoot)
        excluded.removeAll()
    }

    private func diffList(_ entries: [DiffEntry]) -> some View {
        VStack(spacing: 6) {
            HStack {
                ForEach([DiffStatus.onlyInLeft, DiffStatus.onlyInRight, DiffStatus.different, DiffStatus.same], id: \.self) { s in
                    let count = entries.filter { $0.status == s }.count
                    if statusFilter == s {
                        Button("\(s.rawValue) \(count)") { statusFilter = nil }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Button("\(s.rawValue) \(count)") { statusFilter = s }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            let shown = entries.filter { statusFilter == nil || $0.status == statusFilter }
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(shown, id: \.relativePath) { entry in
                        HStack {
                            Circle().fill(color(for: entry.status)).frame(width: 8, height: 8)
                            Text(entry.relativePath)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text(statusText(entry))
                                .font(.system(size: 10))
                                .foregroundColor(theme.secondaryText)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(theme.paneBackground)
            .cornerRadius(6)
        }
    }

    /// 干跑预览：每个动作（方向+路径），可逐项排除。
    private func planPreview(_ plan: [SyncAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("同步计划预览（勾选 = 执行）").font(.caption).foregroundColor(theme.secondaryText)
            if plan.isEmpty {
                Text("无需同步").foregroundColor(theme.secondaryText)
            }
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(plan, id: \.relativePath) { action in
                        Toggle(isOn: Binding(
                            get: { !excluded.contains(action.relativePath) },
                            set: { included in
                                if included { excluded.remove(action.relativePath) }
                                else { excluded.insert(action.relativePath) }
                            })) {
                            HStack {
                                Text(icon(for: action.kind)).frame(width: 20)
                                Text(action.relativePath)
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text(action.kind.rawValue)
                                    .font(.system(size: 10))
                                    .foregroundColor(action.kind == .trashOnRight ? theme.destructive : theme.secondaryText)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 6)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func color(for status: DiffStatus) -> Color {
        switch status {
        case .onlyInLeft: return theme.directoryIconTint
        case .onlyInRight: return theme.selection
        case .different: return theme.destructive
        case .same: return theme.secondaryText
        }
    }

    private func statusText(_ entry: DiffEntry) -> String {
        if entry.status == .different && entry.leftSize != entry.rightSize {
            return "\(Theme.sizeString(entry.leftSize)) ↔ \(Theme.sizeString(entry.rightSize))"
        }
        return entry.status.rawValue
    }

    private func icon(for kind: SyncAction.Kind) -> String {
        switch kind {
        case .copyToRight: return "→"
        case .copyToLeft: return "←"
        case .trashOnRight: return "🗑"
        }
    }
}
