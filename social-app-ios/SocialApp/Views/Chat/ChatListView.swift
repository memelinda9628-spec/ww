import SwiftUI

// MARK: - ChatListView
/// 会话列表视图，显示所有聊天房间

struct ChatListView: View {
    @StateObject private var viewModel = ChatListViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            List {
                if !searchText.isEmpty {
                    Section("搜索结果") {
                        ForEach(viewModel.searchResults) { room in
                            NavigationLink(destination: ChatDetailView(roomId: room.id, roomName: room.displayName)) {
                                ChatRoomRow(room: room)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(viewModel.rooms) { room in
                            NavigationLink(destination: ChatDetailView(roomId: room.id, roomName: room.displayName)) {
                                ChatRoomRow(room: room)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.leaveRoom(room.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    viewModel.markAsRead(room.id)
                                } label: {
                                    Label("已读", systemImage: "envelope.open")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索聊天")
            .onChange(of: searchText) { newValue in
                viewModel.search(query: newValue)
            }
            .navigationTitle("聊天")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.startNewChat() }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .refreshable {
                await viewModel.loadRooms()
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("加载中...")
                }
            }
        }
        .task {
            await viewModel.loadRooms()
        }
    }
}

// MARK: - ChatRoomRow

struct ChatRoomRow: View {
    let room: ChatRoom

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: room.displayName, url: room.avatarUrl, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if room.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    if let time = room.lastMessageTime {
                        Text(formatTime(time))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text(room.lastMessage ?? "暂无消息")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if room.unreadCount > 0 {
                        Text("\(room.unreadCount)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ChatListViewModel

@MainActor
final class ChatListViewModel: ObservableObject {
    @Published var rooms: [ChatRoom] = []
    @Published var searchResults: [ChatRoom] = []
    @Published var isLoading = false

    private let messageService = MessageService.shared

    func loadRooms() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rooms = try await messageService.fetchRooms()
        } catch {
            print("[ChatListViewModel] 加载失败: \(error)")
        }
    }

    func search(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        let lower = query.lowercased()
        searchResults = rooms.filter {
            $0.displayName.lowercased().contains(lower) ||
            ($0.lastMessage?.lowercased().contains(lower) ?? false)
        }
    }

    func markAsRead(_ roomId: String) {
        messageService.markAsRead(roomId: roomId)
    }

    func leaveRoom(_ roomId: String) {
        rooms.removeAll { $0.id == roomId }
    }

    func startNewChat() {
        // TODO: 跳转到新建聊天界面
    }
}