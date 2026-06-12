import Foundation

// MARK: - Timeline 回复筛选扩展
//
// 方案说明：
// 由于 FFI 侧无按 m.in_reply_to 批量筛选房间消息的 API（Rust 核心层 Room::messages() 的
// RoomEventFilter 结构体不包含 related_by_rel_types 字段，且 Room::relations() 未通过 FFI
// 导出），本文件采用本地过滤方案：利用每条消息自带的 MsgLikeContent.inReplyTo 字段
// （类型为 InReplyToDetails?），在 Swift 侧对已加载的 Timeline 事件做筛选和分组。
//
// FFI 类型链（已验证 matrix_sdk_ffi.swift 中的真实签名）：
//   TimelineItem.asEvent() → EventTimelineItem?
//   EventTimelineItem.content → TimelineItemContent
//   TimelineItemContent.msgLike(content: MsgLikeContent) — enum case
//   MsgLikeContent.inReplyTo → InReplyToDetails?
//   InReplyToDetails.eventId() → String

extension Array where Element == EventTimelineItem {

    // MARK: - 回复筛选

    /// 从消息列表中筛选出所有回复消息（即含 m.in_reply_to 关系的消息）。
    ///
    /// 筛选逻辑：检查每条消息的 content 是否为 .msgLike，且其 inReplyTo 字段非 nil。
    /// - Returns: 所有作为回复的消息事件列表
    func filterReplies() -> [EventTimelineItem] {
        self.filter { event in
            if case .msgLike(let content) = event.content, content.inReplyTo != nil {
                return true
            }
            return false
        }
    }

    /// 筛选出回复给指定事件 ID 的所有回复消息。
    ///
    /// - Parameter eventId: 被回复的事件 ID（即 Moment.eventId）
    /// - Returns: 所有回复给该事件的回复列表，按时间正序排列
    func replies(to eventId: String) -> [EventTimelineItem] {
        self.filter { event in
            if case .msgLike(let content) = event.content,
               let replyTo = content.inReplyTo,
               replyTo.eventId() == eventId {
                return true
            }
            return false
        }
    }

    // MARK: - 分组

    /// 将被回复事件 ID 作为 key，将所有回复消息按 key 分组。
    ///
    /// - Returns: key 为被回复事件 ID（来源于 InReplyToDetails.eventId()），value 为对应的回复列表
    func groupRepliesByEventId() -> [String: [EventTimelineItem]] {
        var result: [String: [EventTimelineItem]] = [:]
        for event in self {
            if case .msgLike(let content) = event.content,
               let replyTo = content.inReplyTo {
                let repliedEventId = replyTo.eventId()
                result[repliedEventId, default: []].append(event)
            }
        }
        return result
    }
}

// MARK: - EventTimelineItem 文本提取

extension EventTimelineItem {

    /// 从消息内容中提取纯文本正文。
    ///
    /// 仅处理 .msgLike → .message 的消息类型，返回 MessageContent.body。
    /// 对于图片、文件、贴纸等其他消息类型，返回 nil。
    var extractedBody: String? {
        guard case .msgLike(let msgLike) = content,
              case .message(let messageContent) = msgLike.kind else {
            return nil
        }
        return messageContent.body
    }

    /// 从 senderProfile 中提取展示名称。
    ///
    /// ProfileDetails 为 FFI 枚举，.ready 状态表示资料已加载完成，
    /// 此时可取 displayName；其他状态（unavailable / pending / error）回退到 sender 原始 ID。
    var displayName: String {
        switch senderProfile {
        case .ready(let displayName, _, _):
            return displayName ?? sender
        default:
            return sender
        }
    }

    /// 将 timestamp（Unix 毫秒）转换为 Date。
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
}
