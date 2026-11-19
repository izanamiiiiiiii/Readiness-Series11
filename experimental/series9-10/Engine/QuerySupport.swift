import Foundation

enum ReadinessFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}


final class QueryCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var plainContinuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.plainContinuation = continuation
    }

    @discardableResult
    func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        let throwing = continuation
        let plain = plainContinuation
        continuation = nil
        plainContinuation = nil
        lock.unlock()
        guard throwing != nil || plain != nil else { return false }
        throwing?.resume(with: result)
        if case .success(let value) = result { plain?.resume(returning: value) }
        return true
    }
}
