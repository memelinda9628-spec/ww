//! 事件聚合模块 [like/reply/forward 计数缓存，供 timeline + interaction 联动]
//!
//! 支持实时点赞和评论计数，使用 m.relates_to aggregation 关系。

use std::{collections::HashMap, sync::Arc};

use tokio::sync::RwLock;

use crate::types::models::Moment;

/// 聚合计数结果
#[derive(Debug, Clone)]
pub struct AggregationStats {
    /// 点赞数
    pub like_count: u64,
    /// 评论数（回复数）
    pub reply_count: u64,
    /// 转发数
    pub forward_count: u64,
}

impl AggregationStats {
    /// 创建零计数的统计
    pub fn zero() -> Self {
        Self { like_count: 0, reply_count: 0, forward_count: 0 }
    }
}

/// 事件聚合计数缓存
///
/// 缓存事件的互动统计（点赞、评论、转发），支持增量更新。
/// 设计用于监听 m.relates_to 关系事件并自动更新计数。
#[derive(Debug)]
pub struct AggregationCache {
    /// (room_id, event_id) → AggregationStats
    stats: Arc<RwLock<HashMap<(String, String), AggregationStats>>>,
    /// 最后更新时间戳（用于检测陈旧性）
    last_updated: Arc<RwLock<HashMap<(String, String), i64>>>,
}

impl AggregationCache {
    /// 创建新的聚合计数缓存
    pub fn new() -> Self {
        Self {
            stats: Arc::new(RwLock::new(HashMap::new())),
            last_updated: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// 获取指定事件的聚合统计
    pub async fn get_stats(&self, room_id: &str, event_id: &str) -> AggregationStats {
        let key = (room_id.to_string(), event_id.to_string());
        let stats = self.stats.read().await;
        stats.get(&key).cloned().unwrap_or_else(AggregationStats::zero)
    }

    /// 设置聚合统计
    pub async fn set_stats(&self, room_id: &str, event_id: &str, stats: AggregationStats) {
        let key = (room_id.to_string(), event_id.to_string());
        let mut cache = self.stats.write().await;
        cache.insert(key.clone(), stats);

        let mut timestamps = self.last_updated.write().await;
        timestamps.insert(key, chrono::Utc::now().timestamp());
    }

    /// 增加点赞计数
    pub async fn increment_likes(&self, room_id: &str, event_id: &str) {
        let key = (room_id.to_string(), event_id.to_string());
        let mut cache = self.stats.write().await;
        let stats = cache.entry(key.clone()).or_insert_with(AggregationStats::zero);
        stats.like_count += 1;

        let mut timestamps = self.last_updated.write().await;
        timestamps.insert(key, chrono::Utc::now().timestamp());
    }

    /// 增加评论计数
    pub async fn increment_replies(&self, room_id: &str, event_id: &str) {
        let key = (room_id.to_string(), event_id.to_string());
        let mut cache = self.stats.write().await;
        let stats = cache.entry(key.clone()).or_insert_with(AggregationStats::zero);
        stats.reply_count += 1;

        let mut timestamps = self.last_updated.write().await;
        timestamps.insert(key, chrono::Utc::now().timestamp());
    }

    /// 增加转发计数
    pub async fn increment_forwards(&self, room_id: &str, event_id: &str) {
        let key = (room_id.to_string(), event_id.to_string());
        let mut cache = self.stats.write().await;
        let stats = cache.entry(key.clone()).or_insert_with(AggregationStats::zero);
        stats.forward_count += 1;

        let mut timestamps = self.last_updated.write().await;
        timestamps.insert(key, chrono::Utc::now().timestamp());
    }

    /// 减少点赞计数（用于删除 reaction）
    pub async fn decrement_likes(&self, room_id: &str, event_id: &str) {
        let key = (room_id.to_string(), event_id.to_string());
        let mut cache = self.stats.write().await;
        if let Some(stats) = cache.get_mut(&key) {
            if stats.like_count > 0 {
                stats.like_count -= 1;
            }
        }

        let mut timestamps = self.last_updated.write().await;
        timestamps.insert(key, chrono::Utc::now().timestamp());
    }

    /// 批量更新统计信息
    pub async fn update_batch(&self, updates: Vec<(String, String, AggregationStats)>) {
        let mut cache = self.stats.write().await;
        let mut timestamps = self.last_updated.write().await;
        let now = chrono::Utc::now().timestamp();

        for (room_id, event_id, stats) in updates {
            let key = (room_id, event_id);
            cache.insert(key.clone(), stats);
            timestamps.insert(key, now);
        }
    }

    /// 清除指定事件的统计
    pub async fn clear_stats(&self, room_id: &str, event_id: &str) {
        let key = (room_id.to_string(), event_id.to_string());
        self.stats.write().await.remove(&key);
        self.last_updated.write().await.remove(&key);
    }

    /// 清除全部统计
    pub async fn clear_all(&self) {
        self.stats.write().await.clear();
        self.last_updated.write().await.clear();
    }

    /// 获取缓存中的统计数量
    pub async fn len(&self) -> usize {
        self.stats.read().await.len()
    }

    /// 检查缓存是否为空
    pub async fn is_empty(&self) -> bool {
        self.stats.read().await.is_empty()
    }

    /// 应用聚合统计到 Moment
    pub async fn apply_stats(&self, moment: &mut Moment, room_id: &str) {
        let stats = self.get_stats(room_id, &moment.id).await;
        moment.like_count = stats.like_count;
        moment.comment_count = stats.reply_count;
    }
}

impl Default for AggregationCache {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_aggregation_increment() {
        let cache = AggregationCache::new();
        let room_id = "!room:example.com";
        let event_id = "$event123";

        cache.increment_likes(room_id, event_id).await;
        cache.increment_likes(room_id, event_id).await;
        cache.increment_replies(room_id, event_id).await;

        let stats = cache.get_stats(room_id, event_id).await;
        assert_eq!(stats.like_count, 2);
        assert_eq!(stats.reply_count, 1);
    }

    #[tokio::test]
    async fn test_aggregation_decrement() {
        let cache = AggregationCache::new();
        let room_id = "!room:example.com";
        let event_id = "$event123";

        cache.increment_likes(room_id, event_id).await;
        cache.increment_likes(room_id, event_id).await;
        cache.decrement_likes(room_id, event_id).await;

        let stats = cache.get_stats(room_id, event_id).await;
        assert_eq!(stats.like_count, 1);
    }

    #[tokio::test]
    async fn test_aggregation_batch_update() {
        let cache = AggregationCache::new();

        let updates = vec![
            (
                "!room1:example.com".to_string(),
                "$event1".to_string(),
                AggregationStats { like_count: 5, reply_count: 2, forward_count: 1 },
            ),
            (
                "!room2:example.com".to_string(),
                "$event2".to_string(),
                AggregationStats { like_count: 10, reply_count: 3, forward_count: 0 },
            ),
        ];

        cache.update_batch(updates).await;
        assert_eq!(cache.len().await, 2);

        let stats1 = cache.get_stats("!room1:example.com", "$event1").await;
        assert_eq!(stats1.like_count, 5);
    }

    #[tokio::test]
    async fn test_aggregation_clear() {
        let cache = AggregationCache::new();
        let room_id = "!room:example.com";
        let event_id = "$event123";

        cache.increment_likes(room_id, event_id).await;
        assert_eq!(cache.len().await, 1);

        cache.clear_all().await;
        assert_eq!(cache.len().await, 0);
    }
}
