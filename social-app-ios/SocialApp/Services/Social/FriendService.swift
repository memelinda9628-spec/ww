import Foundation

// MARK: - FriendService
/// 好友管理服务，对应 Matrix Rust SDK 的 room member API。
/// 负责查询好友列表、好友详情、搜索好友及批量获取。

@MainActor
final class FriendService: ObservableObject {
    static let shared = FriendService()

    @Published private(set) var friends: [Friend] = []
    private var friendsById: [String: Friend] = [:]

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    private init() { loadMockData() }

    // MARK: - 好友列表

    func fetchFriends() async throws -> [Friend] {
        // 接入 Rust getDmRooms，映射 DM 房间为好友列表
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let dmRooms = try await client.getDmRooms()
        return dmRooms.map { room in
            let roomId = room.id()
            // 优先读房间缓存
            let displayName: String
            let avatarUrl: URL?
            if let cached = AppContainer.shared.profileCache.getRoom(roomId: roomId) {
                displayName = cached.displayName
                avatarUrl = cached.avatarUrl
            } else {
                let name = room.name() ?? ""
                let avatar = room.avatarUrl().flatMap { URL(string: $0) }
                displayName = name
                avatarUrl = avatar
                let roomProfile = ProfileCache.RoomProfile(roomId: roomId, displayName: name, avatarUrl: avatar)
                AppContainer.shared.profileCache.setRoom(roomId: roomId, profile: roomProfile)
            }
            return Friend(id: roomId, userId: room.member()?.userId ?? "",
                          displayName: displayName,
                          avatarUrl: avatarUrl,
                          statusMessage: nil, isOnline: false, lastSeen: nil)
        }
    }

    func fetchFriendDetail(userId: String) async throws -> Friend {
        // 1. 尝试从 ProfileCache 读取
        if let cached = AppContainer.shared.profileCache.get(userId: userId) {
            return Friend(
                id: cached.userId, userId: cached.userId,
                displayName: cached.displayName,
                avatarUrl: cached.avatarUrl,
                statusMessage: cached.bio,
                isOnline: false, lastSeen: nil
            )
        }
        // 2. 内存缓存
        if let friend = friendsById[userId] { return friend }
        // 3. FFI 获取（通过 searchUsers 按 userId 精确查找）
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let results = try await client.searchUsers(searchTerm: userId, limit: 1)
        if let profile = results.results.first {
            let friend = Friend(
                id: profile.userId, userId: profile.userId,
                displayName: profile.displayName,
                avatarUrl: profile.avatarUrl.flatMap { URL(string: $0) },
                statusMessage: nil, isOnline: false, lastSeen: nil
            )
            // 回写 ProfileCache
            let userProfile = UserProfile(
                id: profile.userId, userId: profile.userId,
                displayName: profile.displayName,
                avatarUrl: profile.avatarUrl.flatMap { URL(string: $0) },
                bio: nil, location: nil,
                feedRoomId: nil, followerCount: 0, followingCount: 0, momentsCount: 0
            )
            AppContainer.shared.profileCache.set(userId: profile.userId, profile: userProfile)
            return friend
        }
        throw SocialFeedError.profileNotFound(userId)
    }

    // MARK: - 搜索好友

    func searchFriends(query: String) -> [Friend] {
        guard !query.isEmpty else { return friends }
        let lower = query.lowercased()
        return friends.filter {
            $0.displayName.lowercased().contains(lower) ||
            $0.userId.lowercased().contains(lower)
        }
    }

    func searchFriendsByKeyword(_ keyword: String) async throws -> [Friend] {
        // 优先读搜索缓存
        if let cached = AppContainer.shared.profileCache.getSearch(keyword: keyword) {
            return cached.map { su in
                Friend(id: su.userId, userId: su.userId,
                       displayName: su.displayName,
                       avatarUrl: su.avatarUrl,
                       statusMessage: su.bio,
                       isOnline: false, lastSeen: nil)
            }
        }
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let results = try await client.searchUsers(searchTerm: keyword, limit: 20)
        var searchedUsers: [SearchedUser] = []
        for profile in results.results {
            let dmRoom = try? client.getDmRoom(userId: profile.userId)
            let isFriend: Bool
            let roomId: String?

            if let dmRoom = dmRoom, await dmRoom.isDirect() {
                let membersIter = try await dmRoom.members()
                var allMembers: [RoomMember] = []
                var chunk = membersIter.nextChunk(chunkSize: 100)
                while let c = chunk {
                    allMembers.append(contentsOf: c)
                    chunk = membersIter.nextChunk(chunkSize: 100)
                }
                let currentUserId = client.userId() ?? ""
                isFriend = allMembers.contains { $0.userId == profile.userId }
                        && allMembers.contains { $0.userId == currentUserId }
                roomId = dmRoom.id()
            } else {
                isFriend = false
                roomId = nil
            }

            searchedUsers.append(SearchedUser(
                id: profile.userId, userId: profile.userId,
                displayName: profile.displayName,
                avatarUrl: profile.avatarUrl.flatMap { URL(string: $0) },
                bio: nil,
                isAlreadyFriend: isFriend,
                roomId: roomId
            ))
        }
        // 回写搜索缓存
        AppContainer.shared.profileCache.setSearch(keyword: keyword, results: searchedUsers)
        // 构建 Friend 数组返回
        let friends = searchedUsers.map { su in
            Friend(id: su.userId, userId: su.userId,
                   displayName: su.displayName,
                   avatarUrl: su.avatarUrl,
                   statusMessage: su.bio,
                   isOnline: false, lastSeen: nil)
        }
        return friends
    }

    // MARK: - 获取好友

    func getFriend(userId: String) -> Friend? {
        friendsById[userId]
    }

    func getAllFriends() -> [Friend] {
        friends
    }

    var friendCount: Int { friends.count }

    // MARK: - 创建 DM

    /// 创建与指定用户的直接消息房间 — 通过 client.createDm() UniFFI 绑定
    /// - Parameter userId: 目标用户的 Matrix ID
    /// - Returns: 创建的 roomId
    func createDm(with userId: String) async throws -> String {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.createDm(userId: userId)
        return room.id()
    }

    // MARK: - Mock Data

    private func loadMockData() {
        friends = [
            Friend(id: "1", userId: "@alice:example.com", displayName: "Alice",
                   avatarUrl: nil, statusMessage: "在忙", isOnline: true, lastSeen: Date()),
            Friend(id: "2", userId: "@bob:example.com", displayName: "Bob",
                   avatarUrl: nil, statusMessage: "今天用 Matrix 搭建了一个去中心化聊天服务", isOnline: true, lastSeen: Date()),
            Friend(id: "3", userId: "@charlie:example.com", displayName: "Charlie",
                   avatarUrl: nil, statusMessage: "matrix-rust-sdk 的 sliding sync 真是太快了", isOnline: false,
                   lastSeen: Date().addingTimeInterval(-3600)),
            Friend(id: "4", userId: "@dave:example.com", displayName: "Dave",
                   avatarUrl: nil, statusMessage: "周末去爬山吗", isOnline: true, lastSeen: Date()),
            Friend(id: "5", userId: "@eve:example.com", displayName: "Eve",
                   avatarUrl: nil, statusMessage: "在写代码", isOnline: false,
                   lastSeen: Date().addingTimeInterval(-7200)),
        ]
        friendsById = Dictionary(uniqueKeysWithValues: friends.map { ($0.userId, $0) })
    }
}
