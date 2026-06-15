//! 个人主页管理模块 [create_profile / set_avatar / update_bio / update_location]
//!
//! 包含创建、查询、更新个人主页的相关功能。

use super::feed::SocialFeed;
use crate::types::models::UserProfile;
use crate::types::error::{Result, SocialFeedError};
use matrix_sdk::ruma::{
    api::client::room::create_room::v3::Request as CreateRoomRequest,
    api::client::room::Visibility,
    MxcUri,
};

impl SocialFeed {
    /// 创建个人主页（公开 Room，世界可读）。
    /// 每个用户只能有一个 feed Room，重复调用会返回已有信息。
    pub async fn create_profile(
        &mut self,
        display_name: &str,
    ) -> Result<UserProfile> {
        if self.my_feed_room_id.is_some() {
            return self.get_my_profile().await;
        }

        let room_name = self.config.feed_room_name(display_name);
        let mut request = CreateRoomRequest::new();
        request.name = Some(room_name);
        request.visibility = Visibility::Public;
        request.topic = Some(self.config.feed_room_topic(""));

        let room = self
            .client
            .create_room(request)
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;

        let room_id = room.room_id().to_owned();
        self.my_feed_room_id = Some(room_id.clone());

        let user_id = self
            .client
            .user_id()
            .ok_or(SocialFeedError::NotAuthenticated)?
            .to_string();

        Ok(UserProfile {
            user_id,
            display_name: Some(display_name.to_string()),
            avatar_url: None,
            bio: None,
            location: None,
            feed_room_id: room_id.to_string(),
            follower_count: 0,
            following_count: 0,
            moments_count: 0,
        })
    }

    /// 获取个人主页信息
    pub async fn get_my_profile(&self) -> Result<UserProfile> {
        let room_id = self
            .my_feed_room_id
            .as_ref()
            .ok_or(SocialFeedError::ProfileNotFound)?;

        let room = self.client.get_room(room_id).ok_or(SocialFeedError::RoomNotFound)?;

        let members_count = room.members(matrix_sdk::RoomMemberships::all()).await
            .map(|members| members.len())
            .unwrap_or(0);

        let user_id = self
            .client
            .user_id()
            .ok_or(SocialFeedError::NotAuthenticated)?
            .to_string();

        Ok(UserProfile {
            user_id,
            display_name: room.name().map(|n| n.to_string()),
            avatar_url: None,
            bio: None,
            location: None,
            feed_room_id: room_id.to_string(),
            follower_count: members_count.saturating_sub(1) as u64,
            following_count: 0,
            moments_count: 0,
        })
    }

    /// 设置头像 URL
    /// 
    /// 接收已上传的 mxc:// URI（由客户端上传图片生成）。
    /// 本层只负责协议操作：将 mxc:// URI 写入 Room 状态。
    pub async fn set_avatar(&mut self, mxc_uri: &str) -> Result<()> {
        let room = self.get_my_room()?;
        
        // MxcUri 是 unsized type，需要转换为 &MxcUri
        let avatar_uri: &MxcUri = mxc_uri.try_into()
            .map_err(|_| SocialFeedError::InvalidUrl(mxc_uri.to_string()))?;
        
        room.set_avatar_url(avatar_uri, None)
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;
        
        Ok(())
    }

    /// 更新用户简介
    /// 
    /// 注意：和 update_location 共享同一 topic 字段，
    /// 本方法只替换 bio 部分，保留已有的 Location: 部分。
    pub async fn update_bio(&mut self, bio: &str) -> Result<()> {
        let room = self.get_my_room()?;
        let current_topic = room.topic().unwrap_or_default();
        
        let new_topic = rebuild_topic(&current_topic, Some(bio), None);
        
        room.set_room_topic(&new_topic)
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;
        
        Ok(())
    }

