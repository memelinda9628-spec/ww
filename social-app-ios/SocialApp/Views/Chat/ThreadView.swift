import SwiftUI

// MARK: - ThreadView
/// 线程列表页（对应 ThreadViewModel）。
/// 展示房间内所有线程，含 root message preview。

struct ThreadView: View {
    @StateObject private var viewModel = ThreadViewModel()
    let roomId: String

    init(roomId: String) {
        self.roomId = roomId
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("加载线程...")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("重试") { Task { await viewModel.loadThreads() } }
                        .buttonStyle(.bordered)
                }
            } else if viewModel.threads.isEmpty {
                ContentUnavailableView(
                    "暂无线程",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("长按消息选择"在话题中回复"即可创建线程")
                )
            } else {
                threadList
            }
        }
        .navigationTitle("话题")
        .task {
            viewModel.configure(roomId: roomId)
            await viewModel.loadThreads()
        }
        .refreshable { await viewModel.refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.subscribedThreads.isEmpty {
                    Label("\(viewModel.subscribedThreads.count) 已订阅", systemImage: "bell")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        List {
            ForEach(viewModel.threads) { thread in
                ThreadRow(thread: thread) {
                    Task {
                        await viewModel.setThreadSubscription(
                            threadId: thread.threadId,
                            subscribe: !thread.isSubscribed
                        )
                    }
                }
            }

            if viewModel.hasMore {
                HStack {
                    Spacer()
                    if viewModel.isLoadingMore {
                        ProgressView("加载更多...")
                    } else {
                        Button("加载更多") {
                            Task { await viewModel.paginate() }
                        }
                        .font(.subheadline)
                    }
                    Spacer()
                }
                .id("loadMore")
            }
        }
    }
}

// MARK: - ThreadRow

struct ThreadRow: View {
    let thread: ThreadInfo
    let onToggleSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                AvatarView(url: thread.authorAvatar, name: thread.authorName, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(thread.rootMessageBody)
                        .font(.body)
                        .lineLimit(2)
                }
                Spacer()

                Button {
                    onToggleSubscribe()
                } label: {
                    Image(systemName: thread.isSubscribed ? "bell.fill" : "bell")
                        .font(.caption)
                        .foregroundColor(thread.isSubscribed ? .blue : .secondary)
                }
            }

            if let preview = thread.preview {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .padding(.vertical, 2)
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 6)
            }

            HStack(spacing: 8) {
                Label("\(thread.replyCount) 回复", systemImage: "arrowshape.turn.up.left")
                if let lastReply = thread.lastReplyTime {
                    Text("·")
                    Text(lastReply, style: .relative)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}