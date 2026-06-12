import SwiftUI

@MainActor
@Observable
final class FeedViewModel {
    private let service = SocialFeedService.shared

    var moments: [Moment] { service.moments }
    var isLoading: Bool { service.isLoading }
    var hasMorePages = true
    var showPostSheet = false
    var showCommentSheet = false
    var showForwardSheet = false
    var selectedMoment: Moment?

    func fetchTimeline() async { await service.fetchTimeline(); resetPagination() }
    func refreshTimeline() async { await service.refreshTimeline(); resetPagination() }

    func loadNextPage() async {
        guard !isLoading, hasMorePages else { return }
        if let result = await service.loadNextPage() {
            moments.append(contentsOf: result.items)
            hasMorePages = result.hasMore
        }
    }

    func toggleLike(_ moment: Moment) { service.toggleLike(momentId: moment.id) }

    func postMoment(text: String, imageURLs: [URL]) async {
        await service.postMoment(text: text, imageURLs: imageURLs)
    }

    func comment(text: String) async {
        guard let moment = selectedMoment else { return }
        await service.comment(momentId: moment.id, text: text)
    }

    func forward(quoteText: String) async {
        guard let moment = selectedMoment else { return }
        await service.forward(moment: moment, quoteText: quoteText)
    }

    func commentButtonTapped(_ moment: Moment) {
        selectedMoment = moment; showCommentSheet = true
    }

    func forwardButtonTapped(_ moment: Moment) {
        selectedMoment = moment; showForwardSheet = true
    }

    private func resetPagination() {
        service.resetPagination()
        hasMorePages = true
    }
}