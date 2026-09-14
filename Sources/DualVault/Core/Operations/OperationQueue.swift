import Foundation

/// 串行后台操作队列：UI 提交操作，后台执行，回报进度，支持取消。
/// 所有复制/移动/删除的唯一执行通道。
final class OperationQueue: ObservableObject {
    @Published private(set) var current: FileOperation?
    @Published private(set) var isRunning = false
    @Published var progressFiles: (done: Int, total: Int) = (0, 0)
    @Published var progressBytes: (done: Int64, total: Int64) = (0, 0)

    private var cancelled = false
    private let queue = DispatchQueue(label: "com.dualvault.fileops", qos: .userInitiated)

    var isCancelled: Bool { cancelled }

    /// 入队执行。completion 在主线程回调结果。
    func enqueue(_ operation: FileOperation, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isRunning else {
            completion(.failure(OperationError.unexpected("已有操作进行中")))
            return
        }
        cancelled = false
        isRunning = true
        current = operation
        progressFiles = (0, 0)
        progressBytes = (0, 0)

        queue.async {
            let result: Result<Void, Error> = Result(catching: {
                try operation.execute(isCancelled: { [weak self] in self?.cancelled ?? true }) { [weak self] d, t, bd, bt in
                    DispatchQueue.main.async {
                        self?.progressFiles = (d, t)
                        self?.progressBytes = (bd, bt)
                    }
                }
            })
            DispatchQueue.main.async {
                self.isRunning = false
                self.current = nil
                completion(result)
            }
        }
    }

    func cancel() {
        cancelled = true
    }
}
