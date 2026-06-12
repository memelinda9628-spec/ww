import Foundation

// MARK: - Matrix ID Validators
// MARK: - 待接入
/// 对应 Rust 的 validators.rs（6 函数）

enum MatrixValidators {
    /// 校验 User ID 格式: @localpart:server
    static func isValidUserId(_ id: String) -> Bool {
        let pattern = #"^@[a-zA-Z0-9._=\-/]+:[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    /// 校验 Room ID 格式: !opaque_id:server
    static func isValidRoomId(_ id: String) -> Bool {
        let pattern = #"^![a-zA-Z0-9._=\-/]+:[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    /// 校验 Event ID 格式: $opaque_id
    static func isValidEventId(_ id: String) -> Bool {
        let pattern = #"^\$[a-zA-Z0-9._=\-/]+$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    /// 校验 URL
    static func isValidUrl(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && url.host != nil
    }

    /// 从 User ID 提取用户名（localpart）
    static func extractUsername(from userId: String) -> String? {
        guard isValidUserId(userId) else { return nil }
        // @localpart:server → localpart
        let trimmed = userId.dropFirst()
        guard let colonIdx = trimmed.firstIndex(of: ":") else { return nil }
        return String(trimmed[..<colonIdx])
    }

    /// 从 User ID 提取 homeserver
    static func extractHomeserver(from userId: String) -> String? {
        guard isValidUserId(userId) else { return nil }
        guard let colonIdx = userId.firstIndex(of: ":") else { return nil }
        return String(userId[userId.index(after: colonIdx)...])
    }
}