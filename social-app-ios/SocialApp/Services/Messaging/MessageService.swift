import Foundation

// MARK: - ChatMessage Model
/// 对应 Matrix RoomMessageEventContent + Relation

struct ChatMessage: Identifiable, Sendable {
    let id: String
    let roomId: String
    let senderId: String
    let senderName: String
    let senderAvatar: URL?
    let body: String
    let formattedBody: String?
    let messageType: MessageType
    let timestamp: Date
    let replyTo: String?           // 被回复消息 ID（m.in_reply_to）
    let editVersion: Int
    let reactions: [String: Int]   // emoji → count
    let isRead: Bool
    let isEdited: Bool
    let isMine: Bool

    init(id: String, roomId: String, senderId: String, senderName: String,
         senderAvatar: URL?, body: String, formattedBody: String? = nil,
         messageType: MessageType = .text, timestamp: Date = Date(),
         replyTo: String? = nil, editVersion: Int = 0,
         reactions: [String: Int] = [:], isRead: Bool = false,
         isEdited: Bool = false, isMine: Bool = false) {
        self.id = id
        self.roomId = roomId
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatar = senderAvatar
        self.body = body
        self.formattedBody = formattedBody
        self.messageType = messageType
        self.timestamp = timestamp
        self.replyTo = replyTo
        self.editVersion = editVersion
        self.reactions = reactions
        self.isRead = isRead
        self.isEdited = isEdited
        self.isMine = isMine
    }
}

// MARK: - MessageType
enum MessageType: String, Sendable, CaseIterable {
    case text
    case image
    case video
    case audio
    case file
    case location
    case sticker
    case notice

    var icon: String {
        switch self {
        case .text: return "text.bubble"
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "mic"
        case .file: return "doc"
        case .location: return "location"
        case .sticker: return "face.smiling"
        case .notice: return "bell"
        }
    }
}

// MARK: - MessageService
/// 即时通讯服务，对应 Rust 的 room.timeline() / send() / send_reply() / edit() / redact() / send_reaction() 等。

@MainActor
final class MessageService: ObservableObject {
    static let shared = MessageService()

    @Published private(set) var messagesByRoom: [String: [ChatMessage]] = [:]
    private var nextId: Int = 0
    let pageSize = 30

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() { loadMockData() }

    // MARK: - 消息列表

    func fetchMessages(roomId: String, page: Int = 0) async throws -> [ChatMessage] {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        let timeline = room.timeline()
        // TimelineListener 模式收集事件：
        // FFI paginateBackwards 仅返回 Bool，事件通过 onUpdate 回调到达，
        // 需用 TimelineEventCollector 缓存后在 Swift 侧转换为 ChatMessage
        let collector = TimelineEventCollector()
        let _ = await timeline.addListener(listener: collector)
        let _ = try await timeline.paginateBackwards(numEvents: UInt16(pageSize))
        return collector.events.map { item in
            let eventId: String
            switch item.eventOrTransactionId {
            case .eventId(let id): eventId = id
            case .transactionId(let tid): tid
            }
            return ChatMessage(id: eventId,
                       roomId: roomId, senderId: item.sender,
                       senderName: item.displayName, senderAvatar: nil,
                       body: item.extractedBody ?? "", timestamp: item.date)
        }
    }

    func fetchRooms() async throws -> [ChatRoom] {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let rooms = try await client.rooms()
        return rooms.map { room in
            let roomId = room.id()
            // 优先读房间缓存
            if let cached = AppContainer.shared.profileCache.getRoom(roomId: roomId) {
                return ChatRoom(id: roomId, name: cached.displayName,
                               avatarUrl: cached.avatarUrl,
                               lastMessage: nil, unreadCount: 0, lastActive: Date())
            }
            // 未命中：读 FFI 并回写缓存
            let name = room.name() ?? ""
            let avatar = room.avatarUrl().flatMap { URL(string: $0) }
            let roomProfile = ProfileCache.RoomProfile(roomId: roomId, displayName: name, avatarUrl: avatar)
            AppContainer.shared.profileCache.setRoom(roomId: roomId, profile: roomProfile)
            return ChatRoom(id: roomId, name: name,
                           avatarUrl: avatar,
                           lastMessage: nil, unreadCount: 0, lastActive: Date())
        }
    }

    // MARK: - 发送消息

