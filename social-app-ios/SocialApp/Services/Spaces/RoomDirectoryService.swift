import Foundation

// MARK: - PublicRoomJoinRule
/// 房间加入规则，对应 Rust PublicRoomJoinRule

enum PublicRoomJoinRule: String, Sendable {
    case `public`
    case knock
    case invite
    case `private`

    var localizedDescription: String {
        switch self {
        case .public: return "公开"
        case .knock: return "敲门进入"
        case .invite: return "仅邀请"
        case .private: return "私有"
        }
    }
}

// MARK: - RoomDescription
/// 目录中的房间描述，对应 Rust RoomDescription

struct RoomDescription: Identifiable, Sendable {
    let id: String
    let roomId: String
    let name: String
    let topic: String?
    let avatarUrl: URL?
    let memberCount: Int
    let joinRule: PublicRoomJoinRule
    let isWorldReadable: Bool
    let aliases: [String]
    let homeserver: String

    var formattedMemberCount: String {
        if memberCount >= 10000 {
            return "\(memberCount / 10000)万"
        }
        return "\(memberCount)"
    }
}

// MARK: - RoomDirectorySearchFilter
/// 目录搜索过滤条件

struct RoomDirectorySearchFilter: Sendable {
    let searchTerm: String?
    let onlyPublic: Bool
    let homeserver: String?

    init(searchTerm: String? = nil, onlyPublic: Bool = true, homeserver: String? = nil) {
        self.searchTerm = searchTerm
        self.onlyPublic = onlyPublic
        self.homeserver = homeserver
    }
}

// MARK: - RoomDirectoryService
/// 房间目录搜索服务，对应 Rust room_directory_search.rs。
/// 负责搜索公开房间、分页加载、订阅更新。

@MainActor
final class RoomDirectoryService: ObservableObject {
    static let shared = RoomDirectoryService()

    @Published private(set) var results: [RoomDescription] = []
    @Published private(set) var loadedPages: Int = 0
    @Published private(set) var isAtLastPage: Bool = false
    @Published private(set) var isLoading: Bool = false

    private let pageSize = 20
    private var currentFilter: RoomDirectorySearchFilter?

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() {}

    // MARK: - 目录搜索

    /// 执行目录搜索
    /// - Parameters:
    ///   - filter: 搜索过滤条件
    ///   - server: 目标服务器地址（可选）
    /// - Returns: 房间描述列表
    func search(
        filter: RoomDirectorySearchFilter = RoomDirectorySearchFilter(),
        via server: String? = nil
    ) async throws -> [RoomDescription] {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        isLoading = true
        defer { isLoading = false }

        let dirSearch = try await client.roomDirectorySearch()
        let ffiResults = try await dirSearch.search(
            filter: filter.searchTerm ?? "",
            batch: UInt32(pageSize),
            via: server
        )

        currentFilter = filter
        loadedPages = 1
        isAtLastPage = ffiResults.isLastPage

        let rooms = ffiResults.results.map { r in
            RoomDescription(
                id: r.roomId,
                roomId: r.roomId,
                name: r.name ?? r.roomId,
                topic: r.topic,
                avatarUrl: r.avatarUrl.flatMap { URL(string: $0) },
                memberCount: Int(r.numJoinedMembers),
                joinRule: PublicRoomJoinRule(rawValue: r.joinRule ?? "public") ?? .public,
                isWorldReadable: r.worldReadable,
                aliases: r.aliases,
                homeserver: server ?? ""
            )
        }
        results = rooms
        return rooms
    }

    /// 加载下一页结果
    func nextPage() async throws -> [RoomDescription] {
        guard !isAtLastPage else { return [] }

        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        isLoading = true
        defer { isLoading = false }

        let dirSearch = try await client.roomDirectorySearch()
        let ffiResults = try await dirSearch.nextPage()

        loadedPages += 1
        isAtLastPage = ffiResults.isLastPage

        let rooms = ffiResults.results.map { r in
            RoomDescription(
                id: r.roomId,
                roomId: r.roomId,
                name: r.name ?? r.roomId,
                topic: r.topic,
                avatarUrl: r.avatarUrl.flatMap { URL(string: $0) },
                memberCount: Int(r.numJoinedMembers),
                joinRule: PublicRoomJoinRule(rawValue: r.joinRule ?? "public") ?? .public,
                isWorldReadable: r.worldReadable,
                aliases: r.aliases,
                homeserver: ""
            )
        }
        results.append(contentsOf: rooms)
        return rooms
    }

    /// 重置搜索状态
    func reset() {
        results = []
        loadedPages = 0
        isAtLastPage = false
        currentFilter = nil
    }
}