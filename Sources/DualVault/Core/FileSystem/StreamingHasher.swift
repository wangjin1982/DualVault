import Foundation
import CryptoKit

/// 流式分块 SHA256：FileHandle 逐块读入，大文件不整载入内存（F1 验收 #4）。
enum StreamingHasher {
    static let chunkSize = 1 << 20 // 1MB

    static func sha256(of url: URL) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw OperationError.unexpected("无法读取文件：\(url.lastPathComponent)")
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
