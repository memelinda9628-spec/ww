// MARK: - SocialFeedError
/// 22 种错误变体，镜像 Rust social-feed error.rs

import Foundation

enum SocialFeedError: Error, LocalizedError, Sendable {
    // MARK: Client / Connection
    case clientNotInitialized
    case connectionFailed(String)
    case timeout

    // MARK: Room
    case roomNotFound(String)
    case roomAlreadyExists(String)
    case notRoomMember(String)

    // MARK: Profile
    case profileNotFound(String)
    case profileAlreadyExists(String)
    case profileUpdateFailed(String)

    // MARK: Timeline / Post
    case postFailed(String)
    case timelineUnavailable
    case invalidContent(String)

    // MARK: Interaction
    case likeFailed(String)
    case commentFailed(String)
    case forwardFailed(String)

    // MARK: Validation
    case invalidUserId(String)
    case invalidRoomId(String)
    case invalidEventId(String)
    case invalidUrl(String)

    // MARK: Media
    case quotaExceeded
    case mediaTooLarge(Int64, Int64) // actual, limit
    case unsupportedMediaType(String)
    case mediaUploadFailed(String)

    // MARK: Other
    case permissionDenied(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "客户端未初始化"
        case .connectionFailed(let detail):
            return "连接失败: \(detail)"
        case .timeout:
            return "请求超时"
        case .roomNotFound(let id):
            return "房间未找到: \(id)"
        case .roomAlreadyExists(let id):
            return "房间已存在: \(id)"
        case .notRoomMember(let id):
            return "不是房间成员: \(id)"
        case .profileNotFound(let id):
            return "用户资料未找到: \(id)"
        case .profileAlreadyExists(let id):
            return "用户资料已存在: \(id)"
        case .profileUpdateFailed(let detail):
            return "资料更新失败: \(detail)"
        case .postFailed(let detail):
            return "发布失败: \(detail)"
        case .timelineUnavailable:
            return "时间线不可用"
        case .invalidContent(let detail):
            return "内容无效: \(detail)"
        case .likeFailed(let detail):
            return "点赞失败: \(detail)"
        case .commentFailed(let detail):
            return "评论失败: \(detail)"
        case .forwardFailed(let detail):
            return "转发失败: \(detail)"
        case .invalidUserId(let id):
            return "无效用户 ID: \(id)"
        case .invalidRoomId(let id):
            return "无效房间 ID: \(id)"
        case .invalidEventId(let id):
            return "无效事件 ID: \(id)"
        case .invalidUrl(let url):
            return "无效 URL: \(url)"
        case .mediaTooLarge(let actual, let limit):
            return "媒体过大: \(actual) bytes (限制 \(limit) bytes)"
        case .quotaExceeded:
            return "超出配额上限"
        case .unsupportedMediaType(let type):
            return "不支持的媒体类型: \(type)"
        case .mediaUploadFailed(let detail):
            return "媒体上传失败: \(detail)"
        case .permissionDenied(let detail):
            return "权限不足: \(detail)"
        case .unknown(let detail):
            return "未知错误: \(detail)"
        }
    }
}

// MARK: - Result Typealias

typealias FeedResult<T> = Result<T, SocialFeedError>