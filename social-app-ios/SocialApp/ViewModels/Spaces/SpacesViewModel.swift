import Foundation
import SwiftUI

// RoomType → 字符串映射，用于 UI 展示
private func roomTypeToString(_ type: RoomType) -> String {
    switch type {
    case .room: return "m.room"
    case .space: return "m.space"
    case .custom(let value): return value
    }
}

// MARK: - SpaceInfo
// UI 层空间信息数据模型，从 Service 的 Space 映射而来

struct SpaceInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let topic: String?
    let avatarUrl: URL?
    let memberCount: Int
    let childRoomCount: Int
    let isJoined: Bool
    let isSuggested: Bool
}

// MARK: - ChildRoomInfo
// UI 层子房间信息，从 SpaceRoomInfo 映射而来

struct ChildRoomInfo: Identifiable, Sendable {
    let id: String
    let roomId: String
    let name: String
    let topic: String?
    let avatarUrl: URL?
    let memberCount: Int
    let isJoined: Bool
    let roomType: String  // "m.room" 或 "m.space"
}

// MARK: - SpacesViewModel
// 空间列表 + 空间详情 ViewModel，完全通过 SpacesService 对接 FFI。
// 管理：顶级空间列表、选中空间的子房间列表、成员管理、addChild/removeChild 操作。

@MainActor
final class SpacesViewModel: ObservableObject {
    // MARK: - 发布状态

    @Published var topLevelSpaces: [SpaceInfo] = []
    @Published var selectedSpace: SpaceInfo?
    @Published var childRooms: [ChildRoomInfo] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchQuery: String = ""

    // MARK: - 依赖
    // 所有 FFI 调用均通过 SpacesService 路由，ViewModel 不直接调 FFI

    private var spacesService: SpacesService { SpacesService.shared }

    // MARK: - 空间列表

