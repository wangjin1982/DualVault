import SwiftUI

/// 三栏布局：左 | 中央按钮栏 | 右，中缝可拖动、位置可持久化。
/// 热修（HOTFIX-1）：原 NSSplitView 桥接在运行时把左右面板布局成零高度
/// （实测帧 = 1100×0），纯 SwiftUI 重写以消除整类 AppKit 桥接布局问题。
/// 对外接口与原 NSViewRepresentable 版本完全一致。
struct DualSplitView<Left: View, Center: View, Right: View>: View {
    let left: Left
    let center: Center
    let right: Right
    @Binding var dividerPosition: CGFloat
    let centerWidth: CGFloat

    @State private var dragStartWidth: CGFloat?

    private let minPaneWidth: CGFloat = 320

    var body: some View {
        GeometryReader { geo in
            let maxLeft = max(minPaneWidth, geo.size.width - centerWidth - minPaneWidth)
            HStack(spacing: 0) {
                left
                    .frame(width: dividerPosition)
                    .clipped()
                Divider()
                    .frame(width: 1)
                center
                    .frame(width: centerWidth)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 6)
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
        }
    }

    init(dividerPosition: Binding<CGFloat>, centerWidth: CGFloat,
         @ViewBuilder left: () -> Left,
         @ViewBuilder center: () -> Center,
         @ViewBuilder right: () -> Right) {
        self._dividerPosition = dividerPosition
        self.centerWidth = centerWidth
        self.left = left()
        self.center = center()
        self.right = right()
    }
}
