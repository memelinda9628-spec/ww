import Foundation

// MARK: - Poll Model
/// 对应 Rust polls 模块的 Poll struct

struct Poll: Identifiable, Sendable {
    let id: String
    let roomId: String
    let question: String
    let options: [PollOption]
    let authorId: String
    let authorName: String
    let totalVotes: Int
    let isClosed: Bool
    let allowsMultiple: Bool
    let isAnonymous: Bool
    let createdAt: Date
    let closesAt: Date?

    var myVote: Set<Int>

    /// 当前用户是否已投票
    var hasVoted: Bool { !myVote.isEmpty }
}

// MARK: - PollOption

struct PollOption: Identifiable, Sendable {
    let id: Int
    let text: String
    let voteCount: Int

    var percentage: Double {
        // 由调用方注入 totalVotes 来计算
        0
    }
}

// MARK: - PollCreateRequest

struct PollCreateRequest: Sendable {
    let question: String
    let options: [String]
    let allowsMultiple: Bool
    let isAnonymous: Bool
    let closesIn: TimeInterval?  // nil = no end time
}

// MARK: - PollService
/// Polls 服务，对应 Rust polls（9 方法）

@MainActor
final class PollService: ObservableObject {
    static let shared = PollService()

    @Published private(set) var pollsByRoom: [String: [Poll]] = [:]

    /// roomId → poll start event 的映射表，用于 castVote/closePoll
    private var pollStartIds: [String: String] = [:]

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() { loadMockData() }

    // MARK: - Poll CRUD

