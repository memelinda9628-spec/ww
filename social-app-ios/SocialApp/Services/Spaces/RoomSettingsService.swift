import Foundation

// MARK: - RoomSettingsService
/// 房间设置服务，封装房间级设置操作（显示名、头像等）
/// 对应 Rust FFI: Room.setOwnMemberDisplayName(displayName:)
/// 每次修改后使 ProfileCache 中对应房间缓存失效，确保 UI 拉到最新值。

@MainActor
final class RoomSettingsService: ObservableObject {
    static let shared = RoomSettingsService()

    private init() {}

    // MARK: - Helpers

    /// 获取 FFI Client（通过 KeychainManager）
    private var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

    /// 通过 roomId 获取 FFI Room 对象（getRoom 为同步 throws，返回 Room?）
    private func ffiRoom(roomId: String) throws -> Room {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let room = try client.getRoom(roomId: roomId) else {
            throw SocialFeedError.roomNotFound("Room not found: \(roomId)")
        }
        return room
    }

    // MARK: - Display Name

    /// 设置当前用户在指定房间内的显示名（房间昵称）
    /// FFI: Room.setOwnMemberDisplayName(displayName: String?) async throws
    /// 成功后使本地房间缓存失效，下次读取时重新拉取最新值。
    func setOwnMemberDisplayName(roomId: String, displayName: String?) async throws {
        let room = try ffiRoom(roomId: roomId)
        try await room.setOwnMemberDisplayName(displayName: displayName)
        // 资料已修改，使本地房间缓存失效
        AppContainer.shared.profileCache.invalidateRoom(roomId: roomId)
    }

    /// 获取当前用户在指定房间内的显示名
    /// 优先读 ProfileCache，未命中再调 FFI，并回写缓存
    func getOwnMemberDisplayName(roomId: String) async throws -> String? {
        // 先查缓存（ProfileCache.getRoom 返回 RoomProfile，含 displayName）
        if let cached = AppContainer.shared.profileCache.getRoom(roomId: roomId) {
            return cached.displayName.isEmpty ? nil : cached.displayName
        }
        let room = try ffiRoom(roomId: roomId)
        let name = try await room.memberDisplayName()
        // 回写缓存
        let profile = ProfileCache.RoomProfile(
            roomId: roomId,
            displayName: name ?? "",
            avatarUrl: nil
        )
        AppContainer.shared.profileCache.setRoom(roomId: roomId, profile: profile)
        return name
    }

    // MARK: - Join Rule

    /// 设置房间的加入规则（谁可以加入房间）
    /// FFI: Room.updateJoinRules(newRule:) async throws
    /// 成功后使本地房间缓存失效，确保 UI 拉到最新值。
    /// - Parameters:
    ///   - roomId: 目标房间 ID
    ///   - newRule: 新的加入规则，类型为 FFI 生成的 `JoinRule`
    func setJoinRule(roomId: String, newRule: JoinRule) async throws {
        let room = try ffiRoom(roomId: roomId)
        try await room.updateJoinRules(newRule: newRule)
        // 规则已修改，使本地房间缓存失效
        AppContainer.shared.profileCache.invalidateRoom(roomId: roomId)
    }

    // MARK: - Avatar

    /// 上传并设置房间头像
    /// FFI: Room.uploadAvatar(mimeType:data:mediaInfo:) async throws -> Void
    /// SDK 内部处理上传并将头像 URL 写入房间状态，无需额外 setter。
    /// 成功后使本地房间缓存失效，下次读取时重新拉取最新值。
    /// - Parameters:
    ///   - roomId: 目标房间 ID
    ///   - data: 图片二进制数据
    ///   - mimeType: 图片 MIME 类型，如 "image/jpeg"、"image/png"
    func setRoomAvatar(roomId: String, data: Data, mimeType: String) async throws {
        let room = try ffiRoom(roomId: roomId)
        // mediaInfo 传 nil，由 SDK 自行推断图片信息
        try await room.uploadAvatar(mimeType: mimeType, data: data, mediaInfo: nil)
        // 头像已更新，使本地房间缓存失效
        AppContainer.shared.profileCache.invalidateRoom(roomId: roomId)
    }
}
