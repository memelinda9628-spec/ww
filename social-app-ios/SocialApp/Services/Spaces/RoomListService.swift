import Foundation

// MARK: - RoomList
/// 房间列表容器，对应 Rust RoomList

struct RoomList: Sendable {
    let entries: [RoomListItem]
    let totalCount: Int
    let isLoading: Bool
}

// MARK: - RoomListItem
/// 房间列表项，对应 Rust RoomListItem

struct RoomListItem: Identifiable, Sendable {
    let id: String
    let roomId: String
    let displayName: String
    let avatarUrl: URL?
    let lastMessage: String?
    let lastMessageTimestamp: Date?
    let unreadCount: Int
    let isDirect: Bool
    let isFavourite: Bool
    let isLowPriority: Bool
    let isMarkedUnread: Bool
    let notificationMode: RoomNotificationMode
    let hasMention: Bool
    let isInvited: Bool
    let isJoined: Bool
    let spaceIds: [String]
}

// RoomNotificationMode 统一使用 Generated/matrix_sdk_ffi.swift 中的 FFI 版本。
// 补充 Sendable 显式遵循以兼容 Swift 5.9（FFI 仅在 compiler >= 6 时添加）。
extension RoomNotificationMode: @unchecked Sendable {}

// MARK: - RoomListState
/// 房间列表服务状态

enum RoomListState: Sendable {
    case initializing
    case running
    case paused
    case error(String)
    case stopped
}

// MARK: - RoomFilterType
/// 房间过滤类型

enum RoomFilterType: Sendable {
    case all
    case favourites
    case unread
    case people    // DM
    case groups    // 群聊
    case lowPriority
    case invited
}

// MARK: - RoomCategory
/// 房间分类

enum RoomCategory: String, Sendable {
    case group = "group"
    case people = "people"
}

// MARK: - RoomListService
/// 房间列表管理服务，对应 Rust room_list.rs。
/// 负责房间列表状态的获取、过滤、排序、订阅。

@MainActor
final class RoomListService: ObservableObject {
    static let shared = RoomListService()

    @Published private(set) var rooms: [RoomListItem] = []
    @Published private(set) var state: RoomListState = .initializing
    @Published private(set) var activeFilter: RoomFilterType = .all
    @Published private(set) var searchQuery: String = ""

    private var allRooms: [RoomListItem] = []

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() {}

    // MARK: - 房间列表

    /// 刷新所有房间列表（从 FFI RoomListService 拉取）
    func refreshRooms() async throws -> [RoomListItem] {
        guard let client = ffiClient else { throw SocialFeedError.notInitialized }
        let listService = client.roomListService()
        let rooms = try await listService.allRooms()
        let items = rooms.map { r in
            RoomListItem(
                id: r.roomId,
                roomId: r.roomId,
                displayName: r.displayName ?? r.roomId,
                avatarUrl: r.avatarUrl.flatMap { URL(string: $0) },
                lastMessage: r.lastMessage?.body,
                lastMessageTimestamp: r.lastMessageTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
                unreadCount: Int(r.unreadCount),
                isDirect: r.isDirect,
                isFavourite: r.isFavourite,
                isLowPriority: r.isLowPriority,
                isMarkedUnread: r.isMarkedUnread,
                notificationMode: r.cachedUserDefinedNotificationMode ?? .allMessages,
                hasMention: r.hasMention,
                isInvited: r.isInvited,
                isJoined: r.isJoined,
                spaceIds: r.spaceIds
            )
        }
        allRooms = items
        applyCurrentFilter()
        return items
    }

    /// 获取所有房间列表
    func allRoomsList() -> [RoomListItem] {
        allRooms
    }

    /// 按房间 ID 获取房间
    /// - Parameter roomId: 房间 ID
    /// - Returns: 房间列表项（如有）
    func room(roomId: String) -> RoomListItem? {
        allRooms.first { $0.roomId == roomId }
    }

    /// 获取当前过滤后的房间列表
    func filteredRooms() -> [RoomListItem] {
        applyFilter(activeFilter, to: allRooms)
    }

    // MARK: - 过滤

    /// 设置活跃过滤条件
    /// - Parameter filter: 过滤类型
    func setFilter(_ filter: RoomFilterType) {
        activeFilter = filter
        applyCurrentFilter()
    }

    /// 搜索房间（模糊匹配名称）
    /// - Parameter query: 搜索字符串
    func search(query: String) {
        searchQuery = query
        applyCurrentFilter()
    }

    /// 获取 30+ Filter Functions 对应的 Swift 封装：
    /// filterAll / filterFavourites / filterUnread / filterPeople / filterGroups / filterInvited / etc.

    func filterAll() -> [RoomListItem] { allRooms }

    func filterFavourites() -> [RoomListItem] {
        allRooms.filter { $0.isFavourite }
    }

    func filterUnread() -> [RoomListItem] {
        allRooms.filter { $0.unreadCount > 0 || $0.isMarkedUnread }
    }

    func filterPeople() -> [RoomListItem] {
        allRooms.filter { $0.isDirect }
    }

    func filterGroups() -> [RoomListItem] {
        allRooms.filter { !$0.isDirect }
    }

    func filterLowPriority() -> [RoomListItem] {
        allRooms.filter { $0.isLowPriority }
    }

    func filterInvited() -> [RoomListItem] {
        allRooms.filter { $0.isInvited }
    }

    func filterJoined() -> [RoomListItem] {
        allRooms.filter { $0.isJoined }
    }

    func filterNonLeft() -> [RoomListItem] {
        allRooms.filter { $0.isJoined || $0.isInvited }
    }

