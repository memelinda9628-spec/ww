//! 社交动态管理器核心模块 [SocialFeed 结构体 + 初始化 + Room 识别]
//!
//! 包含 SocialFeed 结构体定义、创建、状态恢复和 Room 识别逻辑。

use matrix_sdk::{room::Room, Client};
use matrix_sdk::ruma::OwnedRoomId;
use crate::types::config::Config;
use crate::services::cache::ProfileCache;
use crate::services::aggregation::AggregationCache;
use crate::services::rate_limit::RateLimiter;
use std::sync::Arc;

/// 社交动态管理器。关注/取关/信息流的状态由 Matrix SDK 持久化，
/// 不另存内存副本，重启后自动恢复。
pub struct SocialFeed {
    pub(crate) client: Client,
    /// 自己的 feed Room ID，首次 create_profile 后缓存
    pub(crate) my_feed_room_id: Option<OwnedRoomId>,
    /// 配置对象
    pub(crate) config: Config,
    /// 用户资料缓存（display_name、avatar 等）
    pub(crate) profile_cache: ProfileCache,
    /// 事件聚合计数缓存（点赞/评论/转发）
    pub(crate) aggregation_cache: Arc<AggregationCache>,
    /// 速率限制器
    pub(crate) rate_limiter: Arc<RateLimiter>,
}

impl SocialFeed {
    /// 使用已认证的 Matrix Client 和默认配置创建实例。
    ///
    /// 会自动从 SDK 恢复状态（已加入的 feed Room、关注列表）。
    pub fn new(client: Client) -> Self {
        Self::with_config(client, Config::default())
    }

    /// 使用已认证的 Matrix Client 和自定义配置创建实例。
    pub fn with_config(client: Client, config: Config) -> Self {
        let mut feed = Self {
            client,
            my_feed_room_id: None,
            config,
            profile_cache: ProfileCache::new(),
            aggregation_cache: Arc::new(AggregationCache::new()),
            rate_limiter: Arc::new(RateLimiter::default()),
        };
        feed.restore_state();
        feed
    }

    /// 从 SDK 持久化数据中恢复 my_feed_room_id。
    /// feed Room 的判断依据：已加入的公开 Room，名称与配置匹配，topic 与配置匹配。
    fn restore_state(&mut self) {
        for room in self.client.joined_rooms() {
            if self.is_feed_room(&room) {
                self.my_feed_room_id = Some(room.room_id().to_owned());
                break; // 只有一个自己的 feed Room
            }
        }
    }

    /// 判断一个 Room 是否为 feed Room。
    /// 条件：名称与配置后缀匹配，且 topic 与配置前缀匹配。
    pub(crate) fn is_feed_room(&self, room: &Room) -> bool {
        let name_match = room.name()
            .map(|n| self.config.matches_feed_room_name(&n))
            .unwrap_or(false);
        let topic_match = room.topic()
            .map(|t| self.config.matches_feed_room_topic(&t))
            .unwrap_or(false);
        name_match && topic_match
    }
}
