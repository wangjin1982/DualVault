import AppKit

/// 文件图标/缩略图缓存：NSWorkspace.icon 与图片 64px 缩略图统一缓存层。
enum IconStore {
    private static let cache = NSCache<NSString, NSImage>()
    /// F3-4：图片扩展名（缩略图生效范围）。
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp"]

    static func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// F3-4：图片缩略图（64px，降级 = 普通图标）。
    static func thumbnail(for path: String) -> NSImage {
        let key = (path + "#thumb") as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let ext = (path as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(ext),
              let image = NSImage(contentsOfFile: path) else {
            return icon(for: path)
        }
        let thumb = NSImage(size: NSSize(width: 32, height: 32))
        thumb.lockFocus()
        let aspect = min(32 / image.size.width, 32 / image.size.height)
        let size = NSSize(width: image.size.width * aspect, height: image.size.height * aspect)
        image.draw(in: NSRect(x: (32 - size.width) / 2, y: (32 - size.height) / 2, width: size.width, height: size.height))
        thumb.unlockFocus()
        cache.setObject(thumb, forKey: key)
        return thumb
    }
}
