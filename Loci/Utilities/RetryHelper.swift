import Foundation

/// Centralized retry utility with exponential backoff for Supabase operations.
enum RetryHelper {
    /// Default configuration for Supabase network operations.
    static let defaultMaxAttempts = 3
    static let defaultBaseDelay: TimeInterval = 1.0 // seconds

    /// Executes an async operation with exponential backoff retry.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default 3).
    ///   - baseDelay: Base delay in seconds, doubled each retry (default 1s → 2s → 4s).
    ///   - shouldRetry: Optional predicate to determine if a specific error is retryable.
    ///                  Defaults to retrying all errors.
    ///   - operation: The async throwing operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The last error if all attempts fail.
    static func withRetry<T>(
        maxAttempts: Int = defaultMaxAttempts,
        baseDelay: TimeInterval = defaultBaseDelay,
        shouldRetry: ((Error) -> Bool)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            // Respect task cancellation between attempts
            try Task.checkCancellation()

            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error

                // Check if this error is retryable
                if let shouldRetry, !shouldRetry(error) {
                    throw error
                }

                // Don't sleep after the last attempt
                if attempt < maxAttempts - 1 {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw lastError ?? CancellationError()
    }

    /// Returns true if the error is likely a transient network error worth retrying.
    static func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // URLSession network errors
        if nsError.domain == NSURLErrorDomain {
            let retryableCodes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorSecureConnectionFailed,
            ]
            return retryableCodes.contains(nsError.code)
        }

        return false
    }
}