    /// 更新用户位置
    /// 
    /// 注意：和 update_bio 共享同一 topic 字段，
    /// 本方法只替换 Location: 部分，保留已有的 bio。
    pub async fn update_location(&mut self, location: &str) -> Result<()> {
        let room = self.get_my_room()?;
        let current_topic = room.topic().unwrap_or_default();
        
        let new_topic = rebuild_topic(&current_topic, None, Some(location));
        
        room.set_room_topic(&new_topic)
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;
        
        Ok(())
    }

    /// 更新显示名称
    /// 
    /// 通过更新 Room 的 m.room.name 状态事件。
    pub async fn update_display_name(&mut self, display_name: &str) -> Result<()> {
        let room = self.get_my_room()?;
        
        let new_name = self.config.feed_room_name(display_name);
        
        room.set_name(new_name)
            .await
            .map_err(|e| SocialFeedError::SdkError(e.to_string()))?;
        
        Ok(())
    }
}

/// 重建 topic 字符串，bio 和 location 独立更新互不覆盖。
///
/// Topic 格式: `{bio} | Location: {location}`
fn rebuild_topic(current_topic: &str, new_bio: Option<&str>, new_location: Option<&str>) -> String {
    let (mut bio, mut location) = if let Some(pos) = current_topic.find(" | Location:") {
        let after_sep = &current_topic[pos + " | Location:".len()..];
        (&current_topic[..pos], after_sep.trim())
    } else {
        (current_topic, "")
    };

    if let Some(b) = new_bio {
        bio = b;
    }
    if let Some(l) = new_location {
        location = l;
    }

    if bio.is_empty() && location.is_empty() {
        String::new()
    } else if location.is_empty() {
        bio.to_string()
    } else {
        format!("{} | Location: {}", bio, location)
    }
}

#[cfg(test)]
mod tests {
    use super::rebuild_topic;

    #[test]
    fn test_rebuild_topic_empty() {
        assert_eq!(rebuild_topic("", None, None), "");
    }

    #[test]
    fn test_rebuild_topic_set_bio() {
        let result = rebuild_topic("", Some("I like cats"), None);
        assert_eq!(result, "I like cats");
    }

    #[test]
    fn test_rebuild_topic_set_location() {
        let result = rebuild_topic("", None, Some("NYC"));
        assert_eq!(result, " | Location: NYC");
    }

    #[test]
    fn test_rebuild_topic_set_both() {
        let result = rebuild_topic("", Some("I like cats"), Some("NYC"));
        assert_eq!(result, "I like cats | Location: NYC");
    }

    #[test]
    fn test_rebuild_topic_update_bio_preserves_location() {
        let current = "Old bio | Location: NYC";
        let result = rebuild_topic(current, Some("New bio"), None);
        assert_eq!(result, "New bio | Location: NYC");
    }

    #[test]
    fn test_rebuild_topic_update_location_preserves_bio() {
        let current = "I like cats | Location: NYC";
        let result = rebuild_topic(current, None, Some("Paris"));
        assert_eq!(result, "I like cats | Location: Paris");
    }

    #[test]
    fn test_rebuild_topic_update_both_from_existing() {
        let current = "Old bio | Location: NYC";
        let result = rebuild_topic(current, Some("New bio"), Some("Paris"));
        assert_eq!(result, "New bio | Location: Paris");
    }

    #[test]
    fn test_rebuild_topic_remove_location_by_empty() {
        let current = "My bio | Location: NYC";
        // 不传 location（保留旧的），但 bio 也没有的 None 就不能删除 location
        // 本测试验证只更新 bio 时 location 保留
        let result = rebuild_topic(current, Some("My bio"), None);
        assert_eq!(result, "My bio | Location: NYC");
    }

    #[test]
    fn test_rebuild_topic_name_with_location_word() {
        // bio 中包含 "Location:" 字样但不含分隔符的场景
        let current = "讨论 Location: based services";
        // 没有 " | Location:" 分隔符，整个字符串被视为 bio
        let result = rebuild_topic(current, None, Some("NYC"));
        assert_eq!(result, "讨论 Location: based services | Location: NYC");
    }
}
