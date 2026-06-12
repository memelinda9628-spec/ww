import Foundation
import SwiftUI

// MARK: - Contact
/// 联系人数据模型

struct Contact: Identifiable, Sendable {
    let id: String
    let userId: String
    let displayName: String
    let avatarUrl: URL?
    let bio: String?
    let isOnline: Bool
    let lastSeen: Date?
    let isFriend: Bool
    let isBlocked: Bool
    let roomId: String?

    var firstLetter: String {
        String(displayName.prefix(1)).uppercased()
    }
}

// MARK: - ContactSection
/// 按首字母分组的联系人节

struct ContactSection: Identifiable {
    let id: String
    let letter: String
    let contacts: [Contact]
}

// MARK: - ContactsViewModel
/// 联系人列表 ViewModel，对应 FriendService。
/// 管理联系人加载、分组、搜索、好友操作。

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var sections: [ContactSection] = []
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedContact: Contact?
    @Published var showAddFriend: Bool = false
    @Published var pendingRequestsCount: Int = 3

    // MARK: - 加载

    func loadContacts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        try? await Task.sleep(nanoseconds: 300_000_000)
        contacts = mockContacts
        applyGrouping()
    }

    func refresh() async {
        await loadContacts()
    }

    // MARK: - 搜索

    func search(query: String) {
        searchQuery = query
        isSearching = !query.isEmpty
        applyGrouping()
    }

    func clearSearch() {
        searchQuery = ""
        isSearching = false
        applyGrouping()
    }

    // MARK: - 分组

    private func applyGrouping() {
        let filtered = filteredContacts
        let grouped = Dictionary(grouping: filtered) { $0.firstLetter }
        let sortedLetters = grouped.keys.sorted { $0 < $1 }

        sections = sortedLetters.map { letter in
            ContactSection(
                id: letter,
                letter: letter,
                contacts: grouped[letter]?.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } ?? []
            )
        }
    }

    private var filteredContacts: [Contact] {
        if searchQuery.isEmpty { return contacts }
        let lower = searchQuery.lowercased()
        return contacts.filter {
            $0.displayName.lowercased().contains(lower) ||
            $0.userId.lowercased().contains(lower)
        }
    }

    // MARK: - 操作

    func deleteContact(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        applyGrouping()
    }

    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    func blockContact(_ contact: Contact) {
        Task {
            try? await ffiClient?.ignoreUser(userId: contact.userId)
        }
    }

    func startChat(with contact: Contact) {
        selectedContact = contact
    }

    // MARK: - Mock

    private let mockContacts: [Contact] = [
        Contact(id: "1", userId: "@alice:example.com", displayName: "Alice", avatarUrl: nil, bio: "iOS 开发", isOnline: true, lastSeen: nil, isFriend: true, isBlocked: false, roomId: "!roomA:example.com"),
        Contact(id: "2", userId: "@bob:example.com", displayName: "Bob", avatarUrl: nil, bio: "后端工程师", isOnline: false, lastSeen: Date().addingTimeInterval(-3600), isFriend: true, isBlocked: false, roomId: "!roomB:example.com"),
        Contact(id: "3", userId: "@charlie:example.com", displayName: "Charlie", avatarUrl: nil, bio: nil, isOnline: true, lastSeen: nil, isFriend: true, isBlocked: false, roomId: "!roomC:example.com"),
        Contact(id: "4", userId: "@david:example.com", displayName: "David", avatarUrl: nil, bio: "设计师", isOnline: false, lastSeen: Date().addingTimeInterval(-86400), isFriend: true, isBlocked: true, roomId: nil),
        Contact(id: "5", userId: "@eve:example.com", displayName: "Eve", avatarUrl: nil, bio: "产品经理", isOnline: true, lastSeen: nil, isFriend: true, isBlocked: false, roomId: "!roomE:example.com"),
        Contact(id: "6", userId: "@frank:example.com", displayName: "Frank", avatarUrl: nil, bio: nil, isOnline: false, lastSeen: Date().addingTimeInterval(-7200), isFriend: true, isBlocked: false, roomId: "!roomF:example.com"),
        Contact(id: "7", userId: "@grace:example.com", displayName: "Grace", avatarUrl: nil, bio: "前端开发", isOnline: true, lastSeen: nil, isFriend: true, isBlocked: false, roomId: "!roomG:example.com"),
        Contact(id: "8", userId: "@henry:example.com", displayName: "Henry", avatarUrl: nil, bio: nil, isOnline: false, lastSeen: Date().addingTimeInterval(-300), isFriend: true, isBlocked: false, roomId: "!roomH:example.com"),
    ]
}