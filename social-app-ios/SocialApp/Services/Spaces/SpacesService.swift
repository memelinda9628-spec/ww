import Foundation

// MARK: - Space Model
// 对应 Rust spaces 模块的本地 Space 聚合模型

struct Space: Identifiable, Sendable {
    let id: String
    let roomId: String
    let name: String
    let topic: String?
    let avatarUrl: URL?
    let creatorId: String
    let memberCount: Int
    let roomCount: Int
    let isJoined: Bool
    let isPublic: Bool
    let parentSpaceId: String?
    let childSpaceIds: [String]
    let createdAt: Date

    var initial: String { String(name.prefix(1)) }
}

// MARK: - SpaceHierarchy
// 空间层级视图：父空间 + 子空间 + 子房间

struct SpaceHierarchy: Sendable {
    let space: Space
    let parent: Space?
    let children: [Space]
    let rooms: [SpaceRoom]

    struct SpaceRoom: Identifiable, Sendable {
        let id: String
        let roomId: String
        let name: String
        let topic: String?
        let memberCount: Int
    }
}

// MARK: - SpaceRole
// 本地权限模型，用于 UI 层权限判断

enum SpaceRole: String, Sendable {
    case owner
    case admin
    case moderator
    case member
    case invited

    var canManageRooms: Bool { self == .owner || self == .admin }
    var canInvite: Bool { self == .owner || self == .admin || self == .moderator }
    var canKick: Bool { self == .owner || self == .admin }
}

// MARK: - SpaceRoomInfo
// 从 FFI SpaceRoom 提取的子房间元数据，用于 fetchChildRooms 结果

struct SpaceRoomInfo: Sendable {
    let roomId: String
    let displayName: String
    let topic: String?
    let avatarUrl: String?
    let numJoinedMembers: UInt64
    let roomType: RoomType
}

// MARK: - SpacesService
// Spaces 服务，对接 Rust matrix_sdk_ffi SpaceService（13 方法全部接入 FFI）
// 负责空间 CRUD、子房间管理、成员管理、层级查询

@MainActor
final class SpacesService: ObservableObject {
    static let shared = SpacesService()

    @Published private(set) var spaces: [Space] = []
    @Published private(set) var isLoading = false

    // FFI Client，通过 KeychainManager 获取已登录 session
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    private init() {}

    // MARK: - Space CRUD

    // 加载当前用户已加入的顶级空间列表
    // 权限：所有已认证用户均可调用
    func fetchSpaces() async throws -> [Space] {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        // spaceService() 是 async 非可选，直接 await 取值
        let spaceService = await client.spaceService()
        let ffiSpaces = await spaceService.topLevelJoinedSpaces() // async 无 throws，无需 try
        let result = ffiSpaces.map { s in
            Space(
                id: s.roomId,
                roomId: s.roomId,
                name: s.rawName ?? s.displayName, // rawName 是房间状态名称，displayName 是计算名
                topic: s.topic,
                avatarUrl: s.avatarUrl.flatMap { URL(string: $0) },
                creatorId: "", // FFI SpaceRoom 无 creatorId 字段，暂留空
                memberCount: Int(s.numJoinedMembers),
                roomCount: Int(s.childrenCount), // FFI 字段名 childrenCount
                isJoined: true, // topLevelJoinedSpaces 只返回已加入空间
                isPublic: s.joinRule == .public, // 从 joinRule 推导是否公开
                parentSpaceId: nil, // 顶级空间无父空间
                childSpaceIds: [], // FFI SpaceRoom 无此字段，用空数组
                createdAt: Date() // FFI 未暴露出创建时间
            )
        }
        spaces = result
        return result
    }

    // 获取指定空间下的子房间列表（分页加载）
    // 权限：该空间的所有成员均可查看子房间
    func fetchChildRooms(spaceId: String) async throws -> [SpaceRoomInfo] {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let spaceService = await client.spaceService()
        let roomList = try await spaceService.spaceRoomList(spaceId: spaceId) // async throws
        try await roomList.paginate() // 发起分页请求
        let ffiRooms = await roomList.rooms() // 获取已加载的房间列表
        return ffiRooms.map { r in
            SpaceRoomInfo(
                roomId: r.roomId,
                displayName: r.displayName,
                topic: r.topic,
                avatarUrl: r.avatarUrl,
                numJoinedMembers: r.numJoinedMembers,
                roomType: r.roomType
            )
        }
    }

