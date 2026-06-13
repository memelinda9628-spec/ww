//
//  StorageSettingsService.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: Encapsulates StorageSettings-related
//    UniFFI calls into typed async throws Swift methods.

import Foundation
import Combine

// MARK: - StorageSettingsService

/// Wraps matrix-rust-sdk UniFFI bindings for StorageSettings operations.
/// All methods are async throws and access the FFI Client via KeychainManager.

@MainActor
final class StorageSettingsService: ObservableObject {
    static let shared = StorageSettingsService()

    private init() {}


    // MARK: - Cache Management

    /// 清空所有非关键缓存
    func clearCaches() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.clearCaches()
    }

    /// 获取各 Store 占用大小
    func getStoreSizes() async throws -> StoreSizes {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getStoreSizes()
    }

    /// 优化数据库（VACUUM）
    func optimizeStores() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.optimizeStores()
    }

    /// 设置媒体留存策略
    func setMediaRetentionPolicy(maxAgeDays: UInt32) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        let policy = MediaRetentionPolicy(maxAge: maxAgeDays)
        try await client.setMediaRetentionPolicy(policy: policy)
    }

    // MARK: - Media Display Settings

    /// 设置媒体预览展示策略
    func setMediaPreviewDisplayPolicy(_ policy: MediaPreviewDisplayPolicy) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setMediaPreviewDisplayPolicy(policy: policy)
    }

    /// 获取媒体预览展示策略
    func getMediaPreviewDisplayPolicy() async throws -> MediaPreviewDisplayPolicy {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getMediaPreviewDisplayPolicy()
    }

    /// 设置邀请头像展示策略
    func setInviteAvatarsDisplayPolicy(_ policy: InviteAvatarsDisplayPolicy) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.setInviteAvatarsDisplayPolicy(policy: policy)
    }

    /// 获取邀请头像展示策略
    func getInviteAvatarsDisplayPolicy() async throws -> InviteAvatarsDisplayPolicy {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getInviteAvatarsDisplayPolicy()
    }

    /// 获取服务端最大上传大小
    func getMaxMediaUploadSize() async throws -> UInt64 {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        return try await client.getMaxMediaUploadSize()
    }

    /// 拉取服务端媒体预览配置
    func fetchMediaPreviewConfig() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.fetchMediaPreviewConfig()
    }

    // MARK: - Helpers

    static var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

}
