//! [SocialFeedError + `Result<T>` 类型别名]

use std::fmt;

/// 社交动态模块的错误类型（细粒度版本）
#[derive(Debug, Clone)]
pub enum SocialFeedError {
    // 认证相关
    /// 未认证错误
    NotAuthenticated,
    /// 令牌过期
    TokenExpired,
    /// 权限不足
    PermissionDenied,

    // 资源错误
    /// 主页不存在
    ProfileNotFound,
    /// Room 不存在
    RoomNotFound,
    /// Room 不是有效的 feed Room
    InvalidFeedRoom,
    /// 事件不存在
    EventNotFound,

    // 格式/验证错误
    /// 无效的 Room ID
    InvalidRoomId(String),
    /// 无效的 Event ID
    InvalidEventId(String),
    /// 无效的 User ID
    InvalidUserId(String),
    /// 无效的 URL
    InvalidUrl(String),
    /// 无效的 JSON 数据
    InvalidJson(String),

    // 操作限制
    /// 速率限制（被 homeserver 限流）
    RateLimited { retry_after_ms: u64 },
    /// 超过配额
    QuotaExceeded,
    /// 操作已存在（如重复关注）
    AlreadyExists(String),

    // 网络/同步错误
    /// 网络错误
    NetworkError(String),
    /// 同步失败
    SyncError(String),
    /// 超时
    Timeout,

    // 状态错误
    /// 无效的操作状态
    InvalidState(String),
    /// 循环依赖（如无限转发链）
    CyclicDependency,

    // SDK 错误
    /// Matrix SDK 错误（底层）
    SdkError(String),
    /// 其他错误
    Other(String),
}

impl fmt::Display for SocialFeedError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotAuthenticated => write!(f, "客户端未认证，请先登录"),
            Self::TokenExpired => write!(f, "认证令牌已过期，请重新登录"),
            Self::PermissionDenied => write!(f, "权限不足，无法执行此操作"),
            Self::ProfileNotFound => write!(f, "个人主页不存在，请先创建"),
            Self::RoomNotFound => write!(f, "Room 不存在"),
            Self::InvalidFeedRoom => write!(f, "无效的 feed Room"),
            Self::EventNotFound => write!(f, "事件不存在"),
            Self::InvalidRoomId(id) => write!(f, "无效的 Room ID: {}", id),
            Self::InvalidEventId(id) => write!(f, "无效的 Event ID: {}", id),
            Self::InvalidUserId(id) => write!(f, "无效的 User ID: {}", id),
            Self::InvalidUrl(url) => write!(f, "无效的 URL: {}", url),
            Self::InvalidJson(msg) => write!(f, "无效的 JSON 数据: {}", msg),
            Self::RateLimited { retry_after_ms } => {
                write!(f, "请求被限流，请在 {}ms 后重试", retry_after_ms)
            }
            Self::QuotaExceeded => write!(f, "已超过配额限制"),
            Self::AlreadyExists(msg) => write!(f, "已存在: {}", msg),
            Self::NetworkError(msg) => write!(f, "网络错误: {}", msg),
            Self::SyncError(msg) => write!(f, "同步失败: {}", msg),
            Self::Timeout => write!(f, "请求超时"),
            Self::InvalidState(msg) => write!(f, "无效的操作状态: {}", msg),
            Self::CyclicDependency => write!(f, "检测到循环依赖（可能是无限转发链）"),
            Self::SdkError(msg) => write!(f, "SDK 错误: {}", msg),
            Self::Other(msg) => write!(f, "错误: {}", msg),
        }
    }
}

impl std::error::Error for SocialFeedError {}

/// 操作结果类型别名
pub type Result<T> = std::result::Result<T, SocialFeedError>;

/// 从字符串转换为错误
impl From<String> for SocialFeedError {
    fn from(err: String) -> Self {
        SocialFeedError::Other(err)
    }
}

/// 从 &str 转换为错误
impl From<&str> for SocialFeedError {
    fn from(err: &str) -> Self {
        SocialFeedError::Other(err.to_string())
    }
}

/// 从 JSON 错误转换
impl From<serde_json::Error> for SocialFeedError {
    fn from(err: serde_json::Error) -> Self {
        SocialFeedError::InvalidJson(err.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        assert_eq!(SocialFeedError::ProfileNotFound.to_string(), "个人主页不存在，请先创建");
    }

    #[test]
    fn test_rate_limited_error() {
        let err = SocialFeedError::RateLimited { retry_after_ms: 5000 };
        assert!(err.to_string().contains("5000ms"));
    }

    #[test]
    fn test_error_from_string() {
        let err: SocialFeedError = "test error".into();
        match err {
            SocialFeedError::Other(msg) => assert_eq!(msg, "test error"),
            _ => panic!("Expected Other variant"),
        }
    }

    #[test]
    fn test_error_from_json() {
        let json_err = r#"{"invalid": json"#;
        let parse_err: serde_json::Error =
            serde_json::from_str::<serde_json::Value>(json_err).unwrap_err();
        let err: SocialFeedError = parse_err.into();
        match err {
            SocialFeedError::InvalidJson(_) => (),
            _ => panic!("Expected InvalidJson variant"),
        }
    }

    #[test]
    fn test_cyclic_dependency_error() {
        let err = SocialFeedError::CyclicDependency;
        assert!(err.to_string().contains("循环依赖"));
    }
}
