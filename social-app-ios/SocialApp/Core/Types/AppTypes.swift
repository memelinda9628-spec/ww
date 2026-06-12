import Foundation

// MARK: - Pagination Types

struct PaginationToken: Sendable {
    let cursor: String
    let start: Int
    let size: Int
    let direction: PaginationDirection
    let createdAt: Date

    enum PaginationDirection: String, Sendable {
        case forward
        case backward
    }

    static func firstPage(size: Int = 20) -> PaginationToken {
        PaginationToken(cursor: UUID().uuidString, start: 0, size: size, direction: .forward, createdAt: Date())
    }

    func nextToken() -> PaginationToken {
        let newStart = direction == .forward ? start + size : max(0, start - size)
        return PaginationToken(cursor: UUID().uuidString, start: newStart, size: size, direction: direction, createdAt: Date())
    }

    /// 5 分钟过期检测（对应 Rust 的 is_stale）
    func isStale() -> Bool {
        Date().timeIntervalSince(createdAt) > 300
    }
}

struct PagedResult<T>: Sendable {
    let items: [T]
    let total: Int?
    let canPaginateForward: Bool
    let canPaginateBackward: Bool
    let forwardToken: PaginationToken?
    let backwardToken: PaginationToken?

    init(items: [T], total: Int?, canPaginateForward: Bool, canPaginateBackward: Bool,
         forwardToken: PaginationToken? = nil, backwardToken: PaginationToken? = nil) {
        self.items = items
        self.total = total
        self.canPaginateForward = canPaginateForward
        self.canPaginateBackward = canPaginateBackward
        self.forwardToken = forwardToken
        self.backwardToken = backwardToken
    }

    var hasMore: Bool { canPaginateForward }
}

// MARK: - PaginationState
/// 分页历史栈，支持 go_back() 回退到上一页

final class PaginationState: @unchecked Sendable {
    private var history: [PaginationToken] = []

    func push(_ token: PaginationToken) {
        history.append(token)
    }

    func goBack() -> PaginationToken? {
        guard history.count > 1 else { return nil }
        history.removeLast()  // 移除当前页
        return history.last   // 返回上一页
    }

    func reset() {
        history.removeAll()
    }

    var currentToken: PaginationToken? {
        history.last
    }

    var depth: Int { history.count }
}

// MARK: - Search Types

struct SearchFilter: Sendable {
    var keyword: String?
    var authorId: String?
    var startTime: Date?
    var endTime: Date?
    var minLikes: UInt64?
    var minComments: UInt64?
    var hasImages: Bool = false

    init() {}

    func matches(_ moment: Moment) -> Bool {
        if let kw = keyword, !kw.isEmpty {
            guard moment.text.localizedCaseInsensitiveContains(kw) else { return false }
        }
        if let aid = authorId, !aid.isEmpty {
            guard moment.authorId == aid else { return false }
        }
        if let start = startTime {
            guard moment.createdAt >= start else { return false }
        }
        if let end = endTime {
            guard moment.createdAt <= end else { return false }
        }
        if let minL = minLikes {
            guard moment.likeCount >= minL else { return false }
        }
        if let minC = minComments {
            guard moment.commentCount >= minC else { return false }
        }
        if hasImages {
            guard !moment.images.isEmpty else { return false }
        }
        return true
    }
}

enum SortOrder: Sendable {
    case timeDesc, timeAsc, likesDesc, commentsDesc, hotDesc
    func apply(_ moments: [Moment]) -> [Moment] {
        switch self {
        case .timeDesc:     return moments.sorted { $0.createdAt > $1.createdAt }
        case .timeAsc:      return moments.sorted { $0.createdAt < $1.createdAt }
        case .likesDesc:    return moments.sorted { $0.likeCount > $1.likeCount }
        case .commentsDesc: return moments.sorted { $0.commentCount > $1.commentCount }
        case .hotDesc:      return moments.sorted { ($0.likeCount + $0.commentCount) > ($1.likeCount + $1.commentCount) }
        }
    }
}

