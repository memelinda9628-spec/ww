import Foundation

struct UserProfile: Identifiable, Sendable {
    let id: String
    let userId: String
    let displayName: String
    let avatarUrl: URL?
    let bio: String?
    let location: String?
    let feedRoomId: String?
    let followerCount: UInt64
    let followingCount: UInt64
    let momentsCount: UInt64
}