import SwiftUI

/// E1-3 批量重命名：规则表单 + 实时预览（冲突标红）+ 应用。
struct RenameDialogView: View {
    @Environment(\.theme) private var theme
    let items: [FileItem]
    let pane: PaneState
    let onApply: ([RenamePlanEntry]) -> Void
    let onCancel: () -> Void

    @State private var rules = RenameRules()

    /// 现有名（冲突检测 = 预览名撞目录现有名）。排除本次要改名的文件本身。
    private var existingNames: Set<String> {
        let renaming = Set(items.map(\.name))
        return Set(pane.items.map(\.name)).subtracting(renaming)
    }

    private var plan: [RenamePlanEntry] {
        (try? BatchRename.plan(names: items.map(\.name), rules: rules, existingNames: existingNames)) ?? []
    }

    private var regexError: String? { rules.regexError() }

    var body: some View {
        VStack(spacing: 12) {
            Text("批量重命名（\(items.count) 项）").font(.headline)

            rulesForm
            if let error = regexError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(theme.destructive)
            }
            preview

            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                if BatchRename.hasConflicts(plan) {
                    Text("存在冲突项，冲突项将被跳过")
                        .font(.system(size: 11))
                        .foregroundColor(theme.destructive)
                }
                Button("应用") { onApply(plan) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!BatchRename.hasChanges(plan))
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var rulesForm: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("查找：")
                if rules.useRegex {
                    TextField("正则（$1 = 捕获组）", text: $rules.find).frame(width: 180)
                } else {
                    TextField("被替换的文本", text: $rules.find).frame(width: 180)
                }
                Text("替换为：")
                if rules.useRegex {
                    TextField("替换模板", text: $rules.replace).frame(width: 180)
                } else {
                    TextField("替换结果", text: $rules.replace).frame(width: 180)
                }
            }
            GridRow {
                Text("前缀："); TextField("", text: $rules.prefix).frame(width: 180)
                Text("后缀："); TextField("", text: $rules.suffix).frame(width: 180)
            }
            GridRow {
                Text("模板："); TextField("如 照片 ({N})，{name} 原名", text: $rules.template).frame(width: 180)
                Text("起始序号：")
                Stepper("\(rules.startNumber)", value: $rules.startNumber, in: 0...9999).frame(width: 120)
            }
            GridRow {
                Text("大小写：")
                Picker("", selection: $rules.caseTransform) {
                    ForEach(CaseTransform.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .frame(width: 180)
                    .pickerStyle(.menu)
                Toggle("正则", isOn: $rules.useRegex)
                Toggle("扩展名独立", isOn: $rules.preserveExtension)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("预览").font(.caption).foregroundColor(theme.secondaryText)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(plan, id: \.original) { entry in
                        HStack {
                            Text(entry.original)
                                .strikethrough(entry.original != entry.renamed)
                                .foregroundColor(theme.secondaryText)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(theme.secondaryText)
                            Text(entry.renamed)
                                .foregroundColor(entry.conflict ? theme.destructive : theme.foreground)
                            if entry.conflict {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(theme.destructive)
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(8)
        .background(theme.paneBackground)
        .cornerRadius(6)
    }
}
