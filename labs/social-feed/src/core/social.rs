//! 社交关系管理模块 [follow / unfollow / get_following，联动 rate_limit]
//!
//! 包含关注、取关、获取关注列表等功能。

use matrix_sdk::ruma::OwnedRoomId;
use tracing::warn;

use super::feed::SocialFeed;
use crate::{
    services::rate_limit::OperationType,
    types::error::{Result, SocialFeedError},
};

impl SocialFeed {
    /// 关注用户（加入其公开 feed Room）。
    /// feed_room_id 为对方的主页 Room ID。
    pub async fn follow(&mut self, _user_id: &str, feed_room_id: &str) -> Result<()> {
        self.rate_limiter.wait_until_allowed(OperationType::Follow).await;
        let room_id: OwnedRoomId = feed_room_id
            .try_into()
            .map_err(|_| SocialFeedError::InvalidRoomId(feed_room_id.to_string()))?;

        self.client
            .join_room_by_id(&room_id)
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        Ok(())
    }

    /// 取关用户（离开其 feed Room）。
    /// feed_room_id 为对方的 feed Room ID。
    pub async fn unfollow(&mut self, feed_room_id: &str) -> Result<()> {
        let room_id: OwnedRoomId = feed_room_id
            .try_into()
            .map_err(|_| SocialFeedError::InvalidRoomId(feed_room_id.to_string()))?;

        if let Some(room) = self.client.get_room(&room_id) {
            room.leave().await.map_err(|e| SocialFeedError::SdkError(e.to_string()))?;
        } else {
            warn!("Room {} 不在本地缓存中，无法确认当前状态，跳过", feed_room_id);
        }
        Ok(())
    }

    /// 获取关注列表（已加入的 feed Room ID 列表，不含自己的主页）
    pub fn get_following(&self) -> Vec<String> {
        self.joined_feed_room_ids()
    }

    pub(crate) fn joined_feed_room_ids(&self) -> Vec<String> {
        self.client
            .joined_rooms()
            .into_iter()
            .filter(|r| self.is_feed_room(r))
            .filter(|r| self.my_feed_room_id.as_ref().map(|my_id| my_id != r.room_id()).unwrap_or(true))
            .map(|r| r.room_id().to_string())
            .collect()
    }
}
