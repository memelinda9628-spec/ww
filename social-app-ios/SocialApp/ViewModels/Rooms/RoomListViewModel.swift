import Foundation
import SwiftUI

// MARK: - RoomListViewModel
/// 房间列表管理 ViewModel，对应 RoomListService。
/// 管理房间列表状态、过滤、排序、搜索、滑动操作。

@MainActor
final class RoomListViewModel: ObservableObject {
    @Published var rooms: [RoomListItem] = []
    @Published var activeFilter: RoomFilterType = .all
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
    @Published var state: RoomListState = .initializing
    @Published var selectedRoom: RoomListItem?
    @Published var showFilterSheet: Bool = false
    @Published var bulkEditMode: Bool = false
    @Published var selectedRoomIds: Set<String> = []

    private let service = RoomListService.shared
    private var ffiClient: Client? { KeychainManager.shared.ffiClient }

    // MARK: - 数据加载

    func loadRooms() async {
        state = .running
        applyFilterAndSort()
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    func refresh() async {
        await loadRooms()
    }

    // MARK: - 过滤

    func setFilter(_ filter: RoomFilterType) {
        activeFilter = filter
        service.setFilter(filter)
        applyFilterAndSort()
    }

    func search(query: String) {
        searchQuery = query
        isSearching = !query.isEmpty
        service.search(query: query)
        applyFilterAndSort()
    }

    func clearSearch() {
        searchQuery = ""
        isSearching = false
        service.search(query: "")
        applyFilterAndSort()
    }

    // MARK: - 排序

    func sortByRecent() {
        rooms = service.sortByRecent(rooms)
    }

    func sortByUnread() {
        rooms = service.sortByUnread(rooms)
    }

    // MARK: - 房间操作

    /// 标记房间为已读
    func markAsRead(_ roomId: String) {
        Task {
            guard let client = ffiClient else { return }
            guard let room = try? await client.getRoom(roomId: roomId) else { return }
            guard let timeline = try? await room.timeline() else { return }
            guard let eventId = await timeline.latestEventId() else { return }
            try? await room.sendReadReceipt(eventId: eventId, receiptType: .read)
        }
    }

    /// 离开房间
    func leaveRoom(_ roomId: String) async {
        if let client = ffiClient, let room = try? await client.getRoom(roomId: roomId) {
            try? await room.leave()
        }
        rooms.removeAll { $0.roomId == roomId }
    }
    /// 收藏/取消收藏
    func toggleFavourite(_ roomId: String) {
        guard let room = rooms.first(where: { $0.roomId == roomId }) else { return }
        let newValue = !room.isFavourite
        Task {
            guard let client = ffiClient else { return }
            guard let ffiRoom = try? await client.getRoom(roomId: roomId) else { return }
            try? await ffiRoom.setIsFavourite(isFavourite: newValue, tagOrder: nil)
        }
    }

    /// 静音/取消静音
    func toggleMute(_ roomId: String) {
        guard let room = rooms.first(where: { $0.roomId == roomId }) else { return }
        let newMode: RoomNotificationMode = room.notificationMode == .mute ? .allMessages : .mute
        Task {
            guard let client = ffiClient else { return }
            try? await client.setRoomNotificationMode(roomId: roomId, mode: newMode)
        }
    }

    /// 设为低优先级
    func setLowPriority(_ roomId: String) {
        guard let room = rooms.first(where: { $0.roomId == roomId }) else { return }
        let newValue = !room.isLowPriority
        Task {
            guard let client = ffiClient else { return }
            guard let ffiRoom = try? await client.getRoom(roomId: roomId) else { return }
            try? await ffiRoom.setIsLowPriority(isLowPriority: newValue, tagOrder: nil)
        }
    }
    // MARK: - 批量操作

    func toggleBulkEdit() {
        bulkEditMode.toggle()
        if !bulkEditMode { selectedRoomIds.removeAll() }
    }

    func toggleRoomSelection(_ roomId: String) {
        if selectedRoomIds.contains(roomId) {
            selectedRoomIds.remove(roomId)
        } else {
            selectedRoomIds.insert(roomId)
        }
    }

    func bulkMarkAsRead() {
        for id in selectedRoomIds { markAsRead(id) }
        selectedRoomIds.removeAll()
    }

    func bulkLeave() async {
        for id in selectedRoomIds { await leaveRoom(id) }
        selectedRoomIds.removeAll()
    }

    // MARK: - 过滤标签

    var filterTabs: [RoomFilterType] {
        [.all, .unread, .favourites, .people, .groups]
    }

    var filterTabTitle: (RoomFilterType) -> String {
        { type in
            switch type {
            case .all: return "全部"
            case .unread: return "未读"
            case .favourites: return "收藏"
            case .people: return "私聊"
            case .groups: return "群聊"
            default: return ""
            }
        }
    }

    var filterTabIcon: (RoomFilterType) -> String {
        { type in
            switch type {
            case .all: return "message"
            case .unread: return "envelope.badge"
            case .favourites: return "star"
            case .people: return "person"
            case .groups: return "person.3"
            default: return "circle"
            }
        }
    }

    var unreadCount: Int {
        rooms.filter { $0.unreadCount > 0 || $0.isMarkedUnread }.count
    }

    // MARK: - Private

    private func applyFilterAndSort() {
        var result = service.filteredRooms()
        if !searchQuery.isEmpty {
            let lower = searchQuery.lowercased()
            result = result.filter { $0.displayName.lowercased().contains(lower) }
        }
        result = service.sortByRecent(result)
        rooms = result
    }
}