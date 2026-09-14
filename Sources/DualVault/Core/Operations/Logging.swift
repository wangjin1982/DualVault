import Foundation
import os

/// 全应用共享日志（文件操作/外部进程等）。
let fileOpsLogger = Logger(subsystem: "com.dualvault", category: "fileops")

/// 记录清理失败的辅助：清理继续尽力而为，但不许无声（评审 M2 意见 2）。
func logCleanupFailure(_ error: Error, context: String) {
    fileOpsLogger.error("清理失败（\(context, privacy: .public)）：\(error.localizedDescription, privacy: .public)")
}