// MARK: - TokenType
/// 对应 Rust 的 TokenType（4 种）

enum TokenType: String, Sendable {
    case word
    case hashtag
    case mention
    case url
}

// MARK: - SearchIndex (Enhanced)
/// 增强版全文搜索索引，对应 Rust SearchIndex（8 方法 + TokenType）

final class SearchIndex: @unchecked Sendable {
    private var index: [String: Set<String>] = [:]         // term → momentIDs
    private var hashtagIndex: [String: Set<String>] = [:]  // #tag → momentIDs
    private var mentionIndex: [String: Set<String>] = [:]  // @user → momentIDs
    private var tokenTypes: [String: TokenType] = [:]      // term → type
    private let lock = NSLock()

    /// 将 moments 批量索引
    func indexMoments(_ moments: [Moment]) {
        lock.lock(); defer { lock.unlock() }
        for m in moments {
            indexMomentLocked(m)
        }
    }

    /// 索引单条 moment
    func indexMoment(_ moment: Moment) {
        lock.lock(); defer { lock.unlock() }
        indexMomentLocked(moment)
    }

    private func indexMomentLocked(_ m: Moment) {
        let tokens = tokenize(m.text)
        for (term, type) in tokens {
            switch type {
            case .word:
                index[term, default: []].insert(m.id)
            case .hashtag:
                hashtagIndex[term, default: []].insert(m.id)
                index[term, default: []].insert(m.id)
            case .mention:
                mentionIndex[term, default: []].insert(m.id)
                index[term, default: []].insert(m.id)
            case .url:
                index[term, default: []].insert(m.id)
            }
            tokenTypes[term] = type
        }
    }

    /// 全文搜索（AND 逻辑）
    func search(query: String) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        let terms = tokenize(query).map { $0.0 }
        guard !terms.isEmpty else { return [] }
        var results = index[terms[0]] ?? []
        for term in terms.dropFirst() {
            results = results.intersection(index[term] ?? [])
        }
        return results
    }

    /// 按 hashtag 搜索
    func searchHashtag(_ tag: String, limit: Int = 50) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        let normalized = tag.hasPrefix("#") ? String(tag.dropFirst()).lowercased() : tag.lowercased()
        let results = hashtagIndex[normalized] ?? []
        return Set(results.prefix(limit))
    }

    /// 按 mention 搜索
    func searchMention(_ userId: String, limit: Int = 50) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        let normalized = userId.hasPrefix("@") ? String(userId.dropFirst()).lowercased() : userId.lowercased()
        let results = mentionIndex[normalized] ?? []
        return Set(results.prefix(limit))
    }

    /// 从索引中删除 moment
    func removeMoment(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        for (term, var ids) in index { if ids.remove(id) != nil { index[term] = ids.isEmpty ? nil : ids } }
        for (tag, var ids) in hashtagIndex { if ids.remove(id) != nil { hashtagIndex[tag] = ids.isEmpty ? nil : ids } }
        for (user, var ids) in mentionIndex { if ids.remove(id) != nil { mentionIndex[user] = ids.isEmpty ? nil : ids } }
    }

    /// 清空索引
    func clear() {
        lock.lock(); defer { lock.unlock() }
        index.removeAll()
        hashtagIndex.removeAll()
        mentionIndex.removeAll()
        tokenTypes.removeAll()
    }

    /// 索引大小
    var size: Int {
        lock.lock(); defer { lock.unlock() }
        return index.count
    }

    /// 统计信息
    var stats: (words: Int, hashtags: Int, mentions: Int, urls: Int) {
        lock.lock(); defer { lock.unlock() }
        let words = tokenTypes.filter { $0.value == .word }.count
        let hashtags = tokenTypes.filter { $0.value == .hashtag }.count
        let mentions = tokenTypes.filter { $0.value == .mention }.count
        let urls = tokenTypes.filter { $0.value == .url }.count
        return (words, hashtags, mentions, urls)
    }

    // MARK: Tokenizer

    private func tokenize(_ text: String) -> [(String, TokenType)] {
        var results: [(String, TokenType)] = []

        // 提取 #hashtags
        let hashtagPattern = "#[\\w\\u4e00-\\u9fff]+"
        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let nsText = text as NSString
            regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).forEach { match in
                let term = nsText.substring(with: match.range).lowercased()
                results.append((term, .hashtag))
            }
        }

        // 提取 @mentions
        let mentionPattern = "@[\\w._=\\-/]+"
        if let regex = try? NSRegularExpression(pattern: mentionPattern) {
            let nsText = text as NSString
            regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).forEach { match in
                let term = nsText.substring(with: match.range).lowercased()
                results.append((term, .mention))
            }
        }

        // 提取 URLs
        let urlPattern = "https?://[\\w./?=&%#\\-+]+"
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let nsText = text as NSString
            regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).forEach { match in
                let term = nsText.substring(with: match.range).lowercased()
                results.append((term, .url))
            }
        }

        // 普通词汇
        let cleaned = text
            .replacingOccurrences(of: "#[\\w\\u4e00-\\u9fff]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "@[\\w._=\\-/]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "https?://[\\w./?=&%#\\-+]+", with: " ", options: .regularExpression)
        let words = cleaned.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        results.append(contentsOf: words.map { ($0, .word) })

        return results
    }
}

