import Foundation

// MARK: - RateLimiter
/// 令牌桶限流器，对应 Rust 的 RateLimiter。
/// 默认 10 req/s，容量 100，3 次重试（指数退避 ±10% 抖动）。

final class RateLimiter: @unchecked Sendable {
    private let capacity: Int
    private let refillRate: Double  // tokens per second
    private let maxRetries: Int

    private var tokens: Double
    private var lastRefill: Date
    private let lock = NSLock()

    init(capacity: Int = 100, refillRate: Double = 10.0, maxRetries: Int = 3) {
        self.capacity = capacity
        self.refillRate = refillRate
        self.maxRetries = maxRetries
        self.tokens = Double(capacity)
        self.lastRefill = Date()
    }

    /// 检查是否允许放行（消耗 1 token）
    func allow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        refillTokens()
        guard tokens >= 1.0 else { return false }
        tokens -= 1.0
        return true
    }

    /// 等待直到允许（带指数退避重试）
    func waitUntilAllowed() async throws {
        for attempt in 0..<maxRetries {
            if allow() { return }
            let baseDelay = 1.0 / refillRate * Double(attempt + 1)
            let jitter = Double.random(in: -0.1...0.1) * baseDelay
            let delay = max(baseDelay + jitter, 0.01)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        throw SocialFeedError.rateLimited(retryAfterMs: UInt64((1.0 / refillRate * Double(maxRetries)) * 1000))
    }

    /// 处理 rate_limit 事件（服务端返回 retry_after_ms）
    func handleRateLimit(retryAfterMs: UInt64) {
        lock.lock(); defer { lock.unlock() }
        // 临时扣减 tokens 以模拟服务端限流
        let penalty = Double(retryAfterMs) / 1000.0 * refillRate
        tokens = max(0, tokens - penalty)
    }

    /// 重置令牌桶
    func reset() {
        lock.lock(); defer { lock.unlock() }
        tokens = Double(capacity)
        lastRefill = Date()
    }

    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        tokens = min(Double(capacity), tokens + elapsed * refillRate)
        lastRefill = now
    }
}

// MARK: - OperationType
/// 对应 Rust 的 OperationType（6 种操作类型区分）

enum OperationType: Sendable {
    case postMoment
    case like
    case comment
    case forward
    case follow
    case unfollow

    /// 每种操作消耗的 token 权重
    var tokenWeight: Double {
        switch self {
        case .postMoment: return 2.0
        case .like: return 1.0
        case .comment: return 1.0
        case .forward: return 1.5
        case .follow: return 1.0
        case .unfollow: return 0.5
        }
    }
}