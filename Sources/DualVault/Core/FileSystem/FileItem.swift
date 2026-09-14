import Foundation

/// 单个文件系统条目。Core 层模型，不依赖 AppKit/SwiftUI。
struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let size: Int64
    let modified: Date
    let isDirectory: Bool
    let isHidden: Bool

    var id: URL { url }

    /// 列表"种类"列展示用：文件夹显示"文件夹"，其余显示扩展名大写。
    var kind: String {
        isDirectory ? "文件夹" : (url.pathExtension.isEmpty ? "—" : url.pathExtension.uppercased())
    }
}

extension FileItem {
    /// 从资源值构造（DirectoryLoader 快速路径）。
    init(url: URL, values: URLResourceValues?) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = values?.isDirectory ?? false
        self.size = Int64(values?.fileSize ?? 0)
        self.modified = values?.contentModificationDate ?? .distantPast
        let flag = values?.isHidden ?? ((url.lastPathComponent as NSString).hasPrefix("."))
        self.isHidden = flag
    }

    /// 从磁盘属性构造；属性缺失时给安全默认值，不抛错（单文件不可读不应拖垮整个目录列表）。
    init(url: URL, attributes: [FileAttributeKey: Any]) {
        self.url = url
        self.name = url.lastPathComponent
        let type = attributes[.type] as? FileAttributeType
        self.isDirectory = type == .typeDirectory
        self.size = attributes[.size] as? Int64 ?? 0
        self.modified = attributes[.modificationDate] as? Date ?? .distantPast
        self.isHidden = (url.lastPathComponent as NSString).hasPrefix(".")
    }
}
