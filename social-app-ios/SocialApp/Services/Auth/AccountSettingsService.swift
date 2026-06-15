//
//  AccountSettingsService.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: Encapsulates AccountSettings-related
//    UniFFI calls into typed async throws Swift methods.

import Foundation
import Combine

// MARK: - AccountSettingsService

/// Wraps matrix-rust-sdk UniFFI bindings for AccountSettings operations.
/// All methods are async throws and access the FFI Client via KeychainManager.

@MainActor
final class AccountSettingsService: ObservableObject {
    static let shared = AccountSettingsService()

    private init() {}


    // MARK: - Profile

    /// 设置显示名称
    func setDisplayName(_ name: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setDisplayName(name: name)
        // 资料已修改，使本地缓存失效，下次读取时重新拉取最新值
        if let userId = Self.currentUserId {
            AppContainer.shared.profileCache.invalidate(userId: userId)
        }
    }

    /// 获取显示名称（优先读 ProfileCache 当前用户资料）
    func getDisplayName() async throws -> String {
        if let userId = Self.currentUserId,
           let cached = AppContainer.shared.profileCache.get(userId: userId) {
            return cached.displayName
        }
        guard let userId = Self.currentUserId else { throw SocialFeedError.clientNotInitialized }
        let profile = try await getProfile(userId: userId)
        return profile.displayName
    }

    /// 上传头像并返回 MXC URI
    func uploadAvatar(mimeType: String, data: Data) async throws -> String {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.uploadAvatar(mimeType: mimeType, data: [UInt8](data))
    }

    /// 设置头像 URL
    func setAvatarUrl(_ url: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setAvatarUrl(url: url)
        // 资料已修改，使本地缓存失效
        if let userId = Self.currentUserId {
            AppContainer.shared.profileCache.invalidate(userId: userId)
        }
    }

    /// 移除头像
    func removeAvatar() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.removeAvatar()
        // 资料已修改，使本地缓存失效
        if let userId = Self.currentUserId {
            AppContainer.shared.profileCache.invalidate(userId: userId)
        }
    }

    /// 获取当前头像 URL（优先读 ProfileCache 当前用户资料）
    func getAvatarUrl() async throws -> String {
        if let userId = Self.currentUserId,
           let cached = AppContainer.shared.profileCache.get(userId: userId) {
            return cached.avatarUrl?.absoluteString ?? ""
        }
        guard let userId = Self.currentUserId else { throw SocialFeedError.clientNotInitialized }
        let profile = try await getProfile(userId: userId)
        return profile.avatarUrl?.absoluteString ?? ""
    }

    /// 获取指定用户资料（先读缓存，未命中再 FFI）
    func getProfile(userId: String) async throws -> UserProfile {
        if let cached = AppContainer.shared.profileCache.get(userId: userId) {
            return cached
        }
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        let ffiProfile = try await client.getProfile(userId: userId)
        let profile = ffiProfile
        AppContainer.shared.profileCache.set(userId: userId, profile: profile)
        return profile
    }

    // MARK: - Account

    /// 修改密码（首次调用 authData 传 nil，如遇 UIAA 则回传 AuthData）
    func changePassword(newPassword: String, authData: [String: Any]? = nil) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.changePassword(newPassword: newPassword, authData: authData)
    }

    /// 获取绑定的第三方 ID（邮箱/手机）
    func getThirdPartyIds() async throws -> [ThirdPartyId] {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.get3pids()
    }

    /// 请求邮箱验证令牌
    func requestEmailToken(email: String, clientSecret: String, sendAttempt: UInt32) async throws -> String {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.request3pidEmailToken(email: email, clientSecret: clientSecret, sendAttempt: sendAttempt)
    }

    /// 请求手机验证令牌
    func requestPhoneToken(phone: String, clientSecret: String, sendAttempt: UInt32) async throws -> String {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.request3pidMsisdnToken(phone: phone, clientSecret: clientSecret, sendAttempt: sendAttempt)
    }

    /// 绑定第三方 ID
    func addThirdPartyId(sid: String, clientSecret: String, authData: [String: Any]? = nil) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.add3pid(sid: sid, clientSecret: clientSecret, authData: authData)
    }

    /// 解绑第三方 ID
    func deleteThirdPartyId(address: String, medium: String, idServer: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.delete3pid(address: address, medium: medium, idServer: idServer)
    }

    /// 登出当前会话
    func logout() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.logout()
    }

    /// 注销账户
    func deactivateAccount(authData: [String: Any]? = nil, erase: Bool = false) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.deactivateAccount(auth: authData, erase: erase)
    }

    /// 获取 Homeserver 能力信息
    func getHomeserverCapabilities() async throws -> HomeserverCapabilities {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.homeserverCapabilities()
    }

    // MARK: - Helpers

    /// 当前登录用户的 Matrix ID（从 Keychain 读取）
    static var currentUserId: String? {
        KeychainManager.shared.sessionUserId
    }

    static var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

}
