import Foundation

/// 复制路径三连（B3）：POSIX 路径 / file URL / 仅文件名，多选换行分隔。
enum PathCopyService {

    static func posixPaths(_ urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    static func fileURLs(_ urls: [URL]) -> String {
        urls.map { $0.absoluteString }.joined(separator: "\n")
    }

    static func fileNames(_ urls: [URL]) -> String {
        urls.map(\.lastPathComponent).joined(separator: "\n")
    }
}
