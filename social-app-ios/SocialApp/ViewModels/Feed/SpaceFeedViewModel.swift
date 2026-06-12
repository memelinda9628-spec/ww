import Foundation

// MARK: - SpaceFeedViewModel
/// Space 动态流 ViewModel

@MainActor
final class SpaceFeedViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    @Published var isLoading = false

    func loadSpaceFeed(spaceId: String) async {
        isLoading = true
        defer { isLoading = false }
        // TODO: 接入 Rust space.moments() API
        try? await Task.sleep(nanoseconds: 500_000_000)
        moments = SocialFeedService.shared.searchMoments()
    }
}