    func fetchPolls(_ roomId: String) async throws -> [Poll] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return pollsByRoom[roomId] ?? []
    }

    func createPoll(roomId: String, question: String, answers: [String], maxSelections: UInt8, kind: PollKind) async throws -> Poll {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        try await room.timeline().createPoll(question: question, answers: answers, maxSelections: maxSelections, kind: kind)
        let poll = Poll(
            id: UUID().uuidString,
            roomId: roomId,
            question: question,
            options: answers.enumerated().map { PollOption(id: $0, text: $1, voteCount: 0) },
            authorId: "@me:example.com",
            authorName: "小明",
            totalVotes: 0,
            isClosed: false,
            allowsMultiple: maxSelections > 1,
            isAnonymous: kind == .undisclosed,
            createdAt: Date(),
            closesAt: nil,
            myVote: []
        )
        pollsByRoom[roomId, default: []].append(poll)
        return poll
    }

    func getPollDetail(pollId: String) async throws -> Poll {
        try await Task.sleep(nanoseconds: 200_000_000)
        for (_, polls) in pollsByRoom {
            if let poll = polls.first(where: { $0.id == pollId }) {
                return poll
            }
        }
        throw SocialFeedError.notFound("Poll not found")
    }

    // MARK: - Voting

    func castVote(pollId: String, optionIds: Set<Int>) async throws -> Bool {
        // 从映射表获取真实的 poll start event ID
        guard let pollStartId = pollStartIds[pollId] else {
            throw SocialFeedError.notFound("pollStartId 未找到，请先调用 createPoll 或 startPollTracking")
        }

        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        // 通过 pollStartId 定位所在房间：从 pollsByRoom 反查 roomId
        var targetRoomId: String?
        for (roomId, polls) in pollsByRoom {
            if polls.contains(where: { $0.id == pollId }) {
                targetRoomId = roomId
                break
            }
        }
        guard let roomId = targetRoomId else {
            throw SocialFeedError.notFound("Poll not found")
        }

        let room = try await client.getRoom(roomId: roomId)
        try await room.timeline().sendPollResponse(pollStartId: pollStartId, answers: Array(optionIds))

        // 更新本地状态
        return await updateLocalVote(pollId: pollId, optionIds: optionIds)
    }

    /// 更新本地投票状态（不涉及网络请求）
    private func updateLocalVote(pollId: String, optionIds: Set<Int>) async -> Bool {
        for (roomId, var polls) in pollsByRoom {
            if let idx = polls.firstIndex(where: { $0.id == pollId }) {
                var poll = polls[idx]
                guard !poll.isClosed else {
                    throw SocialFeedError.invalidJson("投票已关闭")
                }
                // 单选时替换已有投票
                if poll.hasVoted && !poll.allowsMultiple {
                    for oldOptionId in poll.myVote {
                        if let optIdx = poll.options.firstIndex(where: { $0.id == oldOptionId }) {
                            poll.options[optIdx] = PollOption(
                                id: poll.options[optIdx].id,
                                text: poll.options[optIdx].text,
                                voteCount: max(0, poll.options[optIdx].voteCount - 1)
                            )
                        }
                    }
                    poll.myVote = []
                    poll.totalVotes = max(0, poll.totalVotes - 1)
                }
                // 添加新投票
                for optionId in optionIds {
                    if let optIdx = poll.options.firstIndex(where: { $0.id == optionId }) {
                        poll.options[optIdx] = PollOption(
                            id: poll.options[optIdx].id,
                            text: poll.options[optIdx].text,
                            voteCount: poll.options[optIdx].voteCount + 1
                        )
                    }
                }
                poll.myVote = optionIds
                poll.totalVotes += optionIds.count
                polls[idx] = poll
                pollsByRoom[roomId] = polls
                return true
            }
        }
        throw SocialFeedError.notFound("Poll not found")
    }

    func retractVote(pollId: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)

        for (roomId, var polls) in pollsByRoom {
            if let idx = polls.firstIndex(where: { $0.id == pollId }) {
                var poll = polls[idx]
                guard !poll.isClosed else {
                    throw SocialFeedError.invalidJson("投票已关闭")
                }
                for optionId in poll.myVote {
                    if let optIdx = poll.options.firstIndex(where: { $0.id == optionId }) {
                        poll.options[optIdx] = PollOption(
                            id: poll.options[optIdx].id,
                            text: poll.options[optIdx].text,
                            voteCount: max(0, poll.options[optIdx].voteCount - 1)
                        )
                    }
                }
                poll.totalVotes = max(0, poll.totalVotes - poll.myVote.count)
                poll.myVote = []
                polls[idx] = poll
                pollsByRoom[roomId] = polls
                return
            }
        }
    }

    func closePoll(pollId: String) async throws {
        // 从映射表获取真实的 poll start event ID
        guard let pollStartId = pollStartIds[pollId] else {
            throw SocialFeedError.notFound("pollStartId 未找到，请先调用 createPoll 或 startPollTracking")
        }

        // 反查 roomId
        var targetRoomId: String?
        for (roomId, polls) in pollsByRoom {
            if polls.contains(where: { $0.id == pollId }) {
                targetRoomId = roomId
                break
            }
        }
        guard let roomId = targetRoomId, let client = ffiClient else {
            throw SocialFeedError.notFound("Poll not found 或客户端未初始化")
        }

        let room = try await client.getRoom(roomId: roomId)
        try await room.timeline().endPoll(pollStartId: pollStartId, text: "投票已关闭")

        // 更新本地状态
        for (roomId, var polls) in pollsByRoom {
            if let idx = polls.firstIndex(where: { $0.id == pollId }) {
                var poll = polls[idx]
                poll = Poll(
                    id: poll.id, roomId: poll.roomId, question: poll.question,
                    options: poll.options, authorId: poll.authorId,
                    authorName: poll.authorName, totalVotes: poll.totalVotes,
                    isClosed: true, allowsMultiple: poll.allowsMultiple,
                    isAnonymous: poll.isAnonymous, createdAt: poll.createdAt,
                    closesAt: poll.closesAt, myVote: poll.myVote
                )
                polls[idx] = poll
                pollsByRoom[roomId] = polls
                return
            }
        }
    }

    // MARK: - Poll Start ID Tracking

    /// 开始监听指定房间的 Timeline，从中提取 poll start event ID
    /// - Parameter roomId: 要监听的房间 ID
    ///
    /// 采用 TimelineListener 模式：
    /// FFI paginateBackwards(numEvents:) 仅返回 Bool（是否到达起点），
    /// 事件通过 TimelineEventCollector.onUpdate(diff:) 回调收集，
    /// 然后在 Swift 侧筛选 eventTypeRaw == "m.poll.start" 的事件并提取 poll_id。
    func startPollTracking(roomId: String) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        let timeline = room.timeline()

        // 1. 注册 TimelineListener 收集事件
        let collector = TimelineEventCollector()
        let _ = await timeline.addListener(listener: collector)

        // 2. 触发向后翻页加载历史事件
        let _ = try await timeline.paginateBackwards(numEvents: 50)

        // 3. 从收集到的事件中筛选 m.poll.start 事件
        for item in collector.events {
            guard item.eventTypeRaw == "m.poll.start" else { continue }

            let eventId: String
            switch item.eventOrTransactionId {
            case .eventId(let id): eventId = id
            case .transactionId: continue
            }

            // 从 state event content 中提取 poll_id
            if let localPollId = extractPollIdFromContent(item.content) {
                pollStartIds[localPollId] = eventId
            }
        }
    }

    /// 注册单个 poll 的 start event ID
    func registerPollStartId(localPollId: String, startEventId: String) {
        pollStartIds[localPollId] = startEventId
    }

    /// 从 TimelineItemContent 中提取 poll_id。
    /// m.poll.start 在 FFI 中被映射为 TimelineItemContent.state，
    /// Matrix 协议中 state_key 即为 poll_id。
    private func extractPollIdFromContent(_ content: TimelineItemContent) -> String? {
        if case .state(let stateKey, _) = content {
            return stateKey
        }
        return nil
    }

    func deletePoll(pollId: String) {
        for (roomId, var polls) in pollsByRoom {
            if let idx = polls.firstIndex(where: { $0.id == pollId }) {
                polls.remove(at: idx)
                pollsByRoom[roomId] = polls
                return
            }
        }
    }

    func getPollResults(pollId: String) async throws -> [PollOption] {
        try await Task.sleep(nanoseconds: 200_000_000)
        for (_, polls) in pollsByRoom {
            if let poll = polls.first(where: { $0.id == pollId }) {
                return poll.options
            }
        }
        throw SocialFeedError.notFound("Poll not found")
    }

    // MARK: - Mock Data

    private func loadMockData() {
        pollsByRoom = [
            "!room_general:example.com": [
                Poll(
                    id: "p1", roomId: "!room_general:example.com",
                    question: "下次线下聚会地点？",
                    options: [
                        PollOption(id: 0, text: "北京", voteCount: 12),
                        PollOption(id: 1, text: "上海", voteCount: 8),
                        PollOption(id: 2, text: "深圳", voteCount: 15),
                        PollOption(id: 3, text: "杭州", voteCount: 5),
                    ],
                    authorId: "@alice:example.com", authorName: "Alice",
                    totalVotes: 40, isClosed: false, allowsMultiple: false,
                    isAnonymous: true, createdAt: Date().addingTimeInterval(-7200),
                    closesAt: Date().addingTimeInterval(86400 * 3),
                    myVote: [2]
                ),
                Poll(
                    id: "p2", roomId: "!room_general:example.com",
                    question: "你最常用的编程语言？（多选）",
                    options: [
                        PollOption(id: 0, text: "Rust", voteCount: 22),
                        PollOption(id: 1, text: "Swift", voteCount: 18),
                        PollOption(id: 2, text: "Python", voteCount: 30),
                        PollOption(id: 3, text: "Go", voteCount: 16),
                        PollOption(id: 4, text: "TypeScript", voteCount: 14),
                    ],
                    authorId: "@bob:example.com", authorName: "Bob",
                    totalVotes: 100, isClosed: false, allowsMultiple: true,
                    isAnonymous: false, createdAt: Date().addingTimeInterval(-14400),
                    closesAt: nil, myVote: [0, 1]
                ),
            ],
        ]
    }
}