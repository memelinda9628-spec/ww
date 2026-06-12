import Foundation

// MARK: - Friend Model

struct Friend: Identifiable, Sendable, Hashable {
    let id: String
    let userId: String
    let displayName: String
    let avatarUrl: URL?
    let statusMessage: String?
    let isOnline: Bool
    let lastSeen: Date?

    var initial: String {
        String(displayName.prefix(1))
    }
}
