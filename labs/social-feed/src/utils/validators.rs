//! 验证工具 [ID/URL 格式验证，供 App 层输入校验]
//!
//! Matrix ID 格式验证和 URL 验证。

/// 验证 user_id 格式（@username:homeserver）
pub fn is_valid_user_id(user_id: &str) -> bool {
    if !user_id.starts_with('@') {
        return false;
    }
    if !user_id.contains(':') {
        return false;
    }
    let parts: Vec<&str> = user_id.split(':').collect();
    parts.len() == 2 && parts[0].len() > 1 && !parts[1].is_empty()
}

/// 验证 room_id 格式（!roomid:homeserver）
pub fn is_valid_room_id(room_id: &str) -> bool {
    if !room_id.starts_with('!') {
        return false;
    }
    if !room_id.contains(':') {
        return false;
    }
    let parts: Vec<&str> = room_id.split(':').collect();
    parts.len() == 2 && parts[0].len() > 1 && !parts[1].is_empty()
}

/// 验证 event_id 格式（$eventid）
pub fn is_valid_event_id(event_id: &str) -> bool {
    event_id.starts_with('$') && event_id.len() > 1
}

/// 验证 URL 格式
pub fn is_valid_url(url: &str) -> bool {
    url.starts_with("http://") || url.starts_with("https://") || url.starts_with("mxc://")
}

/// 从 user_id 提取用户名部分
pub fn extract_username(user_id: &str) -> Option<&str> {
    if !user_id.starts_with('@') {
        return None;
    }
    if let Some(pos) = user_id.find(':') {
        Some(&user_id[1..pos])
    } else {
        None
    }
}

/// 从 user_id 提取 homeserver 部分
pub fn extract_homeserver(user_id: &str) -> Option<&str> {
    if let Some(pos) = user_id.find(':') {
        Some(&user_id[pos + 1..])
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_valid_user_id() {
        assert!(is_valid_user_id("@alice:example.com"));
        assert!(is_valid_user_id("@bob:matrix.org"));
        assert!(!is_valid_user_id("alice:example.com"));
        assert!(!is_valid_user_id("@alice"));
        assert!(!is_valid_user_id("@:example.com"));
    }

    #[test]
    fn test_is_valid_room_id() {
        assert!(is_valid_room_id("!room123:example.com"));
        assert!(is_valid_room_id("!abc:matrix.org"));
        assert!(!is_valid_room_id("room123:example.com"));
        assert!(!is_valid_room_id("!room123"));
        assert!(!is_valid_room_id("!:example.com"));
    }

    #[test]
    fn test_is_valid_event_id() {
        assert!(is_valid_event_id("$event123"));
        assert!(is_valid_event_id("$abc"));
        assert!(!is_valid_event_id("event123"));
        assert!(!is_valid_event_id("$"));
    }

    #[test]
    fn test_is_valid_url() {
        assert!(is_valid_url("https://example.com/image.jpg"));
        assert!(is_valid_url("http://example.com/image.jpg"));
        assert!(is_valid_url("mxc://example.com/image123"));
        assert!(!is_valid_url("ftp://example.com/file"));
        assert!(!is_valid_url("example.com"));
    }

    #[test]
    fn test_extract_username() {
        assert_eq!(extract_username("@alice:example.com"), Some("alice"));
        assert_eq!(extract_username("@bob:matrix.org"), Some("bob"));
        assert_eq!(extract_username("alice:example.com"), None);
    }

    #[test]
    fn test_extract_homeserver() {
        assert_eq!(extract_homeserver("@alice:example.com"), Some("example.com"));
        assert_eq!(extract_homeserver("@bob:matrix.org"), Some("matrix.org"));
        assert_eq!(extract_homeserver("alice"), None);
    }
}