// MARK: - ForwardMetadata
/// 转发元数据，对应 Rust 的 ForwardMetadata

struct ForwardMetadata: Sendable, Codable {
    let originalMomentId: String
    let originalAuthorId: String
    let originalAuthorName: String
    let originalText: String
    let originalCreatedAt: Date
    let originalRoomId: String
    let quoteText: String?

    /// HTML blockquote 格式（用于 Matrix formatted_body）
    func formattedBody() -> String {
        """
        <blockquote>
        <p><strong>\(originalAuthorName)</strong></p>
        <p>\(originalText)</p>
        </blockquote>

        \(quoteText ?? "")
        """
    }

    /// 纯文本格式
    func plainBody() -> String {
        """
        > \(originalAuthorName): \(originalText)

        \(quoteText ?? "")
        """
    }

    /// JSON 序列化
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// JSON 反序列化
    static func fromJSON(_ json: String) -> ForwardMetadata? {
        guard let data = json.data(using: .utf8),
              let meta = try? JSONDecoder().decode(ForwardMetadata.self, from: data) else { return nil }
        return meta
    }
}

// MARK: - Forward Manager (Enhanced)

enum ForwardManager {
    static func buildEventURL(roomId: String, eventId: String) -> String {
        "matrix://roomid/\(roomId)/eventid/\(eventId)"
    }

    static func parseMatrixURL(_ url: String) -> (roomId: String, eventId: String)? {
        guard url.hasPrefix("matrix://roomid/") else { return nil }
        let parts = url.components(separatedBy: "/eventid/")
        guard parts.count == 2 else { return nil }
        let roomId = String(parts[0].dropFirst("matrix://roomid/".count))
        return (roomId, parts[1])
    }

    static func detectForwardLoop(quoteText: String, maxDepth: Int = 3) -> Bool {
        let depth = quoteText.components(separatedBy: "<blockquote>").count - 1
        return depth > maxDepth
    }

    /// 创建转发元数据
    static func createMetadata(from moment: Moment, quoteText: String?) -> ForwardMetadata {
        ForwardMetadata(
            originalMomentId: moment.id,
            originalAuthorId: moment.authorId,
            originalAuthorName: moment.authorName,
            originalText: moment.text,
            originalCreatedAt: moment.createdAt,
            originalRoomId: "!feed_\(moment.authorId):example.com",
            quoteText: quoteText
        )
    }
}