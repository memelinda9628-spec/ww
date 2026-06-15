//! 数据模型定义 [Moment / UserProfile，零 SDK 依赖]
//!
//! 包含 Moment（动态）和 UserProfile（用户资料）两个核心数据结构。
//! 这些结构不依赖 Matrix SDK，可以独立序列化/反序列化。

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// 一条动态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Moment {
    /// 动态 ID（对应 Matrix event_id）
    pub id: String,
    /// 发布者 user_id
    pub author_id: String,
    /// 发布者昵称
    pub author_name: String,
    /// 发布者头像 URL
    pub author_avatar: Option<String>,
    /// 文字内容（优先取 formatted body 以保留图片等富文本）
    pub text: String,
    /// 图片 URL 列表
    pub images: Vec<String>,
    /// 发布时间
    pub created_at: DateTime<Utc>,
    /// 点赞数
    pub like_count: u64,
    /// 评论数
    pub comment_count: u64,
}

/// 用户资料
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserProfile {
    pub user_id: String,
    pub display_name: Option<String>,
    /// 用户头像 URL
    pub avatar_url: Option<String>,
    /// 用户简介/bio
    pub bio: Option<String>,
    /// 用户位置
    pub location: Option<String>,
    /// 个人主页对应的公开 Room ID
    pub feed_room_id: String,
    /// 粉丝数（Room 成员数 - 1）
    pub follower_count: u64,
    /// 关注数
    pub following_count: u64,
    /// 动态数
    pub moments_count: u64,
}


