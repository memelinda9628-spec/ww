import Foundation
import SwiftUI

// MARK: - ThreadInfo
/// 消息线程数据模型，对应 Matrix Thread

struct ThreadInfo: Identifiable, Sendable {
    let id: String
    let threadId: String
    let roomId: String
    let rootEventId: String
    let rootMessageBody: String
    let authorName: String
    let authorAvatar: URL?
    let replyCount: Int
    let lastReplyTime: Date?
    let isSubscribed: Bool
    let preview: String?
}

// MARK: - ThreadViewModel
/// 消息线程列表 ViewModel，对应 Rust Room.threadListService() FFI。
/// 管理：线程列表加载、分页、订阅/取消订阅。

@MainActor
final class ThreadViewModel: ObservableObject {
    // MARK: - 发布状态

    @Published var threads: [ThreadInfo] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    @Published var hasMore: Bool = true
    @Published var selectedThread: ThreadInfo?

    // MARK: - 内部状态

    private var roomId: String = ""
    private var currentPage: Int = 0
    private let pageSize: Int = 30

    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    // MARK: - 初始化

    func configure(roomId: String) {
        guard self.roomId != roomId else { return }
        self.roomId = roomId
        self.threads = []
        self.currentPage = 0
        self.hasMore = true
    }

    // MARK: - 加载线程列表

