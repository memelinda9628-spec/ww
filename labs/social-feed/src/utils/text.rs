//! 文本处理工具 [截断/空格/格式化，供 App 层使用]
//!
//! 文本截断、空格清理、时间格式化等。

/// 截断文本到指定长度（安全切分 UTF-8 边界）
pub fn truncate_text(text: &str, max_len: usize) -> String {
    if text.len() <= max_len {
        text.to_string()
    } else {
        // 使用 chars() 避免切在 multi-byte 字符中间导致 panic
        let truncated: String = text.chars().take(max_len).collect();
        format!("{}...", truncated)
    }
}

/// 清除文本中的多余空格
pub fn trim_extra_spaces(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// 检查文本是否为空或仅包含空格
pub fn is_blank(text: &str) -> bool {
    text.trim().is_empty()
}

/// 格式化时间为易读格式
pub fn format_duration(secs: u64) -> String {
    if secs < 60 {
        format!("{}秒前", secs)
    } else if secs < 3600 {
        format!("{}分钟前", secs / 60)
    } else if secs < 86400 {
        format!("{}小时前", secs / 3600)
    } else {
        format!("{}天前", secs / 86400)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_truncate_text() {
        let text = "This is a long text";
        assert_eq!(truncate_text(text, 10), "This is a ...");  // chars, not bytes
        assert_eq!(truncate_text(text, 100), text);
        // 中文字符测试：4 个字符（每字符 3 bytes），截断到 2 char
        assert_eq!(truncate_text("你好世界", 2), "你好...");
    }

    #[test]
    fn test_trim_extra_spaces() {
        assert_eq!(trim_extra_spaces("hello   world  test"), "hello world test");
        assert_eq!(trim_extra_spaces("  hello  "), "hello");
    }

    #[test]
    fn test_is_blank() {
        assert!(is_blank(""));
        assert!(is_blank("   "));
        assert!(!is_blank("hello"));
    }

    #[test]
    fn test_format_duration() {
        assert_eq!(format_duration(30), "30秒前");
        assert_eq!(format_duration(3600), "1小时前");
        assert_eq!(format_duration(86400), "1天前");
    }
}
