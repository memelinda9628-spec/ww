import SwiftUI

// MARK: - ContactsView
/// 联系人列表页（对应 ContactsViewModel）。
/// 支持按首字母分组索引、搜索栏、联系人行（头像+名称+状态）。

struct ContactsView: View {
    @StateObject private var viewModel = ContactsViewModel()
    @State private var showAddFriend = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("加载联系人...")
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("重试") { Task { await viewModel.loadContacts() } }
                            .buttonStyle(.bordered)
                    }
                } else if viewModel.sections.isEmpty {
                    ContentUnavailableView(
                        "暂无联系人",
                        systemImage: "person.slash",
                        description: Text("发送好友请求，建立您的通讯录")
                    )
                } else {
                    contactList
                }
            }
            .navigationTitle("联系人")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if viewModel.pendingRequestsCount > 0 {
                            NavigationLink(destination: FriendRequestView()) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "person.badge.plus")
                                    Text("\(viewModel.pendingRequestsCount)")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(3)
                                        .background(Circle().fill(.red))
                                        .offset(x: 8, y: -6)
                                }
                            }
                        }
                        Button {
                            showAddFriend = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "搜索联系人")
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
            .task { await viewModel.loadContacts() }
            .refreshable { await viewModel.loadContacts() }
        }
    }

    // MARK: - Contact List

    private var contactList: some View {
        List {
            ForEach(searchResults) { section in
                Section(header: Text(section.letter).font(.headline)) {
                    ForEach(section.contacts) { contact in
                        ContactRow(contact: contact)
                    }
                }
            }
        }
    }

    private var searchResults: [ContactSection] {
        guard !viewModel.searchQuery.isEmpty else {
            return viewModel.sections
        }
        let lower = viewModel.searchQuery.lowercased()
        let filtered = viewModel.contacts.filter {
            $0.displayName.lowercased().contains(lower) ||
            $0.userId.lowercased().contains(lower)
        }
        return [ContactSection(id: "search", letter: "搜索结果", contacts: filtered)]
    }
}

// MARK: - ContactRow

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: contact.avatarUrl, name: contact.displayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    if contact.isOnline {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                }
                if let bio = contact.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}