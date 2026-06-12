import Foundation
import SwiftUI

// MARK: - ReactionItemViewModel
/// 单个 reaction 的可视化数据模型

struct ReactionItemViewModel: Identifiable {
    let id: String
    let key: String
    let count: Int
    let isToggledByMe: Bool
    let senders: [String]

    var displayLabel: String { "\(key) \(count)" }
}

// MARK: - ReactionViewModel
/// Reaction（表情回应）ViewModel，对应 ReactionService。
/// 管理：事件 reaction 列表、添加/移除操作、聚合展示。

@MainActor
final class ReactionViewModel: ObservableObject {
    @Published var eventId: String = ""
    @Published var roomId: String = ""
    @Published var reactions: [ReactionItemViewModel] = []
    @Published var totalReactions: Int = 0
    @Published var myActiveKey: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let service = ReactionService.shared

    // MARK: - 初始化

    func configure(eventId: String, roomId: String) {
        self.eventId = eventId
        self.roomId = roomId
        loadReactions()
    }

    // MARK: - 加载

    func loadReactions() {
        guard let event = service.getReactions(for: eventId) else {
            reactions = []
            totalReactions = 0
            myActiveKey = nil
            return
        }
        apply(event)
    }

    /// 切换到指定 reaction — 添加或移除
    func toggleReaction(key: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let event = try await service.toggleReaction(eventId: eventId, key: key, roomId: roomId)
            apply(event)
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 查询

    func reaction(for key: String) -> Reaction? {
        service.getReaction(eventId: eventId, key: key)
    }

    // MARK: - Private

    private func apply(_ event: ReactionEvent) {
        reactions = event.sortedReactions.map { r in
            ReactionItemViewModel(
                id: r.key,
                key: r.key,
                count: r.count,
                isToggledByMe: r.isToggledByMe,
                senders: r.recentSenders.map { $0.senderName }
            )
        }
        totalReactions = event.totalReactions
        myActiveKey = event.myActiveReactionKey
    }
}