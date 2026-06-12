import SwiftUI

// MARK: - MomentDetailView
/// 动态详情页 + 评论列表。

struct MomentDetailView: View {
    let moment: Moment
    @StateObject private var viewModel = MomentDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var newComment: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 动态内容
                momentContent
                Divider().padding(.horizontal)
                // 互动统计
                interactionBar
                Divider().padding(.horizontal)
                // 评论列表
                commentsSection
            }
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("分享") {}
                    Button("复制链接") {}
                    Button("举报", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            commentInputBar
        }
        .task {
            await viewModel.loadComments(for: moment.eventId, feedRoomId: moment.feedRoomId)
        }
    }

    // MARK: - 动态内容

    private var momentContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 作者信息
            HStack(spacing: 10) {
                AvatarView(url: moment.authorAvatar, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.authorName)
                        .font(.headline)
                    Text(moment.displayTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // 正文
            if !moment.text.isEmpty {
                Text(moment.text)
                    .font(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 图片网格
            if !moment.images.isEmpty {
                AsyncImageGrid(urls: moment.images)
            }
        }
        .padding()
    }

    // MARK: - 互动统计

    private var interactionBar: some View {
        HStack(spacing: 24) {
            HStack(spacing: 4) {
                Image(systemName: "hand.thumbsup")
                Text("\(moment.likeCount)")
            }
            HStack(spacing: 4) {
                Image(systemName: "text.bubble")
                Text("\(moment.commentCount)")
            }
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.right")
                Text("\(moment.forwardCount)")
            }
            Spacer()
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .padding()
    }

    // MARK: - 评论列表

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("评论 (\(viewModel.comments.count))")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("还没有评论，来说点什么吧")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(viewModel.comments) { comment in
                    CommentRow(comment: comment)
                    Divider().padding(.leading, 60)
                }
            }
        }
    }

    // MARK: - 评论输入栏

    private var commentInputBar: some View {
        HStack(spacing: 12) {
            AvatarView(url: nil, size: 32)
            TextField("写评论...", text: $newComment)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(20)
            Button("发送") {
                sendComment()
            }
            .font(.subheadline.bold())
            .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func sendComment() {
        let text = newComment.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Task {
            await viewModel.addComment(text: text, momentId: moment.eventId)
            newComment = ""
        }
    }
}

// MARK: - CommentRow

private struct CommentRow: View {
    let comment: MomentComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: comment.authorAvatar, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.subheadline.bold())
                    Text(comment.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .lineLimit(nil)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - MomentComment

/// 评论数据模型（临时定义，后续整合到 Models）

struct MomentComment: Identifiable, Sendable {
    let id: String
    let authorName: String
    let authorAvatar: URL?
    let text: String
    let createdAt: Date

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

// MARK: - MomentDetailViewModel

@MainActor
private final class MomentDetailViewModel: ObservableObject {
    @Published var comments: [MomentComment] = []
    @Published var isLoading: Bool = false

    /// 加载该动态的所有评论（回复消息）。
    ///
    /// 方案说明：
    /// 由于 FFI 无按 m.in_reply_to 批量筛选消息的 API（Rust 核心层 RoomEventFilter
    /// 不含 related_by_rel_types 字段，Room::relations() 也未导出），
    /// 本方法通过 SocialFeedService 的本地筛选方案：
    ///   - TimelineListener 监听 Timeline 收集 EventTimelineItem
    ///   - paginateBackwards 触发服务端拉取
    ///   - Swift 侧用 MsgLikeContent.inReplyTo（类型 InReplyToDetails?）筛选回复
    ///   - InReplyToDetails.eventId() 与当前 moment 的 eventId 匹配即判定为评论
    ///
    /// - Parameters:
    ///   - eventId: 当前动态的事件 ID（用于匹配 InReplyToDetails.eventId()）
    ///   - feedRoomId: 动态所在的 Feed 房间 ID
    func loadComments(for eventId: String, feedRoomId: String) async {
        isLoading = true
        defer { isLoading = false }

        comments = await SocialFeedService.shared.loadComments(
            feedRoomId: feedRoomId,
            eventId: eventId
        )
    }

    func addComment(text: String, momentId: String) async {
        // sendReply FFI 已暴露，通过 SocialFeedService.comment() 调用
        try? await SocialFeedService.shared.comment(momentId: momentId, text: text)
        let comment = MomentComment(
            id: UUID().uuidString,
            authorName: "我",
            authorAvatar: nil,
            text: text,
            createdAt: Date()
        )
        comments.append(comment)
    }
}