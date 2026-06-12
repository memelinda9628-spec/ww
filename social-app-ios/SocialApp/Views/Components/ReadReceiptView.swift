import SwiftUI

// MARK: - ReadReceiptView
/// 已读回执查看界面（对应 ReadReceiptService）。
/// 展示房间已读/未读状态，支持手动标记已读。

struct ReadReceiptView: View {
    @StateObject private var viewModel = ReadReceiptViewModel()
    let roomId: String

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("加载已读状态...")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                content
            }
        }
        .navigationTitle("已读回执")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(roomId: roomId)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        List {
            // 状态概览
            Section("房间状态") {
                HStack {
                    Text("未读消息")
                    Spacer()
                    Text("\(viewModel.unreadCount)")
                        .foregroundColor(viewModel.unreadCount > 0 ? .red : .secondary)
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("完全已读")
                    Spacer()
                    Image(systemName: viewModel.isFullyRead ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(viewModel.isFullyRead ? .green : .secondary)
                }
                if let lastRead = viewModel.lastReadTimestamp {
                    HStack {
                        Text("上次已读")
                        Spacer()
                        Text(lastRead, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("标记为未读")
                    Spacer()
                    Image(systemName: viewModel.isMarkedUnread ? "exclamationmark.circle.fill" : "circle")
                        .foregroundColor(viewModel.isMarkedUnread ? .orange : .secondary)
                }
            }

            // 回执类型说明
            Section("回执类型") {
                ForEach(ReceiptType.allCases, id: \.rawValue) { type in
                    HStack {
                        Image(systemName: type.iconName)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.localizedDescription)
                                .font(.body)
                            Text(type.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // 操作
            Section("操作") {
                Button(action: {
                    Task { await viewModel.markAsRead() }
                }) {
                    Label("标记为已读", systemImage: "envelope.open")
                }
                .disabled(viewModel.isLoading)

                Button(action: {
                    Task { await viewModel.markAsFullyRead() }
                }) {
                    Label("标记为完全已读", systemImage: "checkmark.circle")
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}

// MARK: - ReadReceiptViewModel

@MainActor
final class ReadReceiptViewModel: ObservableObject {
    @Published var unreadCount: Int = 0
    @Published var isFullyRead: Bool = false
    @Published var isMarkedUnread: Bool = false
    @Published var lastReadTimestamp: Date?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let service = ReadReceiptService.shared
    private var roomId: String = ""

    func configure(roomId: String) {
        self.roomId = roomId
        loadSummary()
    }

    func loadSummary() {
        let summary = service.getSummary(for: roomId)
        unreadCount = summary.unreadCount
        isFullyRead = summary.isFullyRead
        isMarkedUnread = summary.isMarkedUnread
        lastReadTimestamp = summary.lastReadTimestamp
    }

    func markAsRead() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await service.markAsRead(roomId: roomId, receiptType: .read)
            loadSummary()
        } catch {
            errorMessage = "标记已读失败: \(error.localizedDescription)"
        }
    }

    func markAsFullyRead() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await service.markAsRead(roomId: roomId, receiptType: .fullyRead)
            loadSummary()
        } catch {
            errorMessage = "标记完全已读失败: \(error.localizedDescription)"
        }
    }
}