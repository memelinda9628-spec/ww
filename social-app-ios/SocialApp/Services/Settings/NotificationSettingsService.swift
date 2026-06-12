//
//  NotificationSettingsService.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: Encapsulates NotificationSettings-related
//    UniFFI calls into typed async throws Swift methods.

import Foundation
import Combine

// MARK: - NotificationSettingsService

/// Wraps matrix-rust-sdk UniFFI bindings for NotificationSettings operations.
/// All methods are async throws and access the FFI Client via KeychainManager.

@MainActor
final class NotificationSettingsService: ObservableObject {
    static let shared = NotificationSettingsService()

    private init() {}


    // MARK: - Room-Level Notification

    /// 获取房间通知设置
    func getRoomNotificationSettings(roomId: String) async throws -> RoomNotificationSettings {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getRoomNotificationSettings(roomId: roomId)
    }

    /// 设置房间通知模式
    func setRoomNotificationMode(roomId: String, mode: RoomNotificationMode) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setRoomNotificationMode(roomId: roomId, mode: mode)
    }

    /// 获取用户自定义通知模式
    func getUserDefinedRoomNotificationMode(roomId: String) async throws -> RoomNotificationMode? {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getUserDefinedRoomNotificationMode(roomId: roomId)
    }

    /// 获取默认房间通知模式
    func getDefaultRoomNotificationMode(isEncrypted: Bool, isOneToOne: Bool) async throws -> RoomNotificationMode {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getDefaultRoomNotificationMode(isEncrypted: isEncrypted, isOneToOne: isOneToOne)
    }

    /// 设置默认房间通知模式
    func setDefaultRoomNotificationMode(isEncrypted: Bool, isOneToOne: Bool, mode: RoomNotificationMode) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setDefaultRoomNotificationMode(isEncrypted: isEncrypted, isOneToOne: isOneToOne, mode: mode)
    }

    /// 恢复房间默认通知模式
    func restoreDefaultRoomNotificationMode(roomId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.restoreDefaultRoomNotificationMode(roomId: roomId)
    }

    /// 取消房间静音
    func unmuteRoom(roomId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.unmuteRoom(roomId: roomId)
    }

    /// 获取有自定义通知规则的房间
    func getRoomsWithUserDefinedRules(enabled: Bool) async throws -> [String] {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getRoomsWithUserDefinedRules(enabled: enabled)
    }

    // MARK: - Push Rule Toggles

    /// 是否启用房间 @提及通知
    func isRoomMentionEnabled() async throws -> Bool {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.isRoomMentionEnabled()
    }

    /// 开关房间 @提及通知
    func setRoomMentionEnabled(_ enabled: Bool) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setRoomMentionEnabled(enabled: enabled)
    }

    /// 是否启用用户 @提及通知
    func isUserMentionEnabled() async throws -> Bool {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.isUserMentionEnabled()
    }

    /// 开关用户 @提及通知
    func setUserMentionEnabled(_ enabled: Bool) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setUserMentionEnabled(enabled: enabled)
    }

    /// 是否启用通话通知
    func isCallEnabled() async throws -> Bool {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.isCallEnabled()
    }

    /// 开关通话通知
    func setCallEnabled(_ enabled: Bool) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setCallEnabled(enabled: enabled)
    }

    /// 是否启用邀请通知
    func isInviteForMeEnabled() async throws -> Bool {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.isInviteForMeEnabled()
    }

    /// 开关邀请通知
    func setInviteForMeEnabled(_ enabled: Bool) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setInviteForMeEnabled(enabled: enabled)
    }

    // MARK: - Pusher (APNs)

    /// 注册推送通道
    func setPusher(deviceToken: String, appId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        let identifiers = PusherIds(pushkey: deviceToken, appId: appId)
        try await client.setPusher(identifiers: identifiers, kind: .http, appDisplayName: "SocialApp", deviceDisplayName: UIDevice.current.name, lang: Locale.current.languageCode ?? "en", url: nil, data: nil, append: false)
    }

    /// 删除推送通道
    func deletePusher(deviceToken: String, appId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        let identifiers = PusherIds(pushkey: deviceToken, appId: appId)
        try await client.deletePusher(identifiers: identifiers)
    }

    /// 标记所有房间已读
    func markAllRoomsAsRead() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.markAllRoomsAsRead()
    }

    // MARK: - Helpers

    static var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

}
