//! 缓存模块 [Profile 缓存，供 timeline.rs fetch_room_moments 查询 display_name]
//!
//! 提供用户 profile、头像等数据的缓存机制，避免频繁的 API 调用。
//! 支持 TTL 过期和事件驱动的热失效机制。

use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};

use matrix_sdk::ruma::{OwnedRoomId, OwnedUserId};
use tokio::sync::RwLock;

/// 缓存条目，包含数据和过期时间
#[derive(Debug, Clone)]
struct CacheEntry<T> {
    value: T,
    expires_at: Instant,
    /// 该条目关联的事件版本（用于检测状态变更）
    #[allow(dead_code)]
    version: u64,
}

impl<T> CacheEntry<T> {
    /// 检查缓存是否过期
    fn is_expired(&self) -> bool {
        Instant::now() > self.expires_at
    }
}

/// 缓存失效事件
#[derive(Debug, Clone)]
pub enum CacheInvalidationEvent {
    /// 用户资料更新（由 m.room.member 状态事件触发）
    UserProfileChanged(OwnedUserId),
    /// 批量失效（例如同步后）
    BatchInvalidate(Vec<OwnedUserId>),
    /// 特定 Room 的成员资料全部失效
    RoomMemberInvalidate(OwnedRoomId),
    /// 全局清除
    Clear,
}

/// 个人资料缓存条目类型
type ProfileEntry = CacheEntry<(String, Option<String>)>;
/// 失效事件监听器类型
type InvalidationListener = Box<dyn Fn(CacheInvalidationEvent) + Send + Sync>;

/// 用户资料缓存（带事件驱动失效）
pub struct ProfileCache {
    /// user_id → (display_name, avatar_url, version)
    profiles: Arc<RwLock<HashMap<String, ProfileEntry>>>,
    /// TTL（生存时间）
    ttl: Duration,
    /// 失效事件监听器（可选）
    invalidation_listeners: Arc<RwLock<Vec<InvalidationListener>>>,
    /// 最大缓存条目数
    max_entries: usize,
    /// 版本号计数器（递增）
    version_counter: Arc<RwLock<u64>>,
}

impl std::fmt::Debug for ProfileCache {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ProfileCache")
            .field("ttl", &self.ttl)
            .field("max_entries", &self.max_entries)
            .finish()
    }
}

impl ProfileCache {
    /// 创建新的 Profile 缓存，设置默认 TTL 为 1 小时
    pub fn new() -> Self {
        Self::with_ttl(Duration::from_secs(3600), 1000)
    }

    /// 使用自定义 TTL 创建 Profile 缓存
    pub fn with_ttl(ttl: Duration, max_entries: usize) -> Self {
        Self {
            profiles: Arc::new(RwLock::new(HashMap::new())),
            ttl,
            invalidation_listeners: Arc::new(RwLock::new(Vec::new())),
            max_entries,
            version_counter: Arc::new(RwLock::new(0)),
        }
    }

    /// 获取缓存中的 profile，如果过期或不存在则返回 None
    pub async fn get(&self, user_id: &OwnedUserId) -> Option<(String, Option<String>)> {
        let key = user_id.to_string();
        let profiles = self.profiles.read().await;
        profiles.get(&key).and_then(|entry| {
            if entry.is_expired() {
                None
            } else {
                Some(entry.value.clone())
            }
        })
    }

    /// 将 profile 写入缓存
    pub async fn set(
        &self,
        user_id: OwnedUserId,
        display_name: String,
        avatar_url: Option<String>,
    ) {
        let key = user_id.to_string();
        let mut version = self.version_counter.write().await;
        *version += 1;

        let mut profiles = self.profiles.write().await;

        // LRU 淘汰：如果超过最大数量，删除最后访问的
        if profiles.len() >= self.max_entries && !profiles.contains_key(&key) {
            // 复制 key 以避免借用冲突
            let old_key = profiles.keys().next().cloned();
            if let Some(k) = old_key {
                profiles.remove(&k);
            }
        }

        profiles.insert(
            key,
            CacheEntry {
                value: (display_name, avatar_url),
                expires_at: Instant::now() + self.ttl,
                version: *version,
            },
        );
    }

    /// 清除过期的缓存条目
    pub async fn cleanup(&self) {
        let mut profiles = self.profiles.write().await;
        let expired_users: Vec<String> = profiles
            .iter()
            .filter(|(_, entry)| entry.is_expired())
            .map(|(k, _)| k.clone())
            .collect();

        for key in &expired_users {
            profiles.remove(key);
        }
    }

