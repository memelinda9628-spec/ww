import Foundation
import SwiftUI

// MARK: - RoomDirectoryViewModel
/// 房间目录 ViewModel，对应 RoomDirectoryService。
/// 管理房间目录搜索、分页、加入操作。

@MainActor
final class RoomDirectoryViewModel: ObservableObject {
    @Published var searchTerm: String = ""
    @Published var rooms: [RoomDescription] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var isAtLastPage: Bool = false
    @Published var loadedPages: Int = 0
    @Published var selectedHomeserver: String?
    @Published var onlyPublic: Bool = true
    @Published var errorMessage: String?
    @Published var joinInProgress: Set<String> = []
    @Published var joinedRooms: Set<String> = []

    private let service = RoomDirectoryService.shared

    // MARK: - 搜索

    func performSearch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let filter = RoomDirectorySearchFilter(
            searchTerm: searchTerm.isEmpty ? nil : searchTerm,
            onlyPublic: onlyPublic,
            homeserver: selectedHomeserver
        )

        do {
            let results = try await service.search(filter: filter)
            rooms = results
            loadedPages = 1
            isAtLastPage = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 加载下一页
    func loadNextPage() async {
        guard !isAtLastPage, !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let newResults = try await service.nextPage()
            rooms.append(contentsOf: newResults)
            loadedPages = service.loadedPages
            isAtLastPage = service.isAtLastPage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 当列表滚动到底部时触发
    func onAppearLastItem(_ room: RoomDescription) async {
        guard let lastRoom = rooms.last, lastRoom.id == room.id else { return }
        await loadNextPage()
    }

    // MARK: - 加入房间

    /// 加入/敲门进入房间
    func joinRoom(_ room: RoomDescription) async {
        joinInProgress.insert(room.id)
        defer { joinInProgress.remove(room.id) }

        do {
            try await Task.sleep(nanoseconds: 800_000_000)
            joinedRooms.insert(room.id)
        } catch {
            errorMessage = "加入失败: \(error.localizedDescription)"
        }
    }

    /// 是否已加入该房间
    func isJoined(_ room: RoomDescription) -> Bool {
        joinedRooms.contains(room.id)
    }

    /// 是否正在加入
    func isJoining(_ room: RoomDescription) -> Bool {
        joinInProgress.contains(room.id)
    }

    // MARK: - 状态

    func reset() {
        rooms = []
        searchTerm = ""
        isAtLastPage = false
        loadedPages = 0
        errorMessage = nil
    }

    /// 可用的 Homeserver 列表
    let availableHomeservers = [
        (nil as String?, "所有服务器"),
        ("matrix.org", "matrix.org"),
        ("example.com", "example.com"),
    ]
}