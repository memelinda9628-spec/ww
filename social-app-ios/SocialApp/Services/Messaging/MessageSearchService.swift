import Foundation

// MARK: - MessageSearchFilter
/// 搜索范围过滤。对应 Rust MessageSearchFilter 枚举

enum MessageSearchFilter: Sendable {
    case all
    case rooms
    case directMessages
    case nonDirectMessages
}

// MARK: - SearchPagination
/// 分页参数

struct SearchPagination: Sendable {
    let limit: Int
    let beforeEvent: String?
    let afterEvent: String?

    init(limit: Int = 20, beforeEvent: String? = nil, afterEvent: String? = nil) {
        self.limit = limit
        self.beforeEvent = beforeEvent
        self.afterEvent = afterEvent
    }
}

// MARK: - MessageSearchResult
/// 全局搜索结果，对应 Rust GlobalSearchResult

struct MessageSearchResult: Sendable {
    let query: String
    let rooms: [RoomSearchResult]
    let totalCount: Int
    let hasMore: Bool
}

// MARK: - RoomSearchResult
/// 单房间搜索结果，对应 Rust RoomSearchResult

struct RoomSearchResult: Sendable {
    let roomId: String
    let roomName: String
    let score: Double
    let matchedEvents: [MatchedMessage]
    let totalMatches: Int
}

// MARK: - MatchedMessage
/// 匹配的消息条目

struct MatchedMessage: Identifiable, Sendable {
    let id: String
    let eventId: String
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let roomId: String
}

// MARK: - MessageSearchService
/// 消息搜索服务，封装全局跨房间搜索与单房间搜索。
/// 对应 Rust FFI: Client.search_messages / Room.search_messages

@MainActor
final class MessageSearchService: ObservableObject {
    static let shared = MessageSearchService()

    @Published private(set) var lastGlobalResult: MessageSearchResult?
    @Published private(set) var isSearching = false

    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    private init() {}

    // MARK: - 全局搜索

    /// 全局跨房间搜索消息
    func searchMessages(
        query: String,
        filter: MessageSearchFilter = .all,
        pagination: SearchPagination = SearchPagination()
    ) async throws -> MessageSearchResult {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        isSearching = true
        defer { isSearching = false }

        let result = try await client.searchMessages(query: query)

        let rooms = result.rooms.map { roomResult in
            let roomId = roomResult.roomId
            // 优先读房间缓存获取房间名，未命中则回写缓存
            let roomName: String
            if let cached = AppContainer.shared.profileCache.getRoom(roomId: roomId) {
                roomName = cached.displayName
            } else {
                roomName = roomResult.roomName
                // 回写房间缓存（avatarUrl 暂无来源，传 nil）
                let roomProfile = ProfileCache.RoomProfile(
                    roomId: roomId, displayName: roomName, avatarUrl: nil)
                AppContainer.shared.profileCache.setRoom(roomId: roomId, profile: roomProfile)
            }
            let events = roomResult.events.map { event in
                MatchedMessage(
                    id: event.eventId,
                    eventId: event.eventId,
                    senderId: event.sender,
                    senderName: event.sender,
                    content: event.body ?? "",
                    timestamp: Date(timeIntervalSince1970: TimeInterval(event.timestamp) / 1000),
                    roomId: roomId
                )
            }
            return RoomSearchResult(
                roomId: roomId,
                roomName: roomName,
                score: roomResult.score,
                matchedEvents: events,
                totalMatches: roomResult.totalMatches
            )
        }
        let searchResult = MessageSearchResult(
            query: query,
            rooms: rooms,
            totalCount: rooms.reduce(0) { $0 + $1.totalMatches },
            hasMore: !result.isLastPage
        )
        lastGlobalResult = searchResult
        return searchResult
    }

    /// 单房间内搜索消息
    func searchRoomMessages(
        roomId: String,
        query: String,
        pagination: SearchPagination = SearchPagination()
    ) async throws -> RoomSearchResult {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let room = try? await client.getRoom(roomId: roomId) else {
            throw SocialFeedError.roomNotFound
        }

        let result = try await room.searchMessages(query: query)
        let events = result.events.map { event in
            MatchedMessage(
                id: event.eventId,
                eventId: event.eventId,
                senderId: event.sender,
                senderName: event.sender,
                content: event.body ?? "",
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.timestamp) / 1000),
                roomId: roomId
            )
        }
        // 优先读房间缓存获取房间名，未命中则回写缓存
        let resolvedRoomName: String
        if let cached = AppContainer.shared.profileCache.getRoom(roomId: roomId) {
            resolvedRoomName = cached.displayName
        } else {
            resolvedRoomName = try? await room.displayName() ?? roomId
            // 回写房间缓存
            let roomProfile = ProfileCache.RoomProfile(
                roomId: roomId, displayName: resolvedRoomName, avatarUrl: nil)
            AppContainer.shared.profileCache.setRoom(roomId: roomId, profile: roomProfile)
        }
        return RoomSearchResult(
            roomId: roomId,
            roomName: resolvedRoomName,
            score: 1.0,
            matchedEvents: events,
            totalMatches: events.count
        )
    }
}