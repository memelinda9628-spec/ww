import Foundation

struct Moment: Identifiable, Sendable {
    let id: String
    let authorId: String
    let authorName: String
    let authorAvatar: URL?
    let text: String
    let images: [URL]
    let createdAt: Date
    let likeCount: UInt64
    let commentCount: UInt64
    let forwardCount: UInt64
    let eventId: String
    /// 该动态所在 Feed 房间 ID，用于 MomentDetailView 中按 m.in_reply_to 关系加载评论
    let feedRoomId: String

    var displayTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var imagesGridColumns: Int {
        switch images.count {
        case 1: return 1
        case 2, 4: return 2
        default: return 3
        }
    }
}