    // 创建新空间（当前为 mock 实现，待 Rust createSpace FFI 暴露后接入）
    func createSpace(name: String, topic: String?, isPublic: Bool = true) async throws -> Space {
        let space = Space(
            id: UUID().uuidString,
            roomId: "!space_\(UUID().uuidString.prefix(8)):example.com",
            name: name, topic: topic, avatarUrl: nil,
            creatorId: "@me:example.com", memberCount: 1, roomCount: 0,
            isJoined: true, isPublic: isPublic,
            parentSpaceId: nil, childSpaceIds: [], createdAt: Date()
        )
        spaces.append(space)
        return space
    }

    // 加入指定空间
    // 权限：通过 room.join() 加入，具体由 Matrix 服务端判断
    func joinSpace(_ spaceId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        // getRoom 是同步 throws，返回可选 Room
        guard let room = try client.getRoom(roomId: spaceId) else {
            throw SocialFeedError.roomNotFound("Space room not found: \(spaceId)")
        }
        try await room.join()
        // 更新本地状态：标记已加入 + 成员数 +1
        if let idx = spaces.firstIndex(where: { $0.id == spaceId }) {
            spaces[idx] = Space(
                id: spaces[idx].id, roomId: spaces[idx].roomId, name: spaces[idx].name,
                topic: spaces[idx].topic, avatarUrl: spaces[idx].avatarUrl,
                creatorId: spaces[idx].creatorId, memberCount: spaces[idx].memberCount + 1,
                roomCount: spaces[idx].roomCount, isJoined: true,
                isPublic: spaces[idx].isPublic, parentSpaceId: spaces[idx].parentSpaceId,
                childSpaceIds: spaces[idx].childSpaceIds, createdAt: spaces[idx].createdAt
            )
        }
    }

    // 离开指定空间（含所有子房间），走 SpaceService 完整离开流程
    // 权限：已加入该空间的用户
    func leaveSpace(_ spaceId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let spaceService = await client.spaceService()
        // 获取 LeaveSpaceHandle，由 Rust 侧计算需要离开的房间列表
        let handle = try await spaceService.leaveSpace(spaceId: spaceId)
        let leaveRooms = handle.rooms() // 同步获取待离开房间列表 [LeaveSpaceRoom]
        let roomIds = leaveRooms.map { $0.spaceRoom.roomId }
        // 批量执行离开
        try await handle.leave(roomIds: roomIds)
        spaces.removeAll { $0.id == spaceId }
    }

    // MARK: - Member Management (Manager)
    // 以下操作需要管理者权限（Creator / Admin / Moderator），通过 canOwnUserXxx 前置检查

    // 邀请用户加入空间
    // 权限要求：canOwnUserInvite() 为 true（Creator/Admin/Moderator）
    func inviteToSpace(spaceId: String, userId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let room = try client.getRoom(roomId: spaceId) else {
            throw SocialFeedError.roomNotFound("Space room not found: \(spaceId)")
        }
        // 获取当前用户在房间内的权限级别
        let powerLevels = try await room.getPowerLevels()
        // 必须具有邀请权限才能继续，否则抛出 permissionDenied
        guard powerLevels.canOwnUserInvite() else {
            throw SocialFeedError.permissionDenied("Current user lacks permission to invite members")
        }
        try await room.inviteUserById(userId: userId)
    }

