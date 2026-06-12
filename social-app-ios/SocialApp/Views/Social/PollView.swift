import SwiftUI

// MARK: - PollView
/// 投票界面（对应 PollViewModel）。
/// 选项列表带进度条、投票按钮、倒计时、结果展现。

struct PollView: View {
    @StateObject private var viewModel = PollViewModel()
    let roomId: String
    let pollId: String

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    ProgressView("加载投票...")
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    pollContent
                }
            }
            .padding(20)
        }
        .navigationTitle("投票")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(roomId: roomId, pollId: pollId)
        }
    }

    // MARK: - Poll Content

    @ViewBuilder
    private var pollContent: some View {
        guard let poll = viewModel.poll else {
            ContentUnavailableView("投票不存在", systemImage: "chart.pie")
            return
        }

        // 问题
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(poll.question)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if poll.isClosed {
                    Label("已结束", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                if poll.isAnonymous {
                    Label("匿名", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if poll.allowsMultiple {
                    Label("多选", systemImage: "checklist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Label("\(poll.totalVotes) 票", systemImage: "person.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let remaining = viewModel.timeRemaining, !poll.isClosed {
                    Label(remaining, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // 选项列表
        VStack(spacing: 12) {
            ForEach(viewModel.options) { option in
                PollOptionRow(option: option, hasVoted: viewModel.hasVoted, isClosed: poll.isClosed) {
                    guard !viewModel.isPollClosed else { return }
                    if poll.allowsMultiple {
                        // Toggle selection
                        var selected = Set(viewModel.options.filter(\.isSelected).map(\.id))
                        if selected.contains(option.id) {
                            selected.remove(option.id)
                        } else {
                            selected.insert(option.id)
                        }
                        Task { await viewModel.castVote(optionIds: selected) }
                    } else {
                        Task { await viewModel.castVote(optionIds: [option.id]) }
                    }
                }
            }
        }

        // 底部操作
        VStack(spacing: 12) {
            if !poll.isClosed {
                if viewModel.hasVoted {
                    Button(role: .destructive) {
                        Task { await viewModel.retractVote() }
                    } label: {
                        Label("撤回投票", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    Task { await viewModel.closePoll() }
                } label: {
                    Label("结束投票", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }
}

// MARK: - PollOptionRow

struct PollOptionRow: View {
    let option: PollOptionViewModel
    let hasVoted: Bool
    let isClosed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 10) {
                        if hasVoted || isClosed {
                            Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(option.isSelected ? .blue : .secondary)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.secondary)
                        }
                        Text(option.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if hasVoted || isClosed {
                        Text(String(format: "%.0f%%", option.percentage))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

                if hasVoted || isClosed {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(option.isSelected ? Color.blue : Color.blue.opacity(0.3))
                                .frame(width: geo.size.width * min(option.percentage / 100, 1), height: 8)
                                .animation(.spring(duration: 0.6), value: option.percentage)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(option.isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}