    func sendMessage(roomId: String, body: String, msgType: MessageType = .text) async throws -> String {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        let msgId = UUID().uuidString
        // m.room.message event type with JSON body
        let contentJson = """
        {"msgtype":"\(msgType == .text ? "m.text" : "m.text")","body":"\(body)"}
        """
        try await room.sendRaw(eventType: "m.room.message", contentJson: contentJson)
        return msgId
    }

    func sendReply(_ roomId: String, replyTo: ChatMessage, body: String) -> String {
        let msgId = UUID().uuidString
        let msg = ChatMessage(
            id: msgId, roomId: roomId, senderId: "@me:example.com",
            senderName: "小明", senderAvatar: nil,
            body: body, timestamp: Date(), replyTo: replyTo.id, isMine: true
        )
        messagesByRoom[roomId, default: []].append(msg)
        return msgId
    }

    // MARK: - 编辑 / 撤回

    func editMessage(roomId: String, messageId: String, newBody: String) {
        guard var msgs = messagesByRoom[roomId],
              let idx = msgs.firstIndex(where: { $0.id == messageId }) else { return }
        msgs[idx] = ChatMessage(
            id: msgs[idx].id, roomId: msgs[idx].roomId,
            senderId: msgs[idx].senderId, senderName: msgs[idx].senderName,
            senderAvatar: msgs[idx].senderAvatar,
            body: newBody, formattedBody: msgs[idx].formattedBody,
            messageType: msgs[idx].messageType, timestamp: msgs[idx].timestamp,
            replyTo: msgs[idx].replyTo, editVersion: msgs[idx].editVersion + 1,
            reactions: msgs[idx].reactions, isRead: msgs[idx].isRead,
            isEdited: true, isMine: msgs[idx].isMine
        )
        messagesByRoom[roomId] = msgs
    }

    func redactMessage(roomId: String, messageId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        try await room.redact(eventId: messageId, reason: nil)
    }

    // MARK: - 表情回应

    func sendReaction(roomId: String, messageId: String, emoji: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        try await room.timeline().toggleReaction(eventId: messageId, key: emoji)
    }

    func removeReaction(roomId: String, messageId: String, emoji: String) {
        guard var msgs = messagesByRoom[roomId],
              let idx = msgs.firstIndex(where: { $0.id == messageId }) else { return }
        var reactions = msgs[idx].reactions
        if let count = reactions[emoji], count > 1 {
            reactions[emoji] = count - 1
        } else {
            reactions.removeValue(forKey: emoji)
        }
        msgs[idx] = rebuildMessage(msgs[idx], reactions: reactions)
        messagesByRoom[roomId] = msgs
    }

    // MARK: - 附件上传

