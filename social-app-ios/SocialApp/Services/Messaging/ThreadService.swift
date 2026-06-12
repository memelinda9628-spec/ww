import Foundation

// MARK: - Thread Model
/// 对应 Rust threads 模块的 Thread struct

struct Thread: Identifiable, Sendable {
    let id: String
    let rootEventId: String
    let roomId: String
    let title: String?
    let authorId: String
    let authorName: String
    let authorAvatar: URL?
    let replyCount: Int
    let lastReplyAt: Date
    let lastReplyAuthor: String?
    let isUnread: Bool
    let isParticipating: Bool

    var initial: String { String(authorName.prefix(1)) }
}

// MARK: - ThreadReply
/// 帖子回复

struct ThreadReply: Identifiable, Sendable {
    let id: String
    let threadId: String
    let authorId: String
    let authorName: String
    let authorAvatar: URL?
    let body: String
    let formattedBody: String?
    let createdAt: Date
    let isEdited: Bool
    let reactions: [String: Int]
}

// MARK: - ThreadService
/// Threads 服务，对应 Rust threads（9 方法）

@MainActor
final class ThreadService: ObservableObject {
    static let shared = ThreadService()

    @Published private(set) var threads: [Thread] = []
    @Published private(set) var repliesByThread: [String: [ThreadReply]] = [:]

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() {}

    // MARK: - Thread CRUD

    func fetchThreads(roomId: String) async throws -> [Thread] {
        guard let client = ffiClient else { throw SocialFeedError.notInitialized }
        let room = try await client.getRoom(roomId: roomId)
        let tls = room.threadListService()
        return tls.items().map { item in
            let root = item.rootEvent
            let name: String
            let avatar: URL?
            if case .ready(let dn, _, let av) = root.senderProfile {
                name = dn ?? root.sender
                avatar = av.flatMap { URL(string: $0) }
            } else {
                name = root.sender
                avatar = nil
            }
            return Thread(
                id: root.eventId,
                rootEventId: root.eventId,
                roomId: roomId,
                title: nil,
                authorId: root.sender,
                authorName: name,
                authorAvatar: avatar,
                replyCount: Int(item.numReplies),
                lastReplyAt: Date(timeIntervalSince1970: TimeInterval(root.timestamp) / 1000.0),
                lastReplyAuthor: item.latestEvent?.sender,
                isUnread: false,
                isParticipating: false
            )
        }
    }

    func createThread(roomId: String, rootEventId: String, title: String? = nil) async throws -> Thread {
        let thread = Thread(
            id: UUID().uuidString, rootEventId: rootEventId, roomId: roomId,
            title: title, authorId: "@me:example.com", authorName: "小明",
            authorAvatar: nil, replyCount: 0, lastReplyAt: Date(),
            lastReplyAuthor: nil, isUnread: false, isParticipating: true
        )
        threads.append(thread)
        return thread
    }

    func getThreadDetail(threadId: String) async throws -> Thread {
        guard let thread = threads.first(where: { $0.id == threadId }) else {
            throw SocialFeedError.notFound("Thread not found")
        }
        return thread
    }

    // MARK: - Replies

    func fetchReplies(threadId: String) async throws -> [ThreadReply] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return repliesByThread[threadId] ?? []
    }

    func sendReply(threadId: String, body: String) async throws -> ThreadReply {
        let reply = ThreadReply(
            id: UUID().uuidString, threadId: threadId,
            authorId: "@me:example.com", authorName: "小明",
            authorAvatar: nil, body: body, createdAt: Date(),
            isEdited: false, reactions: [:]
        )
        repliesByThread[threadId, default: []].append(reply)
        // 更新 thread 信息
        if let idx = threads.firstIndex(where: { $0.id == threadId }) {
            threads[idx] = Thread(
                id: threads[idx].id, rootEventId: threads[idx].rootEventId,
                roomId: threads[idx].roomId, title: threads[idx].title,
                authorId: threads[idx].authorId, authorName: threads[idx].authorName,
                authorAvatar: threads[idx].authorAvatar,
                replyCount: threads[idx].replyCount + 1,
                lastReplyAt: Date(), lastReplyAuthor: "@me:example.com",
                isUnread: false, isParticipating: true
            )
        }
        return reply
    }

    func markThreadRead(threadId: String) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[idx] = Thread(
            id: threads[idx].id, rootEventId: threads[idx].rootEventId,
            roomId: threads[idx].roomId, title: threads[idx].title,
            authorId: threads[idx].authorId, authorName: threads[idx].authorName,
            authorAvatar: threads[idx].authorAvatar,
            replyCount: threads[idx].replyCount,
            lastReplyAt: threads[idx].lastReplyAt,
            lastReplyAuthor: threads[idx].lastReplyAuthor,
            isUnread: false, isParticipating: threads[idx].isParticipating
        )
    }

    func deleteThread(threadId: String) {
        threads.removeAll { $0.id == threadId }
        repliesByThread.removeValue(forKey: threadId)
    }

    // MARK: - Thread Stats

    var threadCount: Int { threads.count }

    var unreadThreadCount: Int { threads.filter { $0.isUnread }.count }

    var totalReplies: Int { repliesByThread.values.reduce(0) { $0 + $1.count } }

    // MARK: - Mock Data

    private func loadMockData() {
        threads = [
            Thread(id: "t1", rootEventId: "ev1", roomId: "!room_general:example.com",
                   title: "欢迎大家加入 Threema 测试社区", authorId: "@alice:example.com",
                   authorName: "Alice", authorAvatar: nil,
                   replyCount: 5, lastReplyAt: Date().addingTimeInterval(-1200),
                   lastReplyAuthor: "@bob:example.com", isUnread: true, isParticipating: true),
            Thread(id: "t2", rootEventId: "ev2", roomId: "!room_general:example.com",
                   title: nil, authorId: "@charlie:example.com",
                   authorName: "Charlie", authorAvatar: nil,
                   replyCount: 2, lastReplyAt: Date().addingTimeInterval(-3600),
                   lastReplyAuthor: "@charlie:example.com", isUnread: false, isParticipating: false),
        ]

        repliesByThread = [
            "t1": [
                ThreadReply(id: "r1", threadId: "t1", authorId: "@bob:example.com",
                            authorName: "Bob", authorAvatar: nil,
                            body: "欢迎欢迎！这个社区越来越热闹了。",
                            createdAt: Date().addingTimeInterval(-1800), isEdited: false,
                            reactions: ["👍": 3]),
                ThreadReply(id: "r2", threadId: "t1", authorId: "@dave:example.com",
                            authorName: "Dave", authorAvatar: nil,
                            body: "大家好，我是新来的，请多关照！",
                            createdAt: Date().addingTimeInterval(-1500), isEdited: false,
                            reactions: ["👋": 2]),
                ThreadReply(id: "r3", threadId: "t1", authorId: "@me:example.com",
                            authorName: "小明", authorAvatar: nil,
                            body: "欢迎加入！有不懂的尽管问。",
                            createdAt: Date().addingTimeInterval(-1200), isEdited: false,
                            reactions: [:]),
            ],
        ]
    }
}