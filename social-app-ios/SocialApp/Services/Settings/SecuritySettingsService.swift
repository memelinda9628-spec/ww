//
//  SecuritySettingsService.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: Encapsulates SecuritySettings-related
//    UniFFI calls into typed async throws Swift methods.

import Foundation
import Combine

// MARK: - SecuritySettingsService

/// Wraps matrix-rust-sdk UniFFI bindings for SecuritySettings operations.
/// All methods are async throws and access the FFI Client via KeychainManager.

@MainActor
final class SecuritySettingsService: ObservableObject {
    static let shared = SecuritySettingsService()

    private init() {}


    // MARK: - Key Management

    /// 获取 ed25519 设备指纹公钥
    func getEd25519Key() async throws -> String {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return try await encryption.ed25519Key()
    }

    /// 获取 curve25519 设备密钥
    func getCurve25519Key() async throws -> String {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return try await encryption.curve25519Key()
    }

    /// 获取当前验证状态
    func getVerificationState() async throws -> VerificationStateInfo {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return encryption.verificationState()
    }

    /// 监听验证状态变更
    func subscribeVerificationState(onUpdate: @escaping (VerificationStateInfo) -> Void) -> TaskHandle? {
        guard let client = Self.ffiClient else { return nil }
        guard let encryption = client.encryption() else { return nil }
        return encryption.verificationStateListener(listener: VerificationStateListenerImpl(onUpdate: onUpdate))
    }

    /// 等待 E2EE 初始化完成
    func waitForE2EEInit() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.waitForE2eeInitializationTasks()
    }

    // MARK: - Backup

    /// 获取备份状态
    func getBackupState() async throws -> BackupStateInfo {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return encryption.backupState()
    }

    /// 检查服务端是否有备份
    func backupExistsOnServer() async throws -> Bool {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return try await encryption.backupExistsOnServer()
    }

    /// 启用密钥备份
    func enableBackups() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.enableBackups()
    }

    /// 等待备份上传完成
    func waitForBackupUpload(onUpdate: @escaping (BackupUploadStateInfo) -> Void) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.waitForBackupUploadSteadyState(listener: BackupSteadyStateListenerImpl(onUpdate: onUpdate))
    }

    // MARK: - Recovery

    /// 获取恢复状态
    func getRecoveryState() async throws -> RecoveryStateInfo {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return encryption.recoveryState()
    }

    /// 启用密钥恢复
    func enableRecovery(recoveryKey: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.enableRecovery(key: recoveryKey)
    }

    /// 禁用恢复
    func disableRecovery() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.disableRecovery()
    }

    /// 重置恢复密钥
    func resetRecoveryKey() async throws -> String {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return try await encryption.resetRecoveryKey()
    }

    /// 用恢复密钥恢复
    func recover(recoveryKey: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.recover(recoveryKey: recoveryKey)
    }

    /// 恢复并修复备份
    func recoverAndFixBackup(recoveryKey: String) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.recoverAndFixBackup(recoveryKey: recoveryKey)
    }

    /// 重置身份（交叉签名密钥）
    func resetIdentity() async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.resetIdentity()
    }

    // MARK: - Import/Export

    /// 导入加密凭据包
    func importSecretsBundle(_ bundle: SecretsBundleWithUserId) async throws {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        try await encryption.importSecretsBundle(bundle)
    }

    // MARK: - Device Verification

    /// 检查是否为最后一个设备
    func isLastDevice() async throws -> Bool {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return encryption.isLastDevice()
    }

    /// 获取用户身份
    func getUserIdentity(userId: String) async throws -> UserIdentityInfo {
        guard let client = Self.ffiClient else { throw SocialFeedError.clientNotInitialized }
        guard let encryption = client.encryption() else { throw SocialFeedError.encryptionNotAvailable }
        return try await encryption.userIdentity(userId: userId)
    }

    /// 获取会话验证控制器
    func getSessionVerificationController() -> SessionVerificationController? {
        guard let client = Self.ffiClient else { return nil }
        return client.sessionVerificationController()
    }

    // MARK: - Helpers

    static var ffiClient: Client? {
        KeychainManager.shared.ffiClient
    }

}
