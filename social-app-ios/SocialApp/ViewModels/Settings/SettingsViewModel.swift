import Foundation
import SwiftUI

// MARK: - SettingsViewModel
/// 设置与偏好 ViewModel，管理所有可配置的用户偏好项

@MainActor
final class SettingsViewModel: ObservableObject {
    /// FFI Client
    private var ffiClient: Client? { KeychainManager.shared.ffiClient }

    // MARK: 通用设置
    @AppStorage("notifications_enabled") var notificationsEnabled = true
    @AppStorage("dark_mode") var darkMode: String = "auto"
    @AppStorage("language") var language: String = "zh-Hans"

    // MARK: 隐私
    @AppStorage("show_online_status") var showOnlineStatus = true
    @AppStorage("read_receipts") var readReceipts = true
    @AppStorage("typing_indicators") var typingIndicators = true
    @AppStorage("allow_search_by_phone") var allowSearchByPhone = false
    @AppStorage("allow_search_by_email") var allowSearchByEmail = true

    // MARK: 安全
    @Published var isChangingPassword = false
    @Published var passwordChangeMessage: String?
    @Published var isSettingPIN = false
    @Published var pinEnabled: Bool { UserDefaults.standard.bool(forKey: "pin_enabled") }

    // MARK: 存储
    @Published var cacheSize: String = "计算中..."
    @Published var isClearingCache = false

    // MARK: 账户
    @Published var matrixUserId: String = "@me:example.com"
    @Published var displayName: String = "小明"

    // MARK: 关于
    let appVersion = "1.0.0"
    let buildNumber = "1"
    let sdkVersion = "matrix-rust-sdk 0.9.0"

    // MARK: 选项

    let darkModeOptions = [
        ("auto", "跟随系统"),
        ("light", "浅色"),
        ("dark", "深色"),
    ]

    let languageOptions = [
        ("zh-Hans", "简体中文"),
        ("en", "English"),
    ]

    // MARK: - 操作

    func clearCache() async {
        isClearingCache = true
        defer { isClearingCache = false }
        do {
            try await StorageSettingsService.shared.clearCaches()
            cacheSize = "0 B"
        } catch {
            cacheSize = "清理失败"
        }
    }

    func calculateCacheSize() {
        Task {
            do {
                let sizes = try await StorageSettingsService.shared.getStoreSizes()
                let total: UInt64 = (sizes.cryptoStore ?? 0)
                    + (sizes.stateStore ?? 0)
                    + (sizes.eventCacheStore ?? 0)
                    + (sizes.mediaStore ?? 0)
                cacheSize = formatBytes(total)
            } catch {
                cacheSize = "计算失败"
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        isChangingPassword = true
        defer { isChangingPassword = false }

        guard !oldPassword.isEmpty, !newPassword.isEmpty else {
            throw SocialFeedError.invalidContent("密码不能为空")
        }
        guard newPassword.count >= 8 else {
            throw SocialFeedError.invalidContent("密码长度至少8位")
        }

        guard let client = ffiClient else {
            throw SocialFeedError.clientNotInitialized
        }

        do {
            // 首次尝试：不带 authData，服务端可能在 session 仍然有效时直接接受
            try await client.changePassword(newPassword: newPassword, authData: nil)
        } catch {
            // 服务端要求 UIAA 二次认证，用旧密码构造 AuthData 重试
            guard let userId = try? KeychainManager.shared.readString(for: .userId) else {
                throw SocialFeedError.unknown("无法获取用户标识")
            }
            let authData = AuthData.password(passwordDetails: AuthDataPasswordDetails(
                identifier: userId,
                password: oldPassword
            ))
            try await client.changePassword(newPassword: newPassword, authData: authData)
        }
        passwordChangeMessage = "密码已更新"
    }

    func setPIN(_ pin: String) {
        UserDefaults.standard.set(!pin.isEmpty, forKey: "pin_enabled")
    }

    func logout() async {
        guard let client = ffiClient else { return }
        try? await client.logout()
    }

    func deactivateAccount() async throws {
        guard let client = ffiClient else { throw SocialFeedError.clientNotInitialized }
        try await client.deactivateAccount(authData: nil, eraseData: false)
    }

    func exportData() async throws -> URL {
        // TODO: 导出用户数据
        throw SocialFeedError.internalError("未实现")
    }

    func checkForUpdates() {
        // TODO: 接入应用更新逻辑
    }

    func reportProblem() {
        // TODO: 打开问题反馈
    }
}