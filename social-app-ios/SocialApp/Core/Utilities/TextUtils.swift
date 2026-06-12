import Foundation

// MARK: - TextUtils
// MARK: - 待接入
/// 文本处理工具，对应 Rust 的 text.rs（4 函数）

enum TextUtils {
    /// 截断文本到指定字符数，末尾追加 "..."
    static func truncate(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<endIndex]) + "..."
    }

    /// 压缩多余空格（多个空格→单个，去除首尾空格）
    static func trimExtraSpaces(_ text: String) -> String {
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 判断字符串是否为空或全空白
    static func isBlank(_ text: String?) -> Bool {
        guard let text = text else { return true }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 格式化时间间隔为中文友好描述
    static func formatDuration(seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))秒"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))分钟"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return mins > 0 ? "\(hours)小时\(mins)分钟" : "\(hours)小时"
        } else {
            let days = Int(seconds / 86400)
            let hours = Int((seconds.truncatingRemainder(dividingBy: 86400)) / 3600)
            return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天"
        }
    }
}