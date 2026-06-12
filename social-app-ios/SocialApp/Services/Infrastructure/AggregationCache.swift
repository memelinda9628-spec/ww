import Foundation

// MARK: - AggregationStats
/// 对应 Rust 的 AggregationStats：like/reply/forward 三计数

struct AggregationStats: Sendable {
    var likeCount: UInt64
    var replyCount: UInt64
    var forwardCount: UInt64

    static let zero = AggregationStats(likeCount: 0, replyCount: 0, forwardCount: 0)
}

// MARK: - AggregationCache
/// 对应 Rust 的 AggregationCache（8 方法）。
/// 用于批量更新和管理 moments 的聚合统计数据，减少频繁的矩阵事件查询。

final class AggregationCache: @unchecked Sendable {
    private var storage: [String: AggregationStats] = [:]
    private let lock = NSLock()

    /// 获取某个 moment 的聚合统计
    func get(momentId: String) -> AggregationStats? {
        lock.lock(); defer { lock.unlock() }
        return storage[momentId]
    }

    /// 设置某个 moment 的聚合统计（覆盖）
    func set(momentId: String, stats: AggregationStats) {
        lock.lock(); defer { lock.unlock() }
        storage[momentId] = stats
    }

    /// 自增某个计数
    func increment(momentId: String, field: AggregationField) {
        lock.lock(); defer { lock.unlock() }
        var stats = storage[momentId] ?? .zero
        switch field {
        case .like: stats.likeCount += 1
        case .reply: stats.replyCount += 1
        case .forward: stats.forwardCount += 1
        }
        storage[momentId] = stats
    }

    /// 自减某个计数
    func decrement(momentId: String, field: AggregationField) {
        lock.lock(); defer { lock.unlock() }
        var stats = storage[momentId] ?? .zero
        switch field {
        case .like: stats.likeCount = stats.likeCount > 0 ? stats.likeCount - 1 : 0
        case .reply: stats.replyCount = stats.replyCount > 0 ? stats.replyCount - 1 : 0
        case .forward: stats.forwardCount = stats.forwardCount > 0 ? stats.forwardCount - 1 : 0
        }
        storage[momentId] = stats
    }

    /// 批量更新
    func updateBatch(_ entries: [(String, AggregationStats)]) {
        lock.lock(); defer { lock.unlock() }
        for (id, stats) in entries {
            storage[id] = stats
        }
    }

    /// 清空指定 moment 的统计
    func clear(momentId: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: momentId)
    }

    /// 全量清空
    func clearAll() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }

    /// 应用统计到 Moment 列表（返回带有最新计数的 Moments）
    func apply(to moments: [Moment]) -> [Moment] {
        lock.lock(); defer { lock.unlock() }
        return moments.map { m in
            if let stats = storage[m.id] {
                return Moment(id: m.id, authorId: m.authorId, authorName: m.authorName,
                              authorAvatar: m.authorAvatar, text: m.text, images: m.images,
                              createdAt: m.createdAt,
                              likeCount: stats.likeCount,
                              commentCount: stats.replyCount,
                              forwardCount: stats.forwardCount,
                              eventId: m.eventId)
            }
            return m
        }
    }

    /// 统计信息
    var stats: (totalEntries: Int, totalLikes: UInt64, totalReplies: UInt64, totalForwards: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let totalLikes = storage.values.reduce(0) { $0 + $1.likeCount }
        let totalReplies = storage.values.reduce(0) { $0 + $1.replyCount }
        let totalForwards = storage.values.reduce(0) { $0 + $1.forwardCount }
        return (storage.count, totalLikes, totalReplies, totalForwards)
    }
}

// MARK: - AggregationField
enum AggregationField: Sendable {
    case like
    case reply
    case forward
}