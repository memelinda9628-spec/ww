import SwiftUI

// MARK: - FriendRequestView
/// 好友请求列表页。
/// 列出所有待处理的 invited 房间（is_direct=true 且 membership=invite），
/// 提供"接受"/"拒绝"按钮。

struct FriendRequestView: View {
    @StateObject private var viewModel = FriendRequestViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("加载请求...")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.clock")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("重试") { Task { await viewModel.loadRequests() } }
                        .buttonStyle(.bordered)
                }
            } else if viewModel.requests.isEmpty {
                ContentUnavailableView(
                    "没有待处理的好友请求",
                    systemImage: "person.badge.plus",
                    description: Text("当有人发送好友请求时，会在此处显示")
                )
            } else {
                requestsList
            }
        }
        .navigationTitle("好友请求")
        .task { await viewModel.loadRequests() }
        .refreshable { await viewModel.loadRequests() }
    }

    // MARK: - Requests List

    private var requestsList: some View {
        List {
            ForEach(viewModel.requests) { request in
                FriendRequestRow(request: request) {
                    Task { await viewModel.acceptRequest(request) }
                } onDecline: {
                    Task { await viewModel.declineRequest(request) }
                }
            }
        }
    }
}

// MARK: - FriendRequestRow

struct FriendRequestRow: View {
    let request: FriendRequestInfo
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: request.avatarUrl, name: request.displayName, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(request.displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(request.userId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let message = request.inviteMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .italic()
                }
            }
            Spacer()
            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Text("接受")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("拒绝")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - FriendRequestInfo

struct FriendRequestInfo: Identifiable, Sendable {
    let id: String
    let roomId: String
    let userId: String
    let displayName: String
    let avatarUrl: URL?
    let inviteMessage: String?
    let timestamp: Date
}

// MARK: - FriendRequestViewModel

@MainActor
final class FriendRequestViewModel: ObservableObject {
    @Published var requests: [FriendRequestInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    func loadRequests() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }

            // 从 Client.rooms() 过滤 invited direct rooms
            let allRooms = try await client.rooms()
            let invitedRooms = allRooms.filter { room in
                room.membership() == .invite && room.isDirect()
            }
            requests = invitedRooms.map { room in
                FriendRequestInfo(
                    id: room.id(),
                    roomId: room.id(),
                    userId: room.inviter()?.userId ?? "",
                    displayName: room.inviter()?.displayName ?? room.name() ?? "未知用户",
                    avatarUrl: room.inviter()?.avatarUrl.flatMap { URL(string: $0) },
                    inviteMessage: nil,
                    timestamp: Date()
                )
            }
        } catch {
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
    }

    func acceptRequest(_ request: FriendRequestInfo) async {
        do {
            guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
            let room = try await client.getRoom(roomId: request.roomId)
            try await room.join()
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = "接受失败: \(error.localizedDescription)"
        }
    }

    func declineRequest(_ request: FriendRequestInfo) async {
        do {
            guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
            let room = try await client.getRoom(roomId: request.roomId)
            try await room.leave()
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = "拒绝失败: \(error.localizedDescription)"
        }
    }
}