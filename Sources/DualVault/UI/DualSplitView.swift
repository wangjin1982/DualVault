import SwiftUI

/// U1.2 双栏布局：左右面板 + 一条细分隔线。
/// 中央按钮栏已移除（操作集中到顶部工具栏）——双栏之间无隔断，启动即 50/50 均衡。
struct DualSplitView<Left: View, Right: View>: View {
    @Environment(\.theme) private var theme
    let left: Left
    let right: Right
    @Binding var dividerPosition: CGFloat

    @State private var dragStartWidth: CGFloat?
    @State private var didBalance = false
    private let minPaneWidth: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            let maxLeft = max(minPaneWidth, geo.size.width - minPaneWidth)
            HStack(spacing: 0) {
                left
                    .frame(width: min(max(dividerPosition, minPaneWidth), maxLeft))
                    .clipped()
                Rectangle()
                    .fill(theme.pathBarStroke)
                    .frame(width: 1)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartWidth == nil { dragStartWidth = dividerPosition }
                                dividerPosition = min(max(minPaneWidth, (dragStartWidth ?? dividerPosition) + value.translation.width), maxLeft)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
                right
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            .onChange(of: geo.size.width) { newWidth in
                // U1.2：首次有效宽度时 50/50 均衡（onAppear 时尺寸未定型会导致偏差）
                guard !didBalance, newWidth > 100 else { return }
                didBalance = true
                dividerPosition = newWidth / 2
            }
            .onAppear {
                // onAppear 兜底：若 onChange 未触发（尺寸已稳定）也均衡一次
                guard !didBalance, geo.size.width > 100 else { return }
                didBalance = true
                dividerPosition = geo.size.width / 2
            }
        }
    }

    init(dividerPosition: Binding<CGFloat>,
         @ViewBuilder left: () -> Left,
         @ViewBuilder right: () -> Right) {
        self._dividerPosition = dividerPosition
        self.left = left()
        self.right = right()
    }
}
