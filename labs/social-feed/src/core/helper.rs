//! 辅助方法模块 [get_my_room / get_room，被 core 内其他模块调用]
//!
//! 包含内部辅助函数。

use super::feed::SocialFeed;
use crate::types::error::{Result, SocialFeedError};
use matrix_sdk::room::Room;
use matrix_sdk::ruma::OwnedRoomId;

impl SocialFeed {
    pub(crate) fn get_my_room(&self) -> Result<Room> {
        self.my_feed_room_id
            .as_ref()
            .and_then(|id| self.client.get_room(id))
            .ok_or(SocialFeedError::ProfileNotFound)
    }

    pub(crate) fn get_room(&self, room_id: &str) -> Result<Room> {
        let rid: OwnedRoomId = room_id
            .try_into()
            .map_err(|_| SocialFeedError::InvalidRoomId(room_id.to_string()))?;
        self.client.get_room(&rid).ok_or(SocialFeedError::RoomNotFound)
    }
}
