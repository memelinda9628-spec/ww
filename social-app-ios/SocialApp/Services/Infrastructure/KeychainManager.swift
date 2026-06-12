import Foundation
import Security

// MARK: - KeychainError
/// Keychain 操作错误

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case accessDenied
    case encodeFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain 中未找到该项"
        case .duplicateItem:
            return "Keychain 中存在重复项"
        case .unexpectedStatus(let status):
            return "Keychain 操作失败: OSStatus \(status)"
        case .accessDenied:
            return "Keychain 访问被拒绝"
        case .encodeFailed:
            return "数据编码失败"
        case .decodeFailed:
            return "数据解码失败"
        }
    }
}

// MARK: - KeychainKey
/// 常用 Keychain 键定义

enum KeychainKey: String {
    case accessToken = "matrix_access_token"
    case refreshToken = "matrix_refresh_token"
    case deviceId = "matrix_device_id"
    case userId = "matrix_user_id"
    case homeserver = "matrix_homeserver"
    case recoveryKey = "matrix_recovery_key"
    case backupKey = "matrix_backup_key"
    case crossSigningKey = "matrix_cross_signing_key"
    case pinCode = "app_pin_code"
    case sessionData = "matrix_session_data"
    case oidcToken = "matrix_oidc_token"
    case oidcRefreshToken = "matrix_oidc_refresh_token"
}

// MARK: - KeychainManager
/// iOS Keychain 服务封装，用于安全存储凭据、token、恢复密钥等。
/// 使用 Security.framework 原语，避免第三方依赖。

final class KeychainManager {
    static let shared = KeychainManager()

    private let service: String
    private let accessGroup: String?

    /// The active FFI Client, injected by AuthManager after build/login/restore.
    var ffiClient: Client?

    private init(service: String = "com.socialapp.matrix", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - 存储

    /// 存储字符串到 Keychain
    /// - Parameters:
    ///   - value: 要存储的字符串
    ///   - key: Keychain 键
    func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodeFailed
        }
        try save(data, for: key.rawValue)
    }

    /// 存储 Data 到 Keychain
    /// - Parameters:
    ///   - data: 要存储的数据
    ///   - key: Keychain 键
    func save(_ data: Data, for key: KeychainKey) throws {
        try save(data, for: key.rawValue)
    }

    /// 存储 Codable 对象到 Keychain（JSON 编码）
    /// - Parameters:
    ///   - object: 要存储的可编码对象
    ///   - key: Keychain 键
    func save<T: Encodable>(_ object: T, for key: KeychainKey) throws {
        let data = try JSONEncoder().encode(object)
        try save(data, for: key.rawValue)
    }

    // MARK: - 读取

    /// 从 Keychain 读取字符串
    /// - Parameter key: Keychain 键
    /// - Returns: 存储的字符串，不存在时返回 nil
    func readString(for key: KeychainKey) throws -> String? {
        guard let data = try read(for: key.rawValue) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 Keychain 读取 Data
    /// - Parameter key: Keychain 键
    /// - Returns: 存储的数据，不存在时返回 nil
    func readData(for key: KeychainKey) throws -> Data? {
        try read(for: key.rawValue)
    }

    /// 从 Keychain 读取 Codable 对象（JSON 解码）
    /// - Parameter key: Keychain 键
    /// - Returns: 解码后的对象，不存在时返回 nil
    func read<T: Decodable>(_ type: T.Type, for key: KeychainKey) throws -> T? {
        guard let data = try read(for: key.rawValue) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KeychainError.decodeFailed
        }
    }

    // MARK: - 删除

    /// 从 Keychain 删除指定项
    /// - Parameter key: Keychain 键
    func delete(for key: KeychainKey) throws {
        try delete(for: key.rawValue)
    }

    /// 删除所有本应用存储的 Keychain 项
    func deleteAll() throws {
        let spec: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(spec as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - 存在性检查

    /// 检查 Keychain 中是否存在指定项
    /// - Parameter key: Keychain 键
    /// - Returns: 是否存在
    func exists(for key: KeychainKey) -> Bool {
        (try? read(for: key.rawValue)) != nil
    }

    // MARK: - 批量操作

    /// 批量保存键值对
    /// - Parameter items: 键值对字典
    func saveBatch(_ items: [KeychainKey: String]) throws {
        for (key, value) in items {
            try save(value, for: key)
        }
    }

    /// 批量读取字符串
    /// - Parameter keys: Keychain 键数组
    /// - Returns: 键值对字典
    func readBatch(_ keys: [KeychainKey]) -> [KeychainKey: String] {
        var result: [KeychainKey: String] = [:]
        for key in keys {
            result[key] = (try? readString(for: key)) ?? nil
        }
        return result
    }

    // MARK: - 凭据便捷方法

    /// 保存 Matrix 会话凭据
    func saveSession(
        accessToken: String,
        refreshToken: String?,
        deviceId: String,
        userId: String,
        homeserver: String
    ) throws {
        try saveBatch([
            .accessToken: accessToken,
            .deviceId: deviceId,
            .userId: userId,
            .homeserver: homeserver,
        ])
        if let rt = refreshToken {
            try save(rt, for: .refreshToken)
        }
    }

    /// 读取 Matrix 会话凭据
    /// - Returns: 凭据元组，accessToken 缺失时返回 nil
    func readSession() -> (accessToken: String, refreshToken: String?, deviceId: String, userId: String, homeserver: String)? {
        guard let token = try? readString(for: .accessToken),
              let deviceId = try? readString(for: .deviceId),
              let userId = try? readString(for: .userId),
              let homeserver = try? readString(for: .homeserver) else {
            return nil
        }
        let refreshToken = try? readString(for: .refreshToken)
        return (token, refreshToken, deviceId, userId, homeserver)
    }

    /// 清除所有会话凭据
    func clearSession() throws {
        let keys: [KeychainKey] = [
            .accessToken, .refreshToken, .deviceId, .userId, .homeserver,
            .recoveryKey, .backupKey, .crossSigningKey, .sessionData, .oidcToken, .oidcRefreshToken
        ]
        for key in keys {
            try? delete(for: key)
        }
    }

    // MARK: - Private Core

    private func save(_ data: Data, for key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if let ag = accessGroup {
            query[kSecAttrAccessGroup as String] = ag
        }

        // 先尝试删除旧值
        SecItemDelete(query as CFDictionary)

        // 再写入新值
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func read(for key: String) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let ag = accessGroup {
            query[kSecAttrAccessGroup as String] = ag
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func delete(for key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let ag = accessGroup {
            query[kSecAttrAccessGroup as String] = ag
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - ClientSessionDelegate

extension KeychainManager: ClientSessionDelegate {

    /// Called by the Rust SDK during Client build to restore a persisted session.
    /// Maps Keychain-stored credentials to the FFI Session struct.
    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        guard let creds = readSession(),
              creds.userId == userId else {
            throw KeychainError.itemNotFound
        }
        let oauthData = try? readString(for: .oidcToken)
        return Session(
            accessToken: creds.accessToken,
            refreshToken: creds.refreshToken,
            userId: creds.userId,
            deviceId: creds.deviceId,
            homeserverUrl: creds.homeserver,
            oauthData: oauthData,
            slidingSyncVersion: .none
        )
    }

    /// Called by the Rust SDK after a successful login to persist the session.
    /// Tears down the FFI Session into discrete Keychain entries.
    func saveSessionInKeychain(session: Session) {
        try? saveSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            deviceId: session.deviceId,
            userId: session.userId,
            homeserver: session.homeserverUrl
        )
        if let oauth = session.oauthData {
            try? save(oauth, for: .oidcToken)
        }
    }
}