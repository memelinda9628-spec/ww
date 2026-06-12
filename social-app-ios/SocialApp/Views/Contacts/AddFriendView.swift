import SwiftUI

// MARK: - AddFriendView
/// 添加好友页（对应 AddFriendViewModel）。
/// 搜索框 → 用户列表 → "添加"/"已发送"按钮。

struct AddFriendView: View {
    @StateObject private var viewModel = AddFriendViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                searchBar
                Divider()

                // 内容区
                Group {
                    if viewModel.isSearching {
                        ProgressView("正在搜索...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.errorMessage {
                        VStack(spacing: 12) {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button("重试") { Task { await viewModel.searchUsers() } }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.searchTerm.isEmpty {
                        pendingInvitationsSection
                    } else if viewModel.searchResults.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchTerm)
                    } else {
                        searchResultsList
                    }
                }
            }
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task { viewModel.loadPendingInvitations() }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("输入用户名或 Matrix ID 搜索", text: $viewModel.searchTerm)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { Task { await viewModel.searchUsers() } }
            if !viewModel.searchTerm.isEmpty {
                Button {
                    viewModel.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Pending Invitations

    private var pendingInvitationsSection: some View {
        List {
            if !viewModel.pendingInvitations.isEmpty {
                Section("待处理的邀请") {
                    ForEach(viewModel.pendingInvitations) { user in
                        SearchedUserRow(user: user) {
                            HStack(spacing: 12) {
                                Button("接受") {
                                    Task { await viewModel.acceptInvitation(from: user) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("拒绝") {
                                    Task { await viewModel.declineInvitation(from: user) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.red)
                            }
                        }
                    }
                }
            }

            Section {
                Text("请输入 Matrix ID 或用户名搜索用户")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            Section("搜索结果") {
                ForEach(viewModel.searchResults) { user in
                    SearchedUserRow(user: user) {
                        if viewModel.isRequestInProgress(for: user) {
                            ProgressView().controlSize(.small)
                        } else if viewModel.hasSentRequest(to: user) {
                            Label("已发送", systemImage: "checkmark")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else if user.isAlreadyFriend {
                            Label("已是好友", systemImage: "person.checkmark")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Button("添加") {
                                Task { await viewModel.sendFriendRequest(to: user) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - SearchedUserRow

struct SearchedUserRow<Actions: View>: View {
    let user: SearchedUser
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarUrl, name: user.displayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(user.userId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            actions()
        }
    }
}