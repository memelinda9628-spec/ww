// MARK: - SocialFeedError
/// 镜像 Rust social-feed error.rs（22 基础变体 + Swift 业务扩展）

import Foundation

enum SocialFeedError: Error, LocalizedError, Sendable {
    // MARK: Client / Connection
    case clientNotInitialized
    case tokenExpired
    case connectionFailed(String)
    case timeout
    case networkError(String)
    case syncError(String)

    // MARK: Room
    case roomNotFound(String)
    case invalidFeedRoom
    case eventNotFound
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

    // MARK: Not Found / State / Rate
    case notFound(String)
    case invalidJson(String)
    case invalidState(String)
    case cyclicDependency
    case rateLimited(retryAfterMs: UInt64)
    case internalError(String)
    case encryptionNotAvailable

    // MARK: Other
    case permissionDenied(String)
    case sdkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "客户端未初始化"
        case .tokenExpired:
            return "认证令牌已过期，请重新登录"
        case .connectionFailed(let detail):
            return "连接失败: \(detail)"
        case .networkError(let detail):
            return "网络错误: \(detail)"
        case .syncError(let detail):
            return "同步失败: \(detail)"
        case .timeout:
            return "请求超时"
        case .roomNotFound(let id):
            return "房间未找到: \(id)"
        case .invalidFeedRoom:
            return "无效的 feed Room"
        case .eventNotFound:
            return "事件不存在"
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
        case .notFound(let detail):
            return "未找到: \(detail)"
        case .invalidJson(let detail):
            return "无效 JSON: \(detail)"
        case .invalidState(let detail):
            return "无效状态: \(detail)"
        case .cyclicDependency:
            return "检测到循环依赖"
        case .rateLimited(retryAfterMs: let ms):
            return "请求被限流，请在 \(ms)ms 后重试"
        case .internalError(let detail):
            return "内部错误: \(detail)"
        case .encryptionNotAvailable:
            return "加密功能不可用"
        case .permissionDenied(let detail):
            return "权限不足: \(detail)"
        case .sdkError(let detail):
            return "SDK 错误: \(detail)"
        case .unknown(let detail):
            return "未知错误: \(detail)"
        }
    }
}

// MARK: - Result Typealias

typealias FeedResult<T> = Result<T, SocialFeedError>