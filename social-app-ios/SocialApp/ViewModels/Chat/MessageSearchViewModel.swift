import Foundation
import SwiftUI

// MARK: - MessageSearchViewModel
/// 消息搜索 ViewModel，对应 MessageSearchService。
/// 管理全局/单房间搜索状态、搜索历史、结果展示。

@MainActor
final class MessageSearchViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: MessageSearchResult?
    @Published var roomSearchResult: RoomSearchResult?
    @Published var isSearching: Bool = false
    @Published var searchFilter: MessageSearchFilter = .all
    @Published var searchHistory: [String] = []
    @Published var selectedRoomId: String?
    @Published var errorMessage: String?

    private let service = MessageSearchService.shared
    private let maxHistoryCount = 20

    // MARK: - 全局搜索

    func performGlobalSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let result = try await service.searchMessages(
                query: query,
                filter: searchFilter,
                pagination: SearchPagination(limit: 50)
            )
            searchResults = result
            addToHistory(query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 在选定房间内搜索
    func performRoomSearch(roomId: String) async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            roomSearchResult = nil
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let result = try await service.searchRoomMessages(
                roomId: roomId,
                query: query,
                pagination: SearchPagination(limit: 50)
            )
            roomSearchResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 过滤

    func setFilter(_ filter: MessageSearchFilter) {
        searchFilter = filter
        if !searchQuery.isEmpty {
            Task { await performGlobalSearch() }
        }
    }

    // MARK: - 历史

    func addToHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        searchHistory.insert(query, at: 0)
        if searchHistory.count > maxHistoryCount {
            searchHistory = Array(searchHistory.prefix(maxHistoryCount))
        }
    }

    func clearHistory() {
        searchHistory.removeAll()
    }

    func removeFromHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
    }

    /// 从历史中选择并重新搜索
    func searchFromHistory(_ query: String) {
        searchQuery = query
        Task { await performGlobalSearch() }
    }

    // MARK: - 状态

    func clearResults() {
        searchResults = nil
        roomSearchResult = nil
        errorMessage = nil
    }

    func reset() {
        searchQuery = ""
        searchResults = nil
        roomSearchResult = nil
        selectedRoomId = nil
        errorMessage = nil
        searchFilter = .all
    }
}