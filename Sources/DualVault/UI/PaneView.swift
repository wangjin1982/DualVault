import SwiftUI

struct PaneView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var pane: PaneState
    @ObservedObject var model: BrowserModel
    let side: PaneSide
    @Binding var focusedSide: PaneSide
    @Binding var sidebarVisible: Bool

    private var isFocused: Bool { focusedSide == side }

    var body: some View {
        VStack(spacing: 0) {
            PathBarView(pane: pane, sidebarVisible: $sidebarVisible)
            FileTableView(pane: pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBarView(pane: pane, model: model)
        }
        .background(theme.paneBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? theme.selection : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { focusedSide = side }
    }
}
