//! [ForwardMetadata 带原文引用，供 forward() 生成富文本转发消息]

use serde::{Deserialize, Serialize};

use crate::types::models::Moment;

/// 转发元数据
///
/// 保存关于被转发的原始事件的完整信息，以便在跨 homeserver 场景下
/// 仍能恢复原文。使用 m.relates_to quote 关系存储。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ForwardMetadata {
    /// 原始事件 ID
    pub original_event_id: String,
    /// 原始 Room ID
    pub original_room_id: String,
    /// 原始事件的完整 URL（matrix:// 或 https://）
    pub original_event_url: String,
    /// 原作者 user_id
    pub original_author_id: String,
    /// 原文本内容（备份）
    pub original_text: String,
    /// 原作者昵称（备份）
    pub original_author_name: String,
    /// 原作者头像（备份）
    pub original_author_avatar: Option<String>,
    /// 转发者的附言
    pub quote_text: String,
}

impl ForwardMetadata {
    /// 从原 Moment 和附言创建转发元数据
    pub fn from_moment(
        moment: &Moment,
        room_id: String,
        quote_text: String,
        event_url: String,
    ) -> Self {
        Self {
            original_event_id: moment.id.clone(),
            original_room_id: room_id,
            original_event_url: event_url,
            original_author_id: moment.author_id.clone(),
            original_text: moment.text.clone(),
            original_author_name: moment.author_name.clone(),
            original_author_avatar: moment.author_avatar.clone(),
            quote_text,
        }
    }

    /// 生成格式化的转发消息体
    pub fn formatted_body(&self) -> String {
        format!(
            "<blockquote><p><strong>{}</strong> (@{})</p><p>{}</p></blockquote>\n\n{}",
            self.original_author_name, self.original_author_id, self.original_text, self.quote_text
        )
    }

    /// 生成纯文本的转发消息体
    pub fn plain_body(&self) -> String {
        format!(
            "> {} (@{}):\n> {}\n\n{}",
            self.original_author_name, self.original_author_id, self.original_text, self.quote_text
        )
    }

    /// 序列化为 JSON（用于嵌入 m.relates_to）
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// 从 JSON 反序列化
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

/// 转发管理器
pub struct ForwardManager;

impl ForwardManager {
    /// 构建转发事件 URL（支持 matrix:// 和 https:// 格式）
    pub fn build_event_url(_homeserver: &str, room_id: &str, event_id: &str) -> String {
        // matrix:// URL 格式：matrix://roomid/eventid
        format!("matrix://roomid/{}/eventid/{}", room_id, event_id)
    }

    /// 从 matrix:// URL 解析事件信息
    pub fn parse_matrix_url(url: &str) -> Option<(String, String)> {
        if !url.starts_with("matrix://roomid/") {
            return None;
        }
        let parts: Vec<&str> = url.split("/eventid/").collect();
        if parts.len() == 2 {
            Some((parts[0].strip_prefix("matrix://roomid/")?.to_string(), parts[1].to_string()))
        } else {
            None
        }
    }

    /// 检查原事件是否可访问（简单检查）
    pub async fn is_source_accessible(event_url: &str) -> bool {
        // 实际应用中可以尝试 HTTP HEAD 请求
        // 这里仅做 URL 格式验证
        event_url.starts_with("matrix://") || event_url.starts_with("https://")
    }

    /// 验证转发链条（防止无限转发）
    pub fn detect_forward_loop(quote_text: &str, max_depth: usize) -> bool {
        // 简单启发式：计算 blockquote 嵌套深度
        let depth = quote_text.matches("<blockquote>").count();
        depth > max_depth
    }

    /// 从转发消息中提取原 URL
    pub fn extract_source_url_from_metadata(metadata: &ForwardMetadata) -> String {
        metadata.original_event_url.clone()
    }
}

#[cfg(test)]
mod tests {
    use chrono::Utc;

    use super::*;

    fn create_test_moment() -> Moment {
        Moment {
            id: "$event123".to_string(),
            author_id: "@alice:example.com".to_string(),
            author_name: "Alice".to_string(),
            author_avatar: Some("mxc://example.com/avatar".to_string()),
            text: "Great post!".to_string(),
            images: vec![],
            created_at: Utc::now(),
            like_count: 5,
            comment_count: 2,
        }
    }

    #[test]
    fn test_forward_metadata_creation() {
        let moment = create_test_moment();
        let metadata = ForwardMetadata::from_moment(
            &moment,
            "!room:example.com".to_string(),
            "Love this!".to_string(),
            "matrix://roomid/!room:example.com/eventid/$event123".to_string(),
        );

        assert_eq!(metadata.original_author_id, "@alice:example.com");
        assert_eq!(metadata.original_text, "Great post!");
        assert_eq!(metadata.quote_text, "Love this!");
    }

    #[test]
    fn test_forward_metadata_formatted_body() {
        let moment = create_test_moment();
        let metadata = ForwardMetadata::from_moment(
            &moment,
            "!room:example.com".to_string(),
            "Love this!".to_string(),
            "matrix://roomid/!room:example.com/eventid/$event123".to_string(),
        );

        let body = metadata.formatted_body();
        assert!(body.contains("Alice"));
        assert!(body.contains("@alice:example.com"));
        assert!(body.contains("Great post!"));
        assert!(body.contains("Love this!"));
    }

    #[test]
    fn test_build_event_url() {
        let url = ForwardManager::build_event_url("example.com", "!room:example.com", "$event123");
        assert_eq!(url, "matrix://roomid/!room:example.com/eventid/$event123");
    }

    #[test]
    fn test_parse_matrix_url() {
        let url = "matrix://roomid/!room:example.com/eventid/$event123";
        let result = ForwardManager::parse_matrix_url(url);
        assert!(result.is_some());
        let (room_id, event_id) = result.unwrap();
        assert_eq!(room_id, "!room:example.com");
        assert_eq!(event_id, "$event123");
    }

    #[test]
    fn test_detect_forward_loop() {
        let normal_text = "<blockquote>Quote level 1</blockquote>";
        let deep_text = "<blockquote><blockquote><blockquote><blockquote>Very deep</blockquote></blockquote></blockquote></blockquote>";

        assert!(!ForwardManager::detect_forward_loop(normal_text, 3));
        assert!(ForwardManager::detect_forward_loop(deep_text, 3));
    }

    #[test]
    fn test_metadata_serialization() {
        let moment = create_test_moment();
        let metadata = ForwardMetadata::from_moment(
            &moment,
            "!room:example.com".to_string(),
            "Love this!".to_string(),
            "matrix://roomid/!room:example.com/eventid/$event123".to_string(),
        );

        let json = metadata.to_json().unwrap();
        let deserialized = ForwardMetadata::from_json(&json).unwrap();

        assert_eq!(deserialized.original_author_id, metadata.original_author_id);
        assert_eq!(deserialized.quote_text, metadata.quote_text);
    }
}
