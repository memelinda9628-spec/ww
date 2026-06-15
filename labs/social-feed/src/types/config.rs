//! 配置模块 [Config + ConfigBuilder，控制 feed Room 命名/缓存/分页等行为]
//!
//! 提供社交动态模块的配置管理。

use std::time::Duration;
use serde::{Deserialize, Serialize};

/// 社交动态模块配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// 个人主页 Room 的 Room Name 后缀
    pub feed_room_name_suffix: String,
    /// 个人主页 Room 的 Topic 前缀
    pub feed_room_topic_prefix: String,
    /// 默认分页大小
    pub default_page_size: u32,
    /// Profile 缓存 TTL（秒）
    pub profile_cache_ttl_secs: u64,
    /// 最大缓存条目数
    pub max_cache_entries: usize,
    /// 启用图片提取
    pub enable_image_extraction: bool,
    /// 启用评论计数
    pub enable_comment_counting: bool,
}

impl Config {
    /// 创建默认配置
    pub fn default_config() -> Self {
        Self {
            feed_room_name_suffix: "的主页".to_string(),
            feed_room_topic_prefix: "feed:".to_string(),
            default_page_size: 20,
            profile_cache_ttl_secs: 3600,  // 1 小时
            max_cache_entries: 1000,
            enable_image_extraction: true,
            enable_comment_counting: false,  // 待实现
        }
    }

    /// 获取 profile 缓存 TTL
    pub fn profile_cache_ttl(&self) -> Duration {
        Duration::from_secs(self.profile_cache_ttl_secs)
    }

    /// 完整的 feed room 识别器
    pub fn feed_room_name(&self, display_name: &str) -> String {
        format!("{} {}", display_name, self.feed_room_name_suffix)
    }

    /// 检查 room 名称是否匹配 feed room 后缀
    pub fn matches_feed_room_name(&self, room_name: &str) -> bool {
        room_name.ends_with(&self.feed_room_name_suffix)
    }

    /// 检查 topic 是否匹配 feed room 前缀
    pub fn matches_feed_room_topic(&self, topic: &str) -> bool {
        topic.starts_with(&self.feed_room_topic_prefix)
    }

    /// 获取完整的 feed room topic
    pub fn feed_room_topic(&self, identifier: &str) -> String {
        format!("{}{}", self.feed_room_topic_prefix, identifier)
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::default_config()
    }
}

/// 构建器模式配置
pub struct ConfigBuilder {
    config: Config,
}

impl ConfigBuilder {
    /// 创建新的配置构建器
    pub fn new() -> Self {
        Self {
            config: Config::default_config(),
        }
    }

    /// 设置 feed room 名称后缀
    pub fn feed_room_name_suffix(mut self, suffix: String) -> Self {
        self.config.feed_room_name_suffix = suffix;
        self
    }

    /// 设置 feed room topic 前缀
    pub fn feed_room_topic_prefix(mut self, prefix: String) -> Self {
        self.config.feed_room_topic_prefix = prefix;
        self
    }

    /// 设置默认分页大小
    pub fn default_page_size(mut self, size: u32) -> Self {
        self.config.default_page_size = size;
        self
    }

    /// 设置 profile 缓存 TTL
    pub fn profile_cache_ttl(mut self, secs: u64) -> Self {
        self.config.profile_cache_ttl_secs = secs;
        self
    }

    /// 设置最大缓存条目数
    pub fn max_cache_entries(mut self, max: usize) -> Self {
        self.config.max_cache_entries = max;
        self
    }

    /// 启用/禁用图片提取
    pub fn enable_image_extraction(mut self, enable: bool) -> Self {
        self.config.enable_image_extraction = enable;
        self
    }

    /// 启用/禁用评论计数
    pub fn enable_comment_counting(mut self, enable: bool) -> Self {
        self.config.enable_comment_counting = enable;
        self
    }

    /// 构建最终配置
    pub fn build(self) -> Config {
        self.config
    }
}

impl Default for ConfigBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default_config();
        assert_eq!(config.default_page_size, 20);
        assert_eq!(config.profile_cache_ttl_secs, 3600);
    }

    #[test]
    fn test_feed_room_name() {
        let config = Config::default_config();
        let name = config.feed_room_name("Alice");
        assert_eq!(name, "Alice 的主页");
    }

    #[test]
    fn test_matches_feed_room_name() {
        let config = Config::default_config();
        assert!(config.matches_feed_room_name("Alice 的主页"));
        assert!(!config.matches_feed_room_name("Alice Room"));
    }

    #[test]
    fn test_config_builder() {
        let config = ConfigBuilder::new()
            .default_page_size(50)
            .profile_cache_ttl(7200)
            .build();

        assert_eq!(config.default_page_size, 50);
        assert_eq!(config.profile_cache_ttl_secs, 7200);
    }
}
