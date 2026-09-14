import Foundation
import CryptoKit

enum ChecksumAlgorithm: String, CaseIterable {
    case md5 = "MD5", sha256 = "SHA-256"

    /// 与 shasum 输出一致的小写 hex。
    func compute(of url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw OperationError.unexpected("无法读取文件：\(url.lastPathComponent)")
        }
        switch self {
        case .md5:
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha256:
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// hex 格式自检。
    static func isValidHex(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isHexDigit }
    }
}