    /// 发送附件，直接调用 Rust FFI sendAttachment
    func sendAttachment(roomId: String, filename: String, mimeType: String, data: Data, caption: String? = nil) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        try await room.sendAttachment(filename: filename, mimeType: mimeType, data: data, caption: caption)
    }

    // MARK: - 转发消息

    /// 将消息从源房间转发到目标房间
    /// - Parameters:
    ///   - fromRoomId: 源房间 ID
    ///   - toRoomId: 目标房间 ID
    ///   - originalEventId: 原始消息的 eventId（即 ChatMessage.id）
    ///
    /// 实现流程：
    /// 1. 通过 FFI 获取源房间的 Timeline，分页拉取事件
    /// 2. 在 Timeline 中定位原消息的 EventTimelineItem，提取 extractedBody
    /// 3. 获取目标房间，通过 sendRaw(eventType:contentJson:) 重新发送
    func forwardMessage(fromRoomId: String, toRoomId: String, originalEventId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }

        // 1. 获取源房间的 Timeline，通过分页定位原消息
        let sourceRoom = try await client.getRoom(roomId: fromRoomId)
        let sourceTimeline = sourceRoom.timeline()
        let collector = TimelineEventCollector()
        let _ = await sourceTimeline.addListener(listener: collector)
        let _ = try await sourceTimeline.paginateBackwards(numEvents: UInt16(pageSize))

        // 2. 查找原消息的 EventTimelineItem
        guard let sourceEvent = collector.events.first(where: { item in
            if case .eventId(let id) = item.eventOrTransactionId { return id == originalEventId }
            return false
        }) else {
            throw SocialFeedError.forwardFailed("源消息未在 Timeline 中定位到: \(originalEventId)")
        }

        // 3. 获取目标房间并发送
        let targetRoom = try await client.getRoom(roomId: toRoomId)
        let bodyText = sourceEvent.extractedBody ?? ""
        // 对文本中的 JSON 特殊字符做转义，与 SocialFeedService.postMoment 保持一致
        let escapedBody = bodyText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        let contentJson = """
        {"msgtype":"m.text","body":"\(escapedBody)"}
        """
        try await targetRoom.sendRaw(eventType: "m.room.message", contentJson: contentJson)
    }

    // MARK: - 未读计数

    func getUnreadCount(roomId: String) -> Int {
        (messagesByRoom[roomId] ?? []).filter { !$0.isRead }.count
    }

    func markAsRead(roomId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        try await room.timeline().markAsRead(receiptType: .read)
    }

    // MARK: - Private

    private func rebuildMessage(_ m: ChatMessage, body: String? = nil, formattedBody: String? = nil,
                                messageType: MessageType? = nil, timestamp: Date? = nil,
                                replyTo: String? = nil, editVersion: Int? = nil,
                                reactions: [String: Int]? = nil, isRead: Bool? = nil,
                                isEdited: Bool? = nil, isMine: Bool? = nil) -> ChatMessage {
        ChatMessage(
            id: m.id, roomId: m.roomId, senderId: m.senderId,
            senderName: m.senderName, senderAvatar: m.senderAvatar,
            body: body ?? m.body, formattedBody: formattedBody ?? m.formattedBody,
            messageType: messageType ?? m.messageType, timestamp: timestamp ?? m.timestamp,
            replyTo: replyTo ?? m.replyTo, editVersion: editVersion ?? m.editVersion,
            reactions: reactions ?? m.reactions, isRead: isRead ?? m.isRead,
            isEdited: isEdited ?? m.isEdited, isMine: isMine ?? m.isMine
        )
    }

    // MARK: - Mock Data

    private func loadMockData() {
        let now = Date()
        messagesByRoom = [
            "!room_alice:example.com": [
                ChatMessage(id: "a1", roomId: "!room_alice", senderId: "@alice:example.com",
                            senderName: "Alice", senderAvatar: nil,
                            body: "嗨，最近怎么样？", timestamp: now.addingTimeInterval(-600), isRead: true),
                ChatMessage(id: "a2", roomId: "!room_alice", senderId: "@me:example.com",
                            senderName: "小明", senderAvatar: nil,
                            body: "挺好的！正在学习 Matrix Rust SDK 😊", timestamp: now.addingTimeInterval(-580), isMine: true),
                ChatMessage(id: "a3", roomId: "!room_alice", senderId: "@alice:example.com",
                            senderName: "Alice", senderAvatar: nil,
                            body: "太棒了！Sliding Sync 真的很快，冷启动不到 500ms", timestamp: now.addingTimeInterval(-560),
                            reactions: ["🔥": 2, "👍": 3], isRead: true),
            ],
            "!room_bob:example.com": [
                ChatMessage(id: "b1", roomId: "!room_bob", senderId: "@bob:example.com",
                            senderName: "Bob", senderAvatar: nil,
                            body: "周末去爬山吗？", timestamp: now.addingTimeInterval(-3600), isRead: true),
            ],
            "!room_charlie:example.com": [
                ChatMessage(id: "c1", roomId: "!room_charlie", senderId: "@charlie:example.com",
                            senderName: "Charlie", senderAvatar: nil,
                            body: "分享一篇关于 E2EE 的文章", timestamp: now.addingTimeInterval(-7200), isRead: false),
            ],
        ]
    }

    private var mockRooms: [ChatRoom] {
        [
            ChatRoom(id: "!room_alice:example.com", displayName: "Alice", avatarUrl: nil,
                     lastMessage: "太棒了！Sliding Sync 真的很快", lastMessageTime: Date().addingTimeInterval(-560),
                     unreadCount: 0, isDirect: true, isEncrypted: true),
            ChatRoom(id: "!room_bob:example.com", displayName: "Bob", avatarUrl: nil,
                     lastMessage: "周末去爬山吗？", lastMessageTime: Date().addingTimeInterval(-3600),
                     unreadCount: 0, isDirect: true, isEncrypted: true),
            ChatRoom(id: "!room_charlie:example.com", displayName: "Charlie", avatarUrl: nil,
                     lastMessage: "分享一篇关于 E2EE 的文章", lastMessageTime: Date().addingTimeInterval(-7200),
                     unreadCount: 1, isDirect: true, isEncrypted: true),
        ]
    }
}

// MARK: - ChatRoom Model

struct ChatRoom: Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: URL?
    let lastMessage: String?
    let lastMessageTime: Date?
    let unreadCount: Int
    let isDirect: Bool
    let isEncrypted: Bool
}