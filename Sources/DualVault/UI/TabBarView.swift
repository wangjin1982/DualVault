import AppKit
import SwiftUI

/// 中键关闭检测：覆盖在标签按钮上，otherMouseDown 触发关闭。
struct MiddleClickDetector: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        view.onOtherMouseDown = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class PassThroughView: NSView {
        var onOtherMouseDown: (() -> Void)?
        override func otherMouseDown(with event: NSEvent) {
            onOtherMouseDown?()
        }
        // 穿透左键点击到底层按钮
        override func hitTest(_ point: NSPoint) -> NSView? {
            let view = super.hitTest(point)
            return view === self ? nil : view
        }
    }
}

struct TabBarView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var group: PaneGroupModel
    let onClose: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(group.tabs) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 28)
        .background(theme.tabBarBackground)
    }

    private func tabButton(_ tab: PaneTab) -> some View {
        let selected = tab.id == group.selectedTabID
        return Button(action: { group.select(id: tab.id) }) {
            HStack(spacing: 4) {
                Text(tab.state.url.lastPathComponent.isEmpty ? "/" : tab.state.url.lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
                if group.tabs.count > 1 {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(theme.secondaryText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selected ? theme.selection.opacity(0.25) : Color.clear)
            .cornerRadius(4)
            .overlay(MiddleClickDetector {
                if group.selectedTabID == tab.id { onClose(tab.id) }
                else { onClose(tab.id) }
            })
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("关闭标签") { onClose(tab.id) }
        }
    }
}
