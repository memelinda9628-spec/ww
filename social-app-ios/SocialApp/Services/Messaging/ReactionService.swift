import Foundation

// MARK: - ReactionItem
/// 回应/表情数据，包装 Rust Reaction 为 UI 友好的类型

struct ReactionItem: Identifiable, Sendable {
    let id: String
    /// 表情符号 key，如 "👍"
    let key: String
    /// 回应计数
    let count: Int
    /// 当前用户是否已使用该 reaction
    let isToggledByMe: Bool
    /// 最近发送者列表
    let recentSenders: [ReactionSenderItem]
    /// 发送时间
    let timestamp: Date
}

// MARK: - ReactionSenderItem
/// Reaction 发送者数据，包装 Rust ReactionSenderData 为 UI 友好类型

struct ReactionSenderItem: Identifiable, Sendable {
    let id: String
    let senderId: String
    let senderName: String
    let timestamp: Date
}

// MARK: - ReactionEvent
/// 事件上的回应聚合

struct ReactionEvent: Sendable {
    let eventId: String
    let roomId: String
    let reactions: [ReactionItem]
    let totalReactions: Int

    /// 按 count 降序排列
    var sortedReactions: [ReactionItem] {
        reactions.sorted { $0.count > $1.count }
    }

    /// 获取用户当前 active 的 reaction key
    var myActiveReactionKey: String? {
        reactions.first(where: { $0.isToggledByMe })?.key
    }
}

// MARK: - ReactionService
/// 回应/表情服务，对应 Rust Timeline.toggle_reaction。
/// 负责添加/移除 reaction、查询事件的 reaction 聚合。

@MainActor
final class ReactionService: ObservableObject {
    static let shared = ReactionService()

    @Published private(set) var eventsReactions: [String: ReactionEvent] = [:]

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() {}

    // MARK: - 核心操作

    /// 切换事件上的 reaction — 通过 timeline.toggleReaction() FFI
    func toggleReaction(
        eventId: String,
        key: String,
        roomId: String
    ) async throws -> ReactionEvent {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        let timeline = room.timeline()
        try await timeline.toggleReaction(itemId: .eventId(eventId: eventId), key: key)

        // 从 FFI 获取更新后的聚合数据，映射 Rust Reaction → ReactionItem
        let myId = client.userId()
        let aggregated = try? await timeline.fetchReactions(for: eventId)
        let reactions: [ReactionItem] = aggregated?.map { r in
            ReactionItem(
                id: r.key,
                key: r.key,
                count: r.senders.count,
                isToggledByMe: r.senders.contains(where: { $0.senderId == myId }),
                recentSenders: r.senders.map { s in
                    ReactionSenderItem(
                        id: s.senderId,
                        senderId: s.senderId,
                        senderName: s.senderId,
                        timestamp: Date(timeIntervalSince1970: TimeInterval(s.timestamp) / 1000)
                    )
                },
                timestamp: r.senders.first.map {
                    Date(timeIntervalSince1970: TimeInterval($0.timestamp) / 1000)
                } ?? Date()
            )
        } ?? []

        let event = ReactionEvent(
            eventId: eventId,
            roomId: roomId,
            reactions: reactions,
            totalReactions: reactions.reduce(0) { $0 + $1.count }
        )
        eventsReactions[eventId] = event
        return event
    }

    /// 获取事件的 reaction 聚合
    func getReactions(for eventId: String) -> ReactionEvent? {
        eventsReactions[eventId]
    }

    /// 获取事件上指定 key 的 reaction 详情
    func getReaction(eventId: String, key: String) -> ReactionItem? {
        eventsReactions[eventId]?.reactions.first(where: { $0.key == key })
    }

    // MARK: - 批量操作

    /// 批量获取多个事件的 reactions
    func getReactionsBatch(eventIds: [String]) -> [String: ReactionEvent] {
        var result: [String: ReactionEvent] = [:]
        for id in eventIds {
            if let event = eventsReactions[id] {
                result[id] = event
            }
        }
        return result
    }