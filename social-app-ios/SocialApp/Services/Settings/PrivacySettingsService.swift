//
//  PrivacySettingsService.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: Encapsulates PrivacySettings-related
//    UniFFI calls into typed async throws Swift methods.

import Foundation
import Combine

// MARK: - PrivacySettingsService

/// Wraps matrix-rust-sdk UniFFI bindings for PrivacySettings operations.
/// All methods are async throws and access the FFI Client via KeychainManager.

@MainActor
final class PrivacySettingsService: ObservableObject {
    static let shared = PrivacySettingsService()

    private init() {}


    // MARK: - Ignored Users

    /// 获取被忽略用户列表
    func getIgnoredUsers() async throws -> [String] {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        return try await client.ignoredUsers()
    }

    /// 忽略指定用户
    func ignoreUser(userId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        try await client.ignoreUser(userId: userId)
    }

    /// 取消忽略指定用户
    func unignoreUser(userId: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        try await client.unignoreUser(userId: userId)
    }

    /// 订阅忽略列表变更
    func subscribeIgnoredUsers(onUpdate: @escaping ([String]) -> Void) -> TaskHandle? {
        guard let client = Self.ffiClient else { return nil }
        return client.subscribeToIgnoredUsers(listener: IgnoredUsersListenerImpl(onUpdate: onUpdate))
    }

    /// 设置离开房间时是否遗忘
    func setForgetRoomWhenLeaving(_ forget: Bool) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        try await client.forgetRoomWhenLeaving(forget: forget)
    }

    /// 获取离开时遗忘设置
    func getForgetRoomWhenLeaving() async throws -> Bool {
        guard let client = Self.ffiClient else { throw SocialFeedError.notInitialized }
        return client.forgetsRoomWhenLeaving()
    }

    // MARK: - Helpers

    static var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

}
