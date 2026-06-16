//! 信息流和动态管理模块 [post_moment / timeline / user_moments /
//! fetch_room_moments]
//!
//! 包含发布动态、拉取信息流、查看单用户动态等功能。

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use matrix_sdk::{
    room::Room,
    ruma::{events::room::message::RoomMessageEventContent, OwnedRoomId, OwnedUserId},
};
use matrix_sdk_ui::timeline::RoomExt;
use tracing::warn;

use crate::{
    core::feed::SocialFeed,
    services::{aggregation::AggregationStats, rate_limit::OperationType},
    types::{
        error::{Result, SocialFeedError},
        models::Moment,
    },
};

impl SocialFeed {
    /// 发布一条动态到自己的主页，返回 event_id
    pub async fn post_moment(&self, text: &str, image_urls: &[String]) -> Result<String> {
        self.rate_limiter.wait_until_allowed(OperationType::PostMoment).await;
        let room = self.get_my_room()?;

        let content = if image_urls.is_empty() {
            RoomMessageEventContent::text_plain(text)
        } else {
            let md =
                image_urls.iter().map(|u| format!("![]({})", u)).collect::<Vec<_>>().join("\n");
            let md_full = format!("{}\n\n{}", text, md);
            // 使用 text_plain 避免 MD 字符串被当作 HTML 渲染
            RoomMessageEventContent::text_plain(md_full)
        };

        let response =
            room.send(content).await.map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        Ok(response.response.event_id.to_string())
    }

    /// 拉取信息流（关注用户 + 自己，按时间倒序）
    pub async fn timeline(&mut self, page_size: u32) -> Result<Vec<Moment>> {
        let mut room_ids = self.joined_feed_room_ids();
        if let Some(ref id) = self.my_feed_room_id {
            room_ids.push(id.to_string());
        }

        let mut all: Vec<Moment> = Vec::new();
        for rid in &room_ids {
            let parsed: OwnedRoomId =
                rid.as_str().try_into().map_err(|_| SocialFeedError::InvalidRoomId(rid.clone()))?;
            if let Some(room) = self.client.get_room(&parsed) {
                let moments = self.fetch_room_moments(&room, page_size).await?;
                all.extend(moments);
            } else {
                warn!("Room {} 未在本地缓存中找到", rid);
            }
        }

        all.sort_by_key(|m| std::cmp::Reverse(m.created_at));
        Ok(all)
    }

    /// 查看单个用户的动态
    pub async fn user_moments(
        &mut self,
        feed_room_id: &str,
        page_size: u32,
    ) -> Result<Vec<Moment>> {
        let rid: OwnedRoomId = feed_room_id
            .try_into()
            .map_err(|_| SocialFeedError::InvalidRoomId(feed_room_id.to_string()))?;
        let room = self.client.get_room(&rid).ok_or(SocialFeedError::RoomNotFound)?;
        self.fetch_room_moments(&room, page_size).await
    }

    #[allow(clippy::map_entry)]
    pub(crate) async fn fetch_room_moments(
        &mut self,
        room: &Room,
        page_size: u32,
    ) -> Result<Vec<Moment>> {
        let timeline =
            room.timeline().await.map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        let items = timeline.items().await;

        struct RawMsg {
            event_id: String,
            sender: OwnedUserId,
            text: String,
            ts: DateTime<Utc>,
        }

        let mut raw_msgs: Vec<RawMsg> = Vec::new();

        for item in items.iter().take(page_size as usize) {
            let Some(event) = item.as_event() else { continue };
            let Some(msg) = event.content().as_message() else { continue };

            let text = msg.body().to_owned();
            let ts = event
                .timestamp()
                .to_system_time()
                .map(DateTime::from)
                .unwrap_or_else(Utc::now);
            let event_id = match event.event_id() {
                Some(id) => id.to_string(),
                None => continue,
            };

            raw_msgs.push(RawMsg {
                event_id: event_id.clone(),
                sender: event.sender().to_owned(),
                text,
                ts,
            });
        }

        // 用 AggregationCache 批量更新计数（替代手写 HashMap）
        let room_id_str = room.room_id().to_string();
        let mut batch_updates: Vec<(String, String, AggregationStats)> = Vec::new();

        let mut like_counts: HashMap<String, u64> = HashMap::new();

        for item in items.iter() {
            let Some(event) = item.as_event() else { continue };

            // 点赞计数
            if let Some(reactions) = event.content().reactions() {
                let reaction_count: u64 =
                    reactions.values().map(|by_user| by_user.len() as u64).sum();
                if reaction_count > 0 {
                    let target_id = event.event_id().map(|id| id.to_string()).unwrap_or_default();
                    *like_counts.entry(target_id).or_insert(0) += reaction_count;
                }
            }
        }

        // 构造批量更新，写入 aggregation cache
        for msg in &raw_msgs {
            let likes = like_counts.get(&msg.event_id).copied().unwrap_or(0);
            batch_updates.push((
                room_id_str.clone(),
                msg.event_id.clone(),
                AggregationStats { like_count: likes, reply_count: 0, forward_count: 0 },
            ));
        }

        // 异步写入缓存
        self.aggregation_cache.update_batch(batch_updates).await;

        // 获取发送者 display names（使用 ProfileCache 和 Room member 信息）
        let mut sender_names: HashMap<String, String> = HashMap::new();
        for msg in &raw_msgs {
            let uid = &msg.sender;
            let uid_str = uid.to_string();

            if !sender_names.contains_key(&uid_str) {
                // 先检查缓存
                let display_name = if let Some((name, _avatar)) = self.profile_cache.get(uid).await
                {
                    name
                } else {
                    // 缓存未命中，尝试从 Room members 获取
                    let name = if let Ok(members) =
                        room.members(matrix_sdk::RoomMemberships::all()).await
                    {
                        members
                            .iter()
                            .find(|m| m.user_id() == uid)
                            .and_then(|m| m.display_name())
                            .map(|n| n.to_string())
                            .or_else(|| Some(uid_str.clone()))
                            .unwrap_or_else(|| uid_str.clone())
                    } else {
                        uid_str.clone()
                    };

                    // 缓存结果
                    self.profile_cache.set(uid.clone(), name.clone(), None).await;
                    name
                };

                sender_names.insert(uid_str, display_name);
            }
        }

        // 构建 Moment 列表
        let mut moments = Vec::new();
        for msg in raw_msgs {
            let author_name = sender_names
                .get(&msg.sender.to_string())
                .cloned()
                .unwrap_or_else(|| msg.sender.to_string());

            moments.push(Moment {
                id: msg.event_id.clone(),
                author_id: msg.sender.to_string(),
                author_name,
                author_avatar: None,
                text: msg.text.clone(),
                images: if self.config.enable_image_extraction {
                    crate::utils::images::extract_all_images(&msg.text)
                } else {
                    vec![]
                },
                created_at: msg.ts,
                like_count: like_counts.get(&msg.event_id).copied().unwrap_or(0),
                comment_count: 0, // TODO: 接入 m.in_reply_to 计数（需 SDK 暴露 relation 字段）
            });
        }

        Ok(moments)
    }
}
