import Foundation

// MARK: - ReceiptType extensions
// The ReceiptType enum itself comes from matrix-sdk-ffi (Generated).
// These extensions add UI-facing properties not in the Rust type.

extension ReceiptType: CaseIterable {
    public static var allCases: [ReceiptType] {
        [.read, .readPrivate, .fullyRead]
    }

    var localizedDescription: String {
        switch self {
        case .read: return "已读"
        case .readPrivate: return "私密已读"
        case .fullyRead: return "完全已读"
        }
    }

    var iconName: String {
        switch self {
        case .read: return "envelope.open"
        case .readPrivate: return "envelope.badge.shield.half.filled"
        case .fullyRead: return "checkmark.circle"
        }
    }
}

// MARK: - ReadReceiptStatus
/// 已读回执状态

struct ReadReceiptStatus: Sendable {
    let eventId: String
    let receiptType: ReceiptType
    let timestamp: Date
    let senderId: String
    let roomId: String

    var isRead: Bool { true }
}

// MARK: - ReadReceiptSummary
/// 房间已读回执汇总

struct ReadReceiptSummary: Sendable {
    let roomId: String
    let unreadCount: Int
    let lastReadEventId: String?
    let lastReadTimestamp: Date?
    let isMarkedUnread: Bool
    let isFullyRead: Bool
}

// MARK: - ReadReceiptService
/// 已读回执服务，对应 Rust Timeline/Room 的 send_read_receipt 和 mark_as_read。
/// 负责发送已读回执、标记已读、查询未读状态。

@MainActor
final class ReadReceiptService: ObservableObject {
    static let shared = ReadReceiptService()

    @Published private(set) var roomSummaries: [String: ReadReceiptSummary] = [:]
    private var receiptCache: [String: ReadReceiptStatus] = [:]

    
    /// Get the FFI Client from KeychainManager
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

private init() {}

    // MARK: - 发送已读回执

    /// 发送已读回执到指定事件 — 通过 room.sendReadReceipt() FFI
    func sendReadReceipt(
        eventId: String,
        receiptType: ReceiptType = .read,
        roomId: String
    ) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        try await room.sendReadReceipt(receiptType: receiptType, eventId: eventId)

        let status = ReadReceiptStatus(
            eventId: eventId,
            receiptType: receiptType,
            timestamp: Date(),
            senderId: client.userId(),
            roomId: roomId
        )
        receiptCache[eventId] = status

        let summary = ReadReceiptSummary(
            roomId: roomId,
            unreadCount: 0,
            lastReadEventId: eventId,
            lastReadTimestamp: Date(),
            isMarkedUnread: false,
            isFullyRead: receiptType == .fullyRead
        )
        roomSummaries[roomId] = summary
    }

    /// 标记房间为已读 — 通过 room.markAsRead() FFI
    func markAsRead(
        roomId: String,
        receiptType: ReceiptType = .read
    ) async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        let room = try await client.getRoom(roomId: roomId)
        try await room.markAsRead(receiptType: receiptType)

        let summary = ReadReceiptSummary(
            roomId: roomId,
            unreadCount: 0,
            lastReadEventId: nil,
            lastReadTimestamp: Date(),
            isMarkedUnread: false,
            isFullyRead: receiptType == .fullyRead
        )
        roomSummaries[roomId] = summary
    }

    /// 设置完全已读标记
    /// - Parameters:
    ///   - eventId: 事件 ID
    ///   - roomId: 房间 ID
    func markAsFullyRead(eventId: String, roomId: String) async throws {
        try await sendReadReceipt(eventId: eventId, receiptType: .fullyRead, roomId: roomId)
    }

    // MARK: - 查询

    /// 获取房间的已读回执汇总
    func getSummary(for roomId: String) -> ReadReceiptSummary {
        roomSummaries[roomId] ?? ReadReceiptSummary(
            roomId: roomId,
            unreadCount: 0,
            lastReadEventId: nil,
            lastReadTimestamp: nil,
            isMarkedUnread: false,
            isFullyRead: false
        )
    }

    /// 获取所有未读房间 ID
    func unreadRoomIds() -> [String] {
        roomSummaries.filter { $0.value.unreadCount > 0 || !$0.value.isFullyRead }
            .map { $0.key }
    }