import SwiftUI

// MARK: - ReactionView
/// 表情回应界面（对应 ReactionViewModel）。
/// 展示事件上的所有 reaction，支持点击切换添加/移除。

struct ReactionView: View {
    @StateObject private var viewModel = ReactionViewModel()
    let eventId: String
    let roomId: String

    private let commonKeys = ["👍", "❤️", "😂", "🎉", "😮", "😢", "👏", "🔥"]

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 已有 reaction 展示
            if !viewModel.reactions.isEmpty {
                reactionSummary
            }

            // 快捷 reaction 选择器
            quickPicker
        }
        .padding(16)
        .navigationTitle("表情回应")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(eventId: eventId, roomId: roomId)
        }
    }

    // MARK: - Reaction Summary

    private var reactionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(viewModel.totalReactions) 个回应")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                ForEach(viewModel.reactions) { item in
                    Button(action: {
                        Task { await viewModel.toggleReaction(key: item.key) }
                    }) {
                        VStack(spacing: 4) {
                            Text(item.key)
                                .font(.title2)
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(item.isToggledByMe ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(item.isToggledByMe ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Quick Picker

    private var quickPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷回应")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(commonKeys, id: \.self) { key in
                    Button(action: {
                        Task { await viewModel.toggleReaction(key: key) }
                    }) {
                        Text(key)
                            .font(.largeTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.myActiveKey == key
                                        ? Color.accentColor.opacity(0.2)
                                        : Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(viewModel.myActiveKey == key ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}