    /// 手动失效指定用户的缓存
    pub async fn invalidate(&self, user_id: &OwnedUserId) {
        let mut profiles = self.profiles.write().await;
        profiles.remove(&user_id.to_string());

        // 通知监听器
        self.emit_invalidation_event(CacheInvalidationEvent::UserProfileChanged(user_id.clone()))
            .await;
    }

    /// 批量失效缓存
    pub async fn invalidate_batch(&self, user_ids: Vec<OwnedUserId>) {
        let mut profiles = self.profiles.write().await;
        for user_id in &user_ids {
            profiles.remove(&user_id.to_string());
        }

        // 通知监听器
        self.emit_invalidation_event(CacheInvalidationEvent::BatchInvalidate(user_ids)).await;
    }

    /// 清除全部缓存
    pub async fn clear(&self) {
        self.profiles.write().await.clear();
        self.emit_invalidation_event(CacheInvalidationEvent::Clear).await;
    }

    /// 获取缓存条目数量
    pub async fn len(&self) -> usize {
        self.profiles.read().await.len()
    }

    /// 检查缓存是否为空
    pub async fn is_empty(&self) -> bool {
        self.profiles.read().await.is_empty()
    }

    /// 注册失效事件监听器
    pub async fn on_invalidation<F>(&self, listener: F)
    where
        F: Fn(CacheInvalidationEvent) + Send + Sync + 'static,
    {
        let mut listeners = self.invalidation_listeners.write().await;
        listeners.push(Box::new(listener));
    }

    /// 触发失效事件
    async fn emit_invalidation_event(&self, event: CacheInvalidationEvent) {
        let listeners = self.invalidation_listeners.read().await;
        for listener in listeners.iter() {
            listener(event.clone());
        }
    }

    /// 根据房间 ID 失效所有成员的缓存
    pub async fn invalidate_room_members(&self, room_id: &OwnedRoomId) {
        self.profiles.write().await.clear(); // 简单起见，清除全部
        self.emit_invalidation_event(CacheInvalidationEvent::RoomMemberInvalidate(room_id.clone()))
            .await;
    }
}

impl Default for ProfileCache {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_cache_set_and_get() {
        let cache = ProfileCache::new();
        let user_id = "@alice:example.com".parse::<OwnedUserId>().unwrap();

        cache
            .set(user_id.clone(), "Alice".to_string(), Some("mxc://example.com/avatar".to_string()))
            .await;

        let result = cache.get(&user_id).await;
        assert!(result.is_some());
        let (name, avatar) = result.unwrap();
        assert_eq!(name, "Alice");
        assert_eq!(avatar, Some("mxc://example.com/avatar".to_string()));
    }

    #[tokio::test]
    async fn test_cache_invalidate() {
        let cache = ProfileCache::new();
        let user_id = "@bob:example.com".parse::<OwnedUserId>().unwrap();

        cache.set(user_id.clone(), "Bob".to_string(), None).await;
        assert!(cache.get(&user_id).await.is_some());

        cache.invalidate(&user_id).await;
        assert!(cache.get(&user_id).await.is_none());
    }

    #[tokio::test]
    async fn test_cache_clear() {
        let cache = ProfileCache::new();
        let user_id = "@charlie:example.com".parse::<OwnedUserId>().unwrap();

        cache.set(user_id, "Charlie".to_string(), None).await;
        assert!(!cache.is_empty().await);

        cache.clear().await;
        assert!(cache.is_empty().await);
    }

    #[tokio::test]
    async fn test_cache_max_entries() {
        let cache = ProfileCache::with_ttl(Duration::from_secs(3600), 2);

        let uid1 = "@user1:example.com".parse::<OwnedUserId>().unwrap();
        let uid2 = "@user2:example.com".parse::<OwnedUserId>().unwrap();
        let uid3 = "@user3:example.com".parse::<OwnedUserId>().unwrap();

        cache.set(uid1, "User1".to_string(), None).await;
        cache.set(uid2, "User2".to_string(), None).await;
        assert_eq!(cache.len().await, 2);

        // 添加第三个时应该淘汰一个
        cache.set(uid3, "User3".to_string(), None).await;
        assert_eq!(cache.len().await, 2);
    }
}
