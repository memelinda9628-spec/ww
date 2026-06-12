import SwiftUI

@MainActor
@Observable
final class DiscoverViewModel {
    private let service = SocialFeedService.shared

    var keyword = ""
    var showFilterSheet = false
    var sortOrder: SortOrder = .timeDesc

    // Full-text search via search index
    var fullTextMode = false
    var fullTextResults: [String] = []

    // Advanced filter
    var authorId: String?
    var minLikes: UInt64?
    var minComments: UInt64?
    var hasImagesOnly = false

    var results: [Moment] {
        if fullTextMode && !keyword.isEmpty {
            let matchingIds = service.fullTextSearch(query: keyword)
            return moments.filter { matchingIds.contains($0.id) }
        }
        return moments
    }

    var sortedResults: [Moment] {
        sortOrder.apply(results)
    }

    private var moments: [Moment] {
        var filter = SearchFilter()
        filter.keyword = fullTextMode ? nil : (keyword.isEmpty ? nil : keyword)
        filter.authorId = authorId
        filter.minLikes = minLikes
        filter.minComments = minComments
        filter.hasImages = hasImagesOnly
        return service.searchMoments(filter: filter)
    }

    func toggleFullText() {
        fullTextMode.toggle()
        if !fullTextMode { fullTextResults = [] }
    }

    func resetFilters() {
        authorId = nil
        minLikes = nil
        minComments = nil
        hasImagesOnly = false
    }
}