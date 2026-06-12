import SwiftUI

@MainActor
@Observable
final class ProfileViewModel {
    private let service = SocialFeedService.shared

    var profile: UserProfile? { service.myProfile }
    var myMoments: [Moment] { service.searchMoments(filter: SearchFilter()) }
    var followingList: [String] { service.getFollowing() }
    var followingCount: Int { service.followingCount }

    var showEditProfile = false
    var showCreateProfile = false
    var showFollowList = false

    func fetchProfile() async { await service.fetchMyProfile() }

    func createProfile(name: String, avatarUri: String?, bio: String?, location: String?) async {
        await service.createProfile(displayName: name, avatarMxcUri: avatarUri, bio: bio, location: location)
    }

    func setAvatar(mxcUri: String) async { await service.setAvatar(mxcUri: mxcUri) }
    func updateBio(_ bio: String) async { await service.updateBio(bio) }
    func updateLocation(_ location: String) async { await service.updateLocation(location) }
    func updateDisplayName(_ name: String) async { await service.updateDisplayName(name) }

    func follow(userId: String, feedRoomId: String) async -> Bool {
        await service.follow(userId: userId, feedRoomId: feedRoomId)
    }

    func unfollow(feedRoomId: String) async {
        await service.unfollow(feedRoomId: feedRoomId)
    }

    func isFollowing(userId: String) -> Bool {
        service.isFollowing(userId: userId)
    }
}