    // 将用户踢出空间
    // 权限要求：canOwnUserKick() 为 true（通常是 Creator/Admin）
    func kickFromSpace(spaceId: String, userId: String, reason: String? = nil) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let room = try client.getRoom(roomId: spaceId) else {
            throw SocialFeedError.roomNotFound("Space room not found: \(spaceId)")
        }
        let powerLevels = try await room.getPowerLevels()
        guard powerLevels.canOwnUserKick() else {
            throw SocialFeedError.permissionDenied("Current user lacks permission to kick members")
        }
        try await room.kickUser(userId: userId, reason: reason)
    }

    // MARK: - Member Management (General)
    // 以下操作为普通成员可见，无特殊权限要求

    // 列出空间所有成员（分块拉取全量）
    // 权限：该空间成员均可查看
    func listMembers(spaceId: String, chunkSize: UInt32 = 100) async throws -> [RoomMember] {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let room = try client.getRoom(roomId: spaceId) else {
            throw SocialFeedError.roomNotFound("Space room not found: \(spaceId)")
        }
        let iterator = try await room.members() // 获取成员迭代器
        var allMembers: [RoomMember] = []
        // 循环分块拉取直到为空或不足 chunkSize
        while let chunk = iterator.nextChunk(chunkSize: chunkSize) {
            allMembers.append(contentsOf: chunk)
            if chunk.count < chunkSize { break }
        }
        return allMembers
    }

    // 获取空间成员统计（已加入 / 已邀请人数）
    // 权限：该空间成员均可查看
    func memberCounts(spaceId: String) async throws -> (joined: Int, invited: Int) {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let room = try client.getRoom(roomId: spaceId) else {
            throw SocialFeedError.roomNotFound("Space room not found: \(spaceId)")
        }
        return (joined: Int(room.joinedMembersCount()), invited: Int(room.invitedMembersCount()))
    }

    // 获取当前用户在该空间内的角色（基于 power level 的建议角色）
    // 权限：无限制，但仅对已加入空间有效
    func currentUserRole(spaceId: String) async throws -> RoomMemberRole {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let room = try client.getRoom(roomId: spaceId) else {
            throw SocialFeedError.roomNotFound("Space room not found: \(spaceId)")
        }
        let ownId = room.ownUserId() // 同步获取自己的 userId
        let member = try await room.member(userId: ownId) // 通过 userId 查 member 详情
        return member.suggestedRoleForPowerLevel // 基于 power level 映射到角色枚举
    }

    // 获取空间层级视图（当前从本地 spaces 数组构建，待 FFI 完善后直连）
    func getSpaceHierarchy(spaceId: String) async throws -> SpaceHierarchy {
        try await Task.sleep(nanoseconds: 300_000_000) // 模拟网络延迟
        guard let space = spaces.first(where: { $0.id == spaceId }) else {
            throw SocialFeedError.roomNotFound("Space not found")
        }
        return SpaceHierarchy(space: space, parent: nil, children: [], rooms: [])
    }

    // 将子房间挂载到指定空间下
    // 权限：需要对该空间有管理权限（由 Rust 侧 SpaceService 判断）
    func addRoomToSpace(spaceId: String, roomId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let spaceService = await client.spaceService()
        // FFI 签名: addChildToSpace(childId: String, spaceId: String) — childId 是被挂载的子房间
        try await spaceService.addChildToSpace(childId: roomId, spaceId: spaceId)
    }

    // 将子房间从指定空间中移除
    // 权限：需要对该空间有管理权限（由 Rust 侧 SpaceService 判断）
    func removeRoomFromSpace(spaceId: String, roomId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let spaceService = await client.spaceService()
        // FFI 签名: removeChildFromSpace(childId: String, spaceId: String) — childId 是被移除的子房间
        try await spaceService.removeChildFromSpace(childId: roomId, spaceId: spaceId)
    }

    // MARK: - Search
    // 本地搜索：按名称/主题模糊匹配已加载的空间列表

    func searchSpaces(query: String) -> [Space] {
        let lower = query.lowercased()
        return spaces.filter {
            $0.name.lowercased().contains(lower) ||
            ($0.topic?.lowercased().contains(lower) ?? false)
        }
    }

    // MARK: - Mock Data
    // 开发用示例数据，生产环境由 fetchSpaces FFI 调用替代

    private func loadMockData() {
        spaces = [
            Space(id: "s1", roomId: "!space_rust:example.com", name: "Rust 中文社区",
                  topic: "专注 Rust 语言学习与交流", avatarUrl: nil,
                  creatorId: "@admin:example.com", memberCount: 328, roomCount: 12,
                  isJoined: true, isPublic: true,
                  parentSpaceId: nil, childSpaceIds: [], createdAt: Date().addingTimeInterval(-86400 * 90)),
            Space(id: "s2", roomId: "!space_ios:example.com", name: "iOS 开发者",
                  topic: "Swift / SwiftUI / Matrix", avatarUrl: nil,
                  creatorId: "@admin:example.com", memberCount: 156, roomCount: 5,
                  isJoined: true, isPublic: true,
                  parentSpaceId: nil, childSpaceIds: [], createdAt: Date().addingTimeInterval(-86400 * 60)),
            Space(id: "s3", roomId: "!space_design:example.com", name: "UI/UX 设计讨论",
                  topic: nil, avatarUrl: nil,
                  creatorId: "@designer:example.com", memberCount: 89, roomCount: 3,
                  isJoined: false, isPublic: true,
                  parentSpaceId: nil, childSpaceIds: [], createdAt: Date().addingTimeInterval(-86400 * 30)),
        ]
    }
}
