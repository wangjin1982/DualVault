import SwiftUI

/// E1-6 目录热列表：⌘D 弹出。点击跳转、添加当前目录、删除条目。持久化于 UserDefaults。
struct HotlistView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var services = AppServices.shared
    let onVisit: (URL) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("目录热列表").font(.headline)
                Spacer()
                Button("添加当前目录") {
                    services.model?.addCurrentToFavorites()
                }
            }
            if services.favorites.isEmpty {
                Text("空。浏览到常用目录后点\"添加当前目录\"。")
                    .foregroundColor(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(services.favorites, id: \.self) { url in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(theme.directoryIconTint)
                                Button(url.path) { onVisit(url) }
                                    .buttonStyle(.plain)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    services.removeFavorite(url)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(theme.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            HStack {
                Spacer()
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
