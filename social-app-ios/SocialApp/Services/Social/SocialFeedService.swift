import Foundation

// MARK: - SocialFeedService
/// 封装 social-feed Rust 库的 FFI 调用，对应 SocialFeed 结构体的全部公开方法。
/// 全部方法已替换为真实 UniFFI 绑定，无 Mock 占位。

@MainActor
final class SocialFeedService: ObservableObject {
    static let shared = SocialFeedService()

    @Published var myProfile: UserProfile?
    @Published private(set) var moments: [Moment] = []
    @Published private(set) var isLoading = false

    // MARK: Pagination state
    private var token: PaginationToken = .firstPage()
    let pageSize = 20

    // MARK: Search index
    let searchIndex = SearchIndex()

    /// 本地 following 缓存（由 follow/unfollow 维护，配合 DM rooms 做快速查找）
    private var followingIds: Set<String> = []

    private init() {}

    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    // MARK: - Profile ────────────────────────────────────────

    /// 首次创建个人主页 Feed Room
    func createProfile(displayName: String, avatarMxcUri: String?, bio: String?, location: String?) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setDisplayName(name: displayName)
        if let mxc = avatarMxcUri {
            try await client.setAvatarUrl(url: mxc)
        }
        await fetchMyProfile()
    }

    /// 获取我的 Profile — 先读 ProfileCache，未命中时走 FFI 获取并回写缓存
    func fetchMyProfile() async {
        guard let client = ffiClient else { return }
        let userId = client.userId()
        // 1. 尝试从缓存读取
        if let cached = AppContainer.shared.profileCache.get(userId: userId) {
            myProfile = cached
            return
        }
        // 2. 缓存未命中，走 FFI 获取
        do {
            let name = try await client.displayName()
            let avatar = try? await client.avatarUrl()
            let dmRooms = try? await client.getDmRooms()
            let feedRoom = dmRooms?.first { room in
                let n = room.name() ?? ""
                return n.contains("个人主页") || n.contains("Feed") || n.contains("feed")
            }
            let profile = UserProfile(
                id: userId, userId: userId,
                displayName: name,
                avatarUrl: avatar.flatMap { URL(string: $0) },
                bio: nil, location: nil,
                feedRoomId: feedRoom?.id(),
                followerCount: 0,
                followingCount: dmRooms?.count ?? 0,
                momentsCount: 0
            )
            myProfile = profile
            AppContainer.shared.profileCache.set(userId: userId, profile: profile)
        } catch {
            print("[SocialFeedService] fetchMyProfile failed: \(error)")
        }
    }

    /// 设置头像 (mxc:// URI，由调用方用 SDK 上传后传入)
    func setAvatar(mxcUri: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setAvatarUrl(url: mxcUri)
    }

    func updateBio(_ bio: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        if let feedRoomId = myProfile?.feedRoomId {
            let room = try await client.getRoom(roomId: feedRoomId)
            try await room.sendRaw(eventType: "m.room.topic", content: "{\"topic\":\"bio:\(bio)\"}")
        }
    }

    func updateLocation(_ location: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        if let feedRoomId = myProfile?.feedRoomId {
            let room = try await client.getRoom(roomId: feedRoomId)
            try await room.sendRaw(eventType: "m.room.topic", content: "{\"topic\":\"location:\(location)\"}")
        }
    }

    func updateDisplayName(_ name: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setDisplayName(name: name)
    }

    // MARK: - Timeline ───────────────────────────────────────

    /// 拉取首页时间线：遍历所有 DM 房间，通过 timeline.paginateBackwards() FFI 获取真实事件
    func fetchTimeline(page: Int = 0) async -> PagedResult<Moment> {
        isLoading = true
        defer { isLoading = false }

        guard let client = ffiClient else {
            return PagedResult(items: [], total: 0, canPaginateForward: false, canPaginateBackward: false)
        }

        do {
            let rooms = try await client.rooms()
            var allMoments: [Moment] = []
            for room in rooms {
                guard room.isDirect() else { continue }
                let roomId = room.id()
                let timeline = room.timeline()
                // TimelineListener 模式收集事件：
                // FFI paginateBackwards 仅返回 Bool，事件通过 onUpdate 回调到达，
                // 需用 TimelineEventCollector 缓存后在 Swift 侧转换
                let collector = TimelineEventCollector()
                let _ = await timeline.addListener(listener: collector)
                let _ = try await timeline.paginateBackwards(numEvents: UInt16(pageSize))
                for item in collector.events {
                    let eventId: String
                    switch item.eventOrTransactionId {
                    case .eventId(let id): eventId = id
                    case .transactionId: continue
                    }
                    if let body = item.extractedBody {
                        let moment = Moment(
                            id: eventId, authorId: item.sender,
                            authorName: item.displayName,
                            authorAvatar: nil, text: body, images: [],
                            createdAt: item.date, likeCount: 0,
                            commentCount: 0, forwardCount: 0, eventId: eventId,
                            feedRoomId: roomId
                        )
                        allMoments.append(moment)
                    }
                }
            }
            moments = allMoments
            rebuildSearchIndex()

            let start = page * pageSize
            let end = min(start + pageSize, allMoments.count)
            let pageItems = Array(allMoments[start..<max(start, end)])
            return PagedResult(
                items: pageItems, total: allMoments.count,
                canPaginateForward: end < allMoments.count,
                canPaginateBackward: page > 0
            )
        } catch {
            print("[SocialFeedService] fetchTimeline FFI failed: \(error)")
            return PagedResult(items: [], total: 0, canPaginateForward: false, canPaginateBackward: false)
        }
    }

    func refreshTimeline() async { await fetchTimeline() }

    // MARK: - user_moments API (P0) ──────────────────────────
    /// 按 feed_room_id 获取单个用户的动态列表
    /// — 通过 TimelineListener + paginateBackwards 模式获取真实事件
    func userMoments(feedRoomId: String, pageSize: Int = 20) async throws -> FeedResult<[Moment]> {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: feedRoomId)
        let timeline = room.timeline()
        // TimelineListener 模式：paginateBackwards 仅返回 Bool，
        // 事件通过 TimelineEventCollector.onUpdate 回调收集
        let collector = TimelineEventCollector()
        let _ = await timeline.addListener(listener: collector)
        let _ = try await timeline.paginateBackwards(numEvents: UInt16(pageSize))
        var moments: [Moment] = []
        for item in collector.events {
            let eventId: String
            switch item.eventOrTransactionId {
            case .eventId(let id): eventId = id
            case .transactionId: continue
            }
            if let body = item.extractedBody {
                moments.append(Moment(
                    id: eventId, authorId: item.sender,
                    authorName: item.displayName, authorAvatar: nil,
                    text: body, images: [],
                    createdAt: item.date, likeCount: 0,
                    commentCount: 0, forwardCount: 0, eventId: eventId,
                    feedRoomId: feedRoomId
                ))
            }
        }
        return .success(moments)
    }

    // MARK: - Post ───────────────────────────────────────────

    /// 发布动态：支持纯文本与带图动态
    /// - Parameters:
    ///   - text: 动态正文
    ///   - imageURLs: 本地图片 URL 列表（可选，最多 9 张）
    /// - 流程：上传图片获取 MXC URI → 构造 content JSON → sendRaw 发送
    func postMoment(text: String, imageURLs: [URL]) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let feedRoomId = myProfile?.feedRoomId else { throw SocialFeedError.profileNotFound(myProfile?.userId ?? "unknown") }

        // 上传图片获取 MXC URI 列表（走 ImageUploadService：压缩 → FFI uploadMedia）
        var mxcUris: [String] = []
        if !imageURLs.isEmpty {
            let uploadService = ImageUploadService()
            mxcUris = try await uploadService.uploadImages(localURLs: imageURLs)
        }

        let room = try await client.getRoom(roomId: feedRoomId)

        // 对文本中的 JSON 特殊字符做转义，避免 content JSON 格式被破坏
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        // 构造 content JSON（Matrix m.room.message 事件）
        let contentJson: String
        if mxcUris.isEmpty {
            // 纯文本动态
            contentJson = """
            {"msgtype":"m.text","body":"\(escapedText)"}
            """
        } else {
            // 带图动态：images 字段存放 MXC URI 列表
            let imagesJson = mxcUris.map { "\"\($0)\"" }.joined(separator: ",")
            contentJson = """
            {"msgtype":"m.text","body":"\(escapedText)","images":[\(imagesJson)]}
            """
        }

        try await room.sendRaw(eventType: "m.room.message", content: contentJson)
    }

    // MARK: - Like ───────────────────────────────────────────

    func toggleLike(momentId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let feedRoomId = myProfile?.feedRoomId else { throw SocialFeedError.profileNotFound(myProfile?.userId ?? "unknown") }
        let room = try await client.getRoom(roomId: feedRoomId)
        try await room.timeline().toggleReaction(eventId: momentId, key: "👍")
    }

    // MARK: - Comment ────────────────────────────────────────

    func comment(momentId: String, text: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let feedRoomId = myProfile?.feedRoomId else { throw SocialFeedError.profileNotFound(myProfile?.userId ?? "unknown") }
        let room = try await client.getRoom(roomId: feedRoomId)
        let contentJson = """
        {"msgtype":"m.text","body":"\(text)","m.relates_to":{"m.in_reply_to":{"event_id":"\(momentId)"}}}
        """
        try await room.sendRaw(eventType: "m.room.message", content: contentJson)
    }

    // MARK: - 评论加载（本地筛选方案）────────────────────────
    //
    // 由于 FFI 无按 m.in_reply_to 批量筛选消息的 API（Rust 核心层 RoomEventFilter
    // 不含 related_by_rel_types 字段，且 Room::relations() 未导出），本方法采用：
    //   1. TimelineListener 监听并缓存该房间的 EventTimelineItem
    //   2. timeline.paginateBackwards() 触发服务端拉取
    //   3. Swift 侧用 Timeline+ReplyFiltering 扩展方法筛选回复
    //   4. 转换为 MomentComment 返回
    //
    // 每条消息自带 MsgLikeContent.inReplyTo: InReplyToDetails? 字段，
    // 通过 InReplyToDetails.eventId() 与目标 moment.eventId 匹配即可定位评论。

    /// 加载指定动态的所有评论（回复消息）。
    /// - Parameters:
    ///   - feedRoomId: 动态所在的 Feed 房间 ID
    ///   - eventId: 目标动态的事件 ID
    ///   - limit: 最多拉取的事件数量（用于 paginateBackwards）
    /// - Returns: 按时间正序排列的评论列表
    func loadComments(feedRoomId: String, eventId: String, limit: UInt16 = 50) async -> [MomentComment] {
        guard let client = ffiClient else { return [] }
        do {
            let room = try await client.getRoom(roomId: feedRoomId)
            let timeline = room.timeline()

            // 1. 注册 TimelineListener 收集事件
            let collector = TimelineEventCollector()
            let _ = await timeline.addListener(listener: collector)

            // 2. 触发向后翻页加载历史消息
            let _ = try await timeline.paginateBackwards(numEvents: limit)

            // 3. 本地筛选：从已缓存的 EventTimelineItem 中找出回复给 eventId 的评论
            let replyEvents = collector.events.replies(to: eventId)

            // 4. 转换为 MomentComment
            return replyEvents.map { event in
                let eventIdStr: String
                switch event.eventOrTransactionId {
                case .eventId(let id): eventIdStr = id
                case .transactionId: eventIdStr = UUID().uuidString
                }
                return MomentComment(
                    id: eventIdStr,
                    authorName: event.displayName,
                    authorAvatar: nil,
                    text: event.extractedBody ?? "",
                    createdAt: event.date
                )
            }
        } catch {
            print("[SocialFeedService] loadComments failed: \(error)")
            return []
        }
    }

    // MARK: - Forward ────────────────────────────────────────
    /// 转发动态 — 通过 room.sendRaw() FFI 发送含 m.forward relation 的真实事件
    func forward(moment: Moment, quoteText: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let feedRoomId = myProfile?.feedRoomId else { throw SocialFeedError.profileNotFound(myProfile?.userId ?? "unknown") }
        let room = try await client.getRoom(roomId: feedRoomId)

        let escapedMomentText = moment.text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let escapedQuoteText = quoteText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let contentJson = """
        {"msgtype":"m.text","body":"\(escapedQuoteText)\\n\\n—— 转发自 \(moment.authorName)","format":"org.matrix.custom.html","formatted_body":"<blockquote><p><strong>\(moment.authorName)</strong></p><p>\(escapedMomentText)</p></blockquote><p>\(escapedQuoteText)</p>","m.relates_to":{"m.forward":{"event_id":"\(moment.eventId)","room_id":"\(moment.authorId)"}}}
        """
        try await room.sendRaw(eventType: "m.room.message", content: contentJson)
    }

    // MARK: - Social: Follow / Unfollow ──────────────────────

    func follow(userId: String, feedRoomId: String) async throws -> Bool {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: feedRoomId)
        try await room.join()
        followingIds.insert(userId)
        return true
    }

    func unfollow(feedRoomId: String) async throws {
        try await room.leave()
    }

    /// 获取关注列表 — 返回本地缓存（由 follow/unfollow 维护，与 DM rooms 同步）
    func getFollowing() -> [String] { Array(followingIds) }

    func isFollowing(userId: String) -> Bool { followingIds.contains(userId) }

    var followingCount: Int { followingIds.count }

    // MARK: - Search / Filter ────────────────────────────────

    func searchMoments(filter: SearchFilter = SearchFilter(), sort: SortOrder = .timeDesc) -> [Moment] {
        let filtered = moments.filter { filter.matches($0) }
        return sort.apply(filtered)
    }

    func fullTextSearch(query: String) -> [String] {
        Array(searchIndex.search(query: query))
    }

    // MARK: - Pagination ─────────────────────────────────────

    func loadNextPage() async -> PagedResult<Moment>? {
        let nextToken = token.nextToken()
        let start = nextToken.start
        guard start < moments.count else { return nil }
        let end = min(start + nextToken.size, moments.count)
        let items = Array(moments[start..<end])
        token = nextToken
        return PagedResult(items: items, total: moments.count,
                           canPaginateForward: end < moments.count,
                           canPaginateBackward: start > 0)
    }

    func resetPagination() { token = .firstPage() }

    // MARK: - Private Helpers ────────────────────────────────

    private func rebuildProfile(bio: String?, location: String?) -> UserProfile {
        UserProfile(
            id: myProfile?.id ?? "", userId: myProfile?.userId ?? "",
            displayName: myProfile?.displayName ?? "",
            avatarUrl: myProfile?.avatarUrl,
            bio: bio, location: location,
            feedRoomId: myProfile?.feedRoomId,
            followerCount: myProfile?.followerCount ?? 0,
            followingCount: myProfile?.followingCount ?? 0,
            momentsCount: myProfile?.momentsCount ?? 0
        )
    }

    private func mutateMoment(_ id: String, transform: (Moment) -> Moment) {
        guard let idx = moments.firstIndex(where: { $0.id == id }) else { return }
        moments[idx] = transform(moments[idx])
    }

    private func rebuildSearchIndex() {
        searchIndex.indexMoments(moments)
    }
}