    func loadThreads() async {
        guard !roomId.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
            let room = try await client.getRoom(roomId: roomId)
            let items = room.threadListService().items()
            threads = items.compactMap { item in
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
                let body: String
                if let content = root.content,
                   case .msgLike(let msgLike) = content,
                   case .message(let msg) = msgLike.kind {
                    body = msg.body
                } else {
                    body = ""
                }
                return ThreadInfo(
                    id: root.eventId,
                    threadId: root.eventId,
                    roomId: roomId,
                    rootEventId: root.eventId,
                    rootMessageBody: body,
                    authorName: name,
                    authorAvatar: avatar,
                    replyCount: Int(item.numReplies),
                    lastReplyTime: Date(timeIntervalSince1970: TimeInterval(root.timestamp) / 1000.0),
                    isSubscribed: false,
                    preview: nil
                )
            }
        } catch {
            errorMessage = "加载线程失败: \(error.localizedDescription)"
            threads = mockThreads()
        }
    }

    /// 分页加载更多线程
    func paginate() async {
        guard !isLoadingMore && hasMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
            let room = try await client.getRoom(roomId: roomId)

            let tls = room.threadListService()
            try await tls.paginate()
            currentPage += 1

            let items = tls.items()
            let existingIds = Set(threads.map { $0.id })
            let more = items.compactMap { item -> ThreadInfo? in
                let root = item.rootEvent
                guard !existingIds.contains(root.eventId) else { return nil }
                let name: String
                let avatar: URL?
                if case .ready(let dn, _, let av) = root.senderProfile {
                    name = dn ?? root.sender
                    avatar = av.flatMap { URL(string: $0) }
                } else {
                    name = root.sender
                    avatar = nil
                }
                let body: String
                if let content = root.content,
                   case .msgLike(let msgLike) = content,
                   case .message(let msg) = msgLike.kind {
                    body = msg.body
                } else {
                    body = ""
                }
                return ThreadInfo(
                    id: root.eventId,
                    threadId: root.eventId,
                    roomId: roomId,
                    rootEventId: root.eventId,
                    rootMessageBody: body,
                    authorName: name,
                    authorAvatar: avatar,
                    replyCount: Int(item.numReplies),
                    lastReplyTime: Date(timeIntervalSince1970: TimeInterval(root.timestamp) / 1000.0),
                    isSubscribed: false,
                    preview: nil
                )
            }
            threads.append(contentsOf: more)
            if more.count < pageSize { hasMore = false }
        } catch {
            errorMessage = "分页加载失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 线程订阅

    func setThreadSubscription(threadId: String, subscribe: Bool) async {
        do {
            if let client = ffiClient {
                let room = try await client.getRoom(roomId: roomId)
                try await room.setThreadSubscription(threadRootEventId: threadId, subscribed: subscribe)
            }
            if let idx = threads.firstIndex(where: { $0.threadId == threadId }) {
                let existing = threads[idx]
                threads[idx] = ThreadInfo(
                    id: existing.id, threadId: existing.threadId,
                    roomId: existing.roomId, rootEventId: existing.rootEventId,
                    rootMessageBody: existing.rootMessageBody,
                    authorName: existing.authorName,
                    authorAvatar: existing.authorAvatar,
                    replyCount: existing.replyCount,
                    lastReplyTime: existing.lastReplyTime,
                    isSubscribed: subscribe,
                    preview: existing.preview
                )
            }
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
        }
    }

    func subscribeToThread(_ threadId: String) async {
        await setThreadSubscription(threadId: threadId, subscribe: true)
    }

    func unsubscribeFromThread(_ threadId: String) async {
        await setThreadSubscription(threadId: threadId, subscribe: false)
    }

    // MARK: - 辅助

    var threadCount: Int { threads.count }

    var subscribedThreads: [ThreadInfo] {
        threads.filter { $0.isSubscribed }
    }

    func refresh() async {
        currentPage = 0
        threads = []
        hasMore = true
        await loadThreads()
    }

    // MARK: - Mock Data

    private func mockThreads() -> [ThreadInfo] { [
        ThreadInfo(id: "th1", threadId: "th1", roomId: roomId, rootEventId: "ev1",
                   rootMessageBody: "大家觉得 Sliding Sync 的性能优化效果如何？",
                   authorName: "Alice", authorAvatar: nil, replyCount: 12,
                   lastReplyTime: Date().addingTimeInterval(-600), isSubscribed: true,
                   preview: "确实很快，冷启动不到 500ms..."),
        ThreadInfo(id: "th2", threadId: "th2", roomId: roomId, rootEventId: "ev2",
                   rootMessageBody: "有人用过 matrix-rust-sdk 的 E2EE 模块吗？",
                   authorName: "Bob", authorAvatar: nil, replyCount: 8,
                   lastReplyTime: Date().addingTimeInterval(-1800), isSubscribed: false,
                   preview: "1:1 和群聊的加密都支持得很好..."),
        ThreadInfo(id: "th3", threadId: "th3", roomId: roomId, rootEventId: "ev3",
                   rootMessageBody: "下周 Code Review 安排",
                   authorName: "Charlie", authorAvatar: nil, replyCount: 5,
                   lastReplyTime: Date().addingTimeInterval(-3600), isSubscribed: true,
                   preview: "周三下午 3 点可以吗？"),
        ThreadInfo(id: "th4", threadId: "th4", roomId: roomId, rootEventId: "ev4",
                   rootMessageBody: "关于 Spaces 子空间管理的新提案",
                   authorName: "Dave", authorAvatar: nil, replyCount: 23,
                   lastReplyTime: Date().addingTimeInterval(-7200), isSubscribed: false,
                   preview: "我赞同方案二，这样更灵活..."),
    ] }

    private func mockMoreThreads(page: Int) -> [ThreadInfo] {
        guard page < 2 else { return [] }
        return [
            ThreadInfo(id: "th5", threadId: "th5", roomId: roomId, rootEventId: "ev5",
                       rootMessageBody: "iOS 端 SwiftUI 迁移进度汇报",
                       authorName: "Eve", authorAvatar: nil, replyCount: 15,
                       lastReplyTime: Date().addingTimeInterval(-10800), isSubscribed: false,
                       preview: "大部分 View 已经完成迁移..."),
            ThreadInfo(id: "th6", threadId: "th6", roomId: roomId, rootEventId: "ev6",
                       rootMessageBody: "FFI 绑定生成脚本优化讨论",
                       authorName: "Frank", authorAvatar: nil, replyCount: 3,
                       lastReplyTime: Date().addingTimeInterval(-14400), isSubscribed: false,
                       preview: "可以考虑用 CI 自动化..."),
        ]
    }
}