    // 加载顶级已加入空间列表
    // 对应 FFI: topLevelJoinedSpaces()
    func loadSpaces() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let spaces = try await spacesService.fetchSpaces()
            topLevelSpaces = spaces.map { space in
                SpaceInfo(
                    id: space.id,
                    name: space.name,
                    topic: space.topic,
                    avatarUrl: space.avatarUrl,
                    memberCount: space.memberCount,
                    childRoomCount: space.roomCount,
                    isJoined: space.isJoined,
                    isSuggested: false
                )
            }
        } catch {
            errorMessage = "加载空间失败: \(error.localizedDescription)"
            topLevelSpaces = mockSpaces() // 加载失败时降级为 mock 数据
        }
    }

    // MARK: - 空间详情

    // 加载指定空间的子房间列表（分页）
    // 对应 FFI: spaceRoomList → paginate → rooms
    func loadSpaceRooms(spaceId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rooms = try await spacesService.fetchChildRooms(spaceId: spaceId)
            childRooms = rooms.map { room in
                ChildRoomInfo(
                    id: room.roomId,
                    roomId: room.roomId,
                    name: room.displayName,
                    topic: room.topic,
                    avatarUrl: room.avatarUrl.flatMap { URL(string: $0) },
                    memberCount: Int(room.numJoinedMembers),
                    isJoined: true,
                    roomType: roomTypeToString(room.roomType)
                )
            }
        } catch {
            errorMessage = "加载空间房间失败: \(error.localizedDescription)"
            childRooms = mockChildRooms()
        }
    }

    // MARK: - 空间操作
    // 以下操作均委托给 SpacesService，ViewModel 仅更新本地 UI 状态

    // 将子房间挂载到空间
    func addChildToSpace(spaceId: String, childRoomId: String) async throws {
        try await spacesService.addRoomToSpace(spaceId: spaceId, roomId: childRoomId)
        // 更新本地子房间列表的加入状态
        if let idx = childRooms.firstIndex(where: { $0.roomId == childRoomId }) {
            let existing = childRooms[idx]
            childRooms[idx] = ChildRoomInfo(
                id: existing.id, roomId: existing.roomId,
                name: existing.name, topic: existing.topic,
                avatarUrl: existing.avatarUrl, memberCount: existing.memberCount,
                isJoined: true, roomType: existing.roomType
            )
        }
    }

    // 将子房间从空间移除
    func removeChildFromSpace(spaceId: String, childRoomId: String) async throws {
        try await spacesService.removeRoomFromSpace(spaceId: spaceId, roomId: childRoomId)
        childRooms.removeAll { $0.roomId == childRoomId }
    }

    // 离开空间（含所有子房间）
    func leaveSpace(spaceId: String) async throws {
        try await spacesService.leaveSpace(spaceId)
        topLevelSpaces.removeAll { $0.id == spaceId }
        if selectedSpace?.id == spaceId {
            selectedSpace = nil
            childRooms = []
        }
    }

    // 创建新空间
    // TODO: SpacesService.createSpace 仍为 mock 实现，暂直调 ffiClient。
    //       待 SpacesService.createSpace 接入 FFI 后改为走 Service。
    func createSpace(name: String, topic: String? = nil) async throws {
        guard let client = KeychainManager.shared.ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }
        let params = CreateRoomParameters(isEncrypted: false, visibility: .private, preset: .privateChat, isSpace: true)
        _ = try await client.createRoom(request: params)
        let newSpace = SpaceInfo(
            id: UUID().uuidString, name: name, topic: topic,
            avatarUrl: nil, memberCount: 1, childRoomCount: 0,
            isJoined: true, isSuggested: false
        )
        topLevelSpaces.append(newSpace)
    }

    // MARK: - 成员管理 (Manager)
    // 需要管理者权限的操作，由 SpacesService 做前置权限检查

    // 邀请用户加入空间
    // 权限：canOwnUserInvite()（Creator/Admin/Moderator）
    func inviteToSpace(spaceId: String, userId: String) async throws {
        try await spacesService.inviteToSpace(spaceId: spaceId, userId: userId)
    }

    // 将用户踢出空间
    // 权限：canOwnUserKick()（Creator/Admin）
    func kickFromSpace(spaceId: String, userId: String, reason: String? = nil) async throws {
        try await spacesService.kickFromSpace(spaceId: spaceId, userId: userId, reason: reason)
    }

    // MARK: - 成员管理 (General)

    // 列出空间所有成员（分块全量拉取）
    func listMembers(spaceId: String) async throws -> [RoomMember] {
        try await spacesService.listMembers(spaceId: spaceId)
    }

    // MARK: - 搜索

    // 按名称/主题模糊过滤已加载的空间列表
    var filteredSpaces: [SpaceInfo] {
        guard !searchQuery.isEmpty else { return topLevelSpaces }
        let lower = searchQuery.lowercased()
        return topLevelSpaces.filter {
            $0.name.lowercased().contains(lower) ||
            ($0.topic?.lowercased().contains(lower) ?? false)
        }
    }

    // MARK: - Mock Data
    // 开发用降级数据，网络异常或 FFI 未就绪时使用

    private func mockSpaces() -> [SpaceInfo] { [
        SpaceInfo(id: "!space_dev:example.com", name: "开发团队", topic: "技术讨论与代码评审", avatarUrl: nil, memberCount: 42, childRoomCount: 8, isJoined: true, isSuggested: false),
        SpaceInfo(id: "!space_design:example.com", name: "设计团队", topic: "UI/UX 设计协作", avatarUrl: nil, memberCount: 18, childRoomCount: 5, isJoined: true, isSuggested: false),
        SpaceInfo(id: "!space_rust:example.com", name: "Rust 爱好者", topic: "Matrix Rust SDK 交流", avatarUrl: nil, memberCount: 156, childRoomCount: 12, isJoined: true, isSuggested: false),
    ] }

    private func mockChildRooms() -> [ChildRoomInfo] { [
        ChildRoomInfo(id: "!room_general:example.com", roomId: "!room_general:example.com", name: "综合讨论", topic: "日常闲聊与技术交流", avatarUrl: nil, memberCount: 35, isJoined: true, roomType: "m.room"),
        ChildRoomInfo(id: "!room_announcements:example.com", roomId: "!room_announcements:example.com", name: "公告频道", topic: "重要通知与发布记录", avatarUrl: nil, memberCount: 42, isJoined: true, roomType: "m.room"),
        ChildRoomInfo(id: "!room_code_review:example.com", roomId: "!room_code_review:example.com", name: "代码评审", topic: "PR 评审与代码规范讨论", avatarUrl: nil, memberCount: 28, isJoined: true, roomType: "m.room"),
    ] }
}
