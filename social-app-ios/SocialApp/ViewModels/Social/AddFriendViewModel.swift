import Foundation
import SwiftUI

// MARK: - SearchedUser
/// 搜索到的用户

struct SearchedUser: Identifiable, Sendable {
    let id: String
    let userId: String
    let displayName: String
    let avatarUrl: URL?
    let bio: String?
    let isAlreadyFriend: Bool
    let roomId: String?  // 邀请房间 ID，仅 pendingInvitations 场景使用
}

// MARK: - AddFriendViewModel
/// 添加好友 ViewModel，对应 FriendService 搜索与邀请功能。

@MainActor
final class AddFriendViewModel: ObservableObject {
    /// FFI Client
    private var ffiClient: Client? { KeychainManager.shared.ffiClient }

    @Published var searchTerm: String = ""
    @Published var searchResults: [SearchedUser] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?
    @Published var requestInProgress: Set<String> = []
    @Published var sentRequests: Set<String> = []
    @Published var pendingInvitations: [SearchedUser] = []

    // MARK: - 搜索用户

    func searchUsers() async {
        let term = searchTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            searchResults = []
            return
        }

        // 优先读搜索缓存
        if let cached = AppContainer.shared.profileCache.getSearch(keyword: term) {
            searchResults = cached
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            guard let client = ffiClient else {
                errorMessage = "Not initialized"
                return
            }
            let results = try client.searchUsers(searchTerm: term, limit: 20)
            let mapped = results.map { r in
                SearchedUser(
                    id: r.userId,
                    userId: r.userId,
                    displayName: r.displayName ?? r.userId,
                    avatarUrl: r.avatarUrl.flatMap { URL(string: $0) },
                    bio: nil,
                    isAlreadyFriend: false
                )
            }
            // 回写搜索缓存
            AppContainer.shared.profileCache.setSearch(keyword: term, results: mapped)
            searchResults = mapped
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 按完整 Matrix ID 搜索
    func searchByUserId(_ userId: String) async -> SearchedUser? {
        isSearching = true
        defer { isSearching = false }

        do {
            try await Task.sleep(nanoseconds: 800_000_000)
            return SearchedUser(
                id: UUID().uuidString,
                userId: userId,
                displayName: userId.replacingOccurrences(of: "@", with: "").split(separator: ":").first.map(String.init) ?? userId,
                avatarUrl: nil,
                bio: nil,
                isAlreadyFriend: false
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - 发送好友请求

    /// 发送好友请求（在 Matrix 中表示邀请用户进入 DM 房间）
    func sendFriendRequest(to user: SearchedUser) async {
        requestInProgress.insert(user.id)
        defer { requestInProgress.remove(user.id) }

        do {
            // inviteUserById FFI 已接入
            _ = try await client.createDm(userId: user.userId)
            sentRequests.insert(user.id)
        } catch {
            errorMessage = "发送好友请求失败: \(error.localizedDescription)"
        }
    }

    /// 接受收到的邀请
    func acceptInvitation(from user: SearchedUser) async {
        requestInProgress.insert(user.id)
        defer { requestInProgress.remove(user.id) }

        do {
            guard let client = ffiClient, let roomId = user.roomId else {
                errorMessage = "Not initialized or missing room ID"
                return
            }
            let room = try await client.getRoom(roomId: roomId)
            try await room.join()
            pendingInvitations.removeAll { $0.id == user.id }
        } catch {
            errorMessage = "接受邀请失败: \(error.localizedDescription)"
        }
    }

    /// 拒绝邀请
    func declineInvitation(from user: SearchedUser) async {
        do {
            guard let client = ffiClient, let roomId = user.roomId else {
                errorMessage = "Not initialized or missing room ID"
                return
            }
            let room = try await client.getRoom(roomId: roomId)
            try await room.leave()
            pendingInvitations.removeAll { $0.id == user.id }
        } catch {
            errorMessage = "拒绝邀请失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 状态查询

    func isRequestInProgress(for user: SearchedUser) -> Bool {
        requestInProgress.contains(user.id)
    }

    func hasSentRequest(to user: SearchedUser) -> Bool {
        sentRequests.contains(user.id)
    }

    func loadPendingInvitations() {
        pendingInvitations = [
            SearchedUser(id: "inv_1", userId: "@zoe:example.com", displayName: "Zoe", avatarUrl: nil, bio: "来自搜索", isAlreadyFriend: false, roomId: nil),
        ]
    }

    func reset() {
        searchTerm = ""
        searchResults = []
        errorMessage = nil
    }
}