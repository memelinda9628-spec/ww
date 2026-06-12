import Foundation
import SwiftUI

// MARK: - RoomSettingsViewModel
/// 房间设置 ViewModel，管理单个房间的设置状态（加入规则、显示名、头像等）
/// 对应 Service: RoomSettingsService

@MainActor
final class RoomSettingsViewModel: ObservableObject {

    // MARK: - Published 状态

    @Published var roomId: String
    @Published var isPublic: Bool = true
    @Published var joinRule: JoinRule = .public
    @Published var ownDisplayName: String? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    // MARK: - 加入规则选项（用于 UI Picker）

    let joinRuleOptions: [JoinRule] = [
        .public,
        .invite,
        .knock,
    ]

    // MARK: - 初始化

    init(roomId: String) {
        self.roomId = roomId
    }

    // MARK: - 加载当前设置

    /// 加载房间当前加入规则
    func loadJoinRule() async {
        isLoading = true
        errorMessage = nil
        do {
            let service = RoomSettingsService.shared
            // 通过 RoomInfo 读取当前 joinRule（无需额外 FFI 调用）
            guard let client = KeychainManager.shared.ffiClient,
                  let room = try client.getRoom(roomId: roomId) else {
                throw SocialFeedError.roomNotFound("房间不存在: \(roomId)")
            }
            let info = try await room.roomInfo()
            if let rule = info.joinRule {
                joinRule = rule
                isPublic = (rule == .public)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 加载当前用户在房间内的显示名（房间昵称）
    func loadOwnDisplayName() async {
        do {
            let service = RoomSettingsService.shared
            ownDisplayName = try await service.getOwnMemberDisplayName(roomId: roomId)
        } catch {
            ownDisplayName = nil
        }
    }

    // MARK: - 更新操作

    /// 更新房间加入规则
    func updateJoinRule(_ newRule: JoinRule) async {
        isLoading = true
        errorMessage = nil
        do {
            let service = RoomSettingsService.shared
            try await service.setJoinRule(roomId: roomId, newRule: newRule)
            joinRule = newRule
            isPublic = (newRule == .public)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 更新当前用户在房间内的显示名
    func updateOwnDisplayName(_ newName: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            let service = RoomSettingsService.shared
            try await service.setOwnMemberDisplayName(roomId: roomId, displayName: newName)
            ownDisplayName = newName
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 更新房间头像
    func updateRoomAvatar(data: Data, mimeType: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let service = RoomSettingsService.shared
            try await service.setRoomAvatar(roomId: roomId, data: data, mimeType: mimeType)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