    func filterBySpace(spaceId: String) -> [RoomListItem] {
        allRooms.filter { $0.spaceIds.contains(spaceId) }
    }

    func filterByNotificationMode(_ mode: RoomNotificationMode) -> [RoomListItem] {
        allRooms.filter { $0.notificationMode == mode }
    }

    func filterByCategory(_ category: RoomCategory) -> [RoomListItem] {
        switch category {
        case .group: return filterGroups()
        case .people: return filterPeople()
        }
    }

    func filterByIds(_ ids: [String]) -> [RoomListItem] {
        allRooms.filter { ids.contains($0.id) }
    }

    func filterHasMention() -> [RoomListItem] {
        allRooms.filter { $0.hasMention }
    }

    // MARK: - 排序

    /// 按最近消息时间降序
    func sortByRecent(_ rooms: [RoomListItem]) -> [RoomListItem] {
        rooms.sorted { ($0.lastMessageTimestamp ?? Date.distantPast) > ($1.lastMessageTimestamp ?? Date.distantPast) }
    }

    /// 按未读数降序
    func sortByUnread(_ rooms: [RoomListItem]) -> [RoomListItem] {
        rooms.sorted { $0.unreadCount > $1.unreadCount }
    }

    // MARK: - 状态

    /// 订阅列表加载状态变更
    func updateState(_ newState: RoomListState) {
        state = newState
    }

    /// 同步指示器延迟
    func syncIndicator(delay: TimeInterval = 3.0) async {
        guard let client = ffiClient else { return }
        let listService = client.roomListService()
        _ = listService.syncIndicator(delay: UInt32(delay))
    }

    // MARK: - Private

    private func applyCurrentFilter() {
        var result = applyFilter(activeFilter, to: allRooms)
        if !searchQuery.isEmpty {
            let lower = searchQuery.lowercased()
            result = result.filter {
                $0.displayName.lowercased().contains(lower)
            }
        }
        result = sortByRecent(result)
        rooms = result
    }

    private func applyFilter(_ filter: RoomFilterType, to items: [RoomListItem]) -> [RoomListItem] {
        switch filter {
        case .all: return items
        case .favourites: return items.filter { $0.isFavourite }
        case .unread: return items.filter { $0.unreadCount > 0 || $0.isMarkedUnread }
        case .people: return items.filter { $0.isDirect }
        case .groups: return items.filter { !$0.isDirect }
        case .lowPriority: return items.filter { $0.isLowPriority }
        case .invited: return items.filter { $0.isInvited }
        }
    }

    // MARK: - Mock

    private func loadMockData() {
        let now = Date()
        allRooms = [
            RoomListItem(
                id: UUID().uuidString, roomId: "!roomA:example.com",
                displayName: "技术讨论组", avatarUrl: nil,
                lastMessage: "Alice: 新版 SDK 已经发布了", lastMessageTimestamp: now.addingTimeInterval(-120),
                unreadCount: 3, isDirect: false, isFavourite: true,
                isLowPriority: false, isMarkedUnread: false,
                notificationMode: .allMessages, hasMention: true,
                isInvited: false, isJoined: true, spaceIds: []
            ),
            RoomListItem(
                id: UUID().uuidString, roomId: "!roomB:example.com",
                displayName: "Alice", avatarUrl: nil,
                lastMessage: "好的，下午见", lastMessageTimestamp: now.addingTimeInterval(-600),
                unreadCount: 1, isDirect: true, isFavourite: false,
                isLowPriority: false, isMarkedUnread: false,
                notificationMode: .allMessages, hasMention: false,
                isInvited: false, isJoined: true, spaceIds: []
            ),
            RoomListItem(
                id: UUID().uuidString, roomId: "!roomC:example.com",
                displayName: "产品需求池", avatarUrl: nil,
                lastMessage: "Bob: 需求文档已更新到第3版", lastMessageTimestamp: now.addingTimeInterval(-1800),
                unreadCount: 0, isDirect: false, isFavourite: false,
                isLowPriority: true, isMarkedUnread: false,
                notificationMode: .mute, hasMention: false,
                isInvited: false, isJoined: true, spaceIds: []
            ),
            RoomListItem(
                id: UUID().uuidString, roomId: "!roomD:example.com",
                displayName: "新项目邀请", avatarUrl: nil,
                lastMessage: nil, lastMessageTimestamp: nil,
                unreadCount: 0, isDirect: false, isFavourite: false,
                isLowPriority: false, isMarkedUnread: false,
                notificationMode: .allMessages, hasMention: false,
                isInvited: true, isJoined: false, spaceIds: []
            ),
            RoomListItem(
                id: UUID().uuidString, roomId: "!roomE:example.com",
                displayName: "团队周报", avatarUrl: nil,
                lastMessage: "Charlie: 本周已完成 80% 的开发任务", lastMessageTimestamp: now.addingTimeInterval(-3600),
                unreadCount: 12, isDirect: false, isFavourite: false,
                isLowPriority: false, isMarkedUnread: true,
                notificationMode: .mentionsAndKeywordsOnly, hasMention: false,
                isInvited: false, isJoined: true, spaceIds: []
            ),
            RoomListItem(
                id: UUID().uuidString, roomId: "!roomF:example.com",
                displayName: "Bob", avatarUrl: nil,
                lastMessage: "周末去爬山吗？", lastMessageTimestamp: now.addingTimeInterval(-7200),
                unreadCount: 0, isDirect: true, isFavourite: true,
                isLowPriority: false, isMarkedUnread: false,
                notificationMode: .allMessages, hasMention: false,
                isInvited: false, isJoined: true, spaceIds: []
            ),
        ]
        applyCurrentFilter()